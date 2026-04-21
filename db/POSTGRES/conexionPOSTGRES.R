library(DBI)
library(RPostgres)
library(sf)

# =============================================================================
## CONEXIÓN A POSTGRESQL ----
# =============================================================================

#' Abre una conexión a la base de datos PostgreSQL/QGIS de la IMM.
#'
#' Usá dbDisconnect(con) cuando termines de trabajar para liberar la conexión.
#'
#' @param host     Host del servidor.
#' @param port     Puerto.
#' @param dbname   Nombre de la base de datos.
#' @param user     Usuario.
#' @param password Contraseña.
#' @return Objeto de conexión DBI.
conectar_postgres <- function(
  host     = "pdbqgistest.imm.gub.uy",
  port     = 5411,
  dbname   = "qgis",
  user     = "qgis",
  password = "mapa22"
) {
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    dbname   = dbname,
    host     = host,
    port     = port,
    user     = user,
    password = password
  )
  cat("Conectado a:", dbname, "en", host, "\n")
  con
}

#' Lista todas las tablas disponibles en la base de datos.
#'
#' @param con Conexión DBI activa.
#' @return Data frame con columnas table_schema y table_name.
listar_tablas_postgres <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_type = 'BASE TABLE'
      AND table_schema NOT IN ('information_schema', 'pg_catalog')
    ORDER BY table_schema, table_name;
  ")
}

# =============================================================================
## LLAMADA ----
# =============================================================================

con <- conectar_postgres()

# Opcional: ver qué tablas hay disponibles
# tablas <- listar_tablas_postgres(con)
# print(tablas)

# Al terminar de trabajar, cerrar la conexión:
# dbDisconnect(con)

# =============================================================================
## LEER CAPAS ----
# =============================================================================

#' Carga una capa espacial (o tabla) desde PostgreSQL.
#'
#' @param con     Conexión DBI activa (salida de conectar_postgres()).
#' @param tabla   Nombre de la tabla en la base de datos.
#' @param schema  Esquema donde está la tabla (por defecto "public").
#' @return Objeto sf con la capa cargada.
leer_capa_postgres <- function(con, tabla, schema = "public") {
  cat("Leyendo:", schema, "::", tabla, "...\n")
  tryCatch(
    sf::st_read(con, DBI::Id(schema = schema, table = tabla), quiet = TRUE),
    error = function(e) {
      message("Error al leer '", tabla, "': ", e$message)
      NULL
    }
  )
}

#' Descarga una capa desde PostgreSQL y la guarda en disco (RDS + GPKG).
#'
#' Estructura generada:
#'   <base_dir>/RDS/<tabla>.rds
#'   <base_dir>/GPKG/capas.gpkg  (la capa se agrega/reemplaza dentro del GPKG)
#'
#' @param con      Conexión DBI activa.
#' @param tabla    Nombre de la tabla.
#' @param schema   Esquema (por defecto "public").
#' @param base_dir Carpeta raíz de almacenamiento.
#' @return El objeto sf descargado (invisible).
actualizar_capa_postgres <- function(con, tabla, schema = "public", base_dir = "db/POSTGRES") {

  # 1. Leer desde la base
  sf_obj <- leer_capa_postgres(con, tabla, schema)
  if (is.null(sf_obj)) {
    message("No se pudo actualizar '", tabla, "': la capa no se descargó.")
    return(invisible(NULL))
  }

  # Nombre de archivo seguro (reemplaza espacios y caracteres especiales)
  nombre_archivo <- gsub("[^a-zA-Z0-9_]", "_", tabla)

  # 2. Guardar RDS
  dir_rds <- file.path(base_dir, "RDS")
  dir.create(dir_rds, recursive = TRUE, showWarnings = FALSE)
  ruta_rds <- file.path(dir_rds, paste0(nombre_archivo, ".rds"))
  saveRDS(sf_obj, ruta_rds)
  cat("  RDS  guardado:", ruta_rds, "\n")

  # 3. Guardar GPKG (reemplaza la capa si ya existe)
  dir_gpkg  <- file.path(base_dir, "GPKG")
  dir.create(dir_gpkg, recursive = TRUE, showWarnings = FALSE)
  gpkg_path <- file.path(dir_gpkg, "capas.gpkg")

  # Borramos la capa del GPKG si ya existe para actualizarla limpia
  if (file.exists(gpkg_path)) {
    capas_existentes <- tryCatch(sf::st_layers(gpkg_path)$name, error = function(e) character(0))
    if (nombre_archivo %in% capas_existentes) {
      sf::st_delete(gpkg_path, layer = nombre_archivo)
    }
  }
  sf::st_write(sf_obj, dsn = gpkg_path, layer = nombre_archivo,
               driver = "GPKG", append = TRUE, quiet = TRUE)
  cat("  GPKG guardado:", gpkg_path, "(capa:", nombre_archivo, ")\n")

  invisible(sf_obj)
}

# ---------------------------------------------------------------

#' Carga una capa desde disco (sin necesitar conexión a la base de datos).
#'
#' @param tabla    Nombre de la tabla (el mismo que se usó en actualizar_capa_postgres).
#' @param base_dir Carpeta raíz de almacenamiento.
#' @param formato  "RDS" o "GPKG".
#' @return Objeto sf.
cargar_capa_local_postgres <- function(tabla, base_dir = "db/POSTGRES", formato = c("RDS", "GPKG")) {
  formato        <- match.arg(formato)
  nombre_archivo <- gsub("[^a-zA-Z0-9_]", "_", tabla)

  if (formato == "RDS") {
    ruta <- file.path(base_dir, "RDS", paste0(nombre_archivo, ".rds"))
    if (!file.exists(ruta)) stop("No existe el archivo: ", ruta)
    cat("Cargando desde RDS:", ruta, "\n")
    readRDS(ruta)

  } else {
    gpkg_path <- file.path(base_dir, "GPKG", "capas.gpkg")
    if (!file.exists(gpkg_path)) stop("No existe el archivo: ", gpkg_path)
    cat("Cargando desde GPKG:", gpkg_path, "(capa:", nombre_archivo, ")\n")
    sf::st_read(gpkg_path, layer = nombre_archivo, quiet = TRUE)
  }
}

# =============================================================================
## PRUEBA / EJEMPLOS DE USO ----
# =============================================================================

# --- PASO 1: actualizar desde la base (requiere conexión) ---
con <- conectar_postgres()
capa_intra <- actualizar_capa_postgres(con, "Intradomiciliario_operativo")
dbDisconnect(con)

# --- PASO 2: la próxima vez, cargar desde disco (sin conexión) ---
# capa_intra <- cargar_capa_local_postgres("Intradomiciliario_operativo")
# capa_intra <- cargar_capa_local_postgres("Intradomiciliario_operativo", formato = "GPKG")

# --- Verificar que cargó bien ---
# nrow(capa_intra)
# names(capa_intra)
# plot(sf::st_geometry(capa_intra))

# =============================================================================

capa_Circuitos_intradomiciliaria <- st_read(con, Id(schema = "public", table = "Circuitos_intradomiciliaria"))
capa_circuitos_con_turnos_y_frecuencias <- st_read(con, Id(schema = "public", table = "Circuitos con turnos y frecuencias"))
capa_v_mdg_accesos <- st_read(con, Id(schema = "public", table = "v_mdg_accesos"))
capa_pos_ferias <- st_read(con, Id(schema = "public", table = "pos_ferias"))
capa_imm_municipios <- st_read(con, Id(schema = "public", table = "imm_municipios"))
capa_DEPARTAMENTO <- st_read(con, Id(schema = "public", table = "DEPARTAMENTO"))
capa_ESPACIOS_LIBRES <- st_read(con, Id(schema = "public", table = "ESPACIOS LIBRES"))

capa_Intradomiciliario_operativo <- st_read(con, Id(schema = "public", table = "ESPACIOS LIBRES"))


# 
# 15       public                                      FIDEICOMISO_POSICIONES_MR
# 16       public                                            FIDEICOMISO_RUTA_MR
# 17       public                                            FIDEICOMISO_ZONA_MR
# 
# 19       public                                    INTRADOMICILIARIO_PROPUESTA
# 20       public                                                  Intra_proximo
# 21       public                                    Intradomiciliario_operativo
# 
# 26       public                          Obras Viales (Afectaciones laterales)
# 27       public                                                   Obras viales
# 28       public                                  Obras viales (cambio de ruta)
# 
# 32       public                                              PLUMA_movimientos
# 
# 44       public                             Puntos operativos de Div. Limpieza
# 45       public                                                  RBB_Operativo
# 46       public                                              RBB_beneficiarios
# 47       public                                                     RBB_puntos
# 
# 50       public                                       RECOLECCION MANUAL A PIE
# 51       public                                      RECOLECCION MANUAL PUNTOS
# 52       public                                       RECOLECCION MANUAL RUTAS
# 53       public                                       RECOLECCION MANUAL ZONAS
# 
# 65       public                                                        barrios
# 67       public                                   ide:ide_v_sig_comunales_ubic
# 68       public                                  ide:ide_v_sig_municipios_ubic
# 71       public                          imm:mobile_v_mdg_vias_multilinestring







# 2. Leemos la capa específica
# 'public' es el esquema y 'Intradomiciliario_operativo' es la tabla
capa_intra <- st_read(con, Id(schema = "public", table = "Intradomiciliario_operativo"))
capa_intra_proximo <- st_read(con, Id(schema = "public", table = "Intra_proximo"))


########################## CREO LAS MATRICULAS CON SUS CAMIONES Y CSOO

# Crear el data frame con la información de la flota
df_flota <- data.frame(
  Matricula = c(
    1858, 2196, 2198, 2199, 2202, 2203, 2640, 2980, 3156, 3157, 3159, 3160, 3161, 3162, # Canton 2
    1862, 3008, 1891, 1900, 3014, 2619, 3114, 3116, 3117, 3119,                         # Sin Base
    2184, 2185, 2188, 2200, 2201, 2204, 2205, 2463, 3115, 3128, 3129, 3155              # Haiti
  ),
  Marca = c(
    rep("Freighliner", 8), rep("Scania 280", 6), # Canton 2
    rep("Freighliner", 6), rep("Scania 280", 4), # Sin Base
    rep("Freighliner", 8), rep("Scania 280", 4)  # Haiti
  ),
  Base = c(
    rep("Canton 2", 14),
    rep("", 10),
    rep("Haiti", 12)
  ),
  Servicio = c(
    rep("Mezclado", 24),
    rep("Reciclable", 12)
  ),
  stringsAsFactors = FALSE
)

# Agregar el prefijo "SIM" a la columna Matricula
df_flota$Matricula <- paste0("SIM", df_flota$Matricula)


########################



## PRUEBA MAPAS
#st_write(capa_intra, "vistas/mapas/capa_intra_montevideo.geojson", driver = "GeoJSON", delete_dsn = TRUE)
capa_filtrada_CAPURRO_2 <- capa_intra[capa_intra$nombre == "CAPURRO 2", ] # Ejemplo de filtro

capa_filtrada_CARRASCO_2 <- capa_intra[capa_intra$nombre == "CARRASCO 2", ] # Ejemplo de filtro


# --- 1. PREPARAR CAPA TERRITORIAL FILTRADA ---
temp_path_intra <- tempfile(fileext = ".geojson")
st_write(capa_filtrada_CARRASCO_2, temp_path_intra, driver = "GeoJSON")

# Capa json del recorrido del camion
capa_recorrido <- st_read("vistas/mapas/SIM_reciclable.json")

# --- 2. CALCULAR PUNTOS SUPERPUESTOS (INTERSECCIÓN) ---
# Aseguramos misma proyección
capa_recorrido <- st_transform(capa_recorrido, st_crs(capa_filtrada_CARRASCO_2))
# Intersección: Solo los puntos que cayeron dentro de Capurro
puntos_solapados <- st_intersection(capa_recorrido, capa_filtrada_CARRASCO_2)

# Extraemos el valor de referencia
matricula_ref <- puntos_solapados$matricula[1]

# Buscamos el servicio
servicio_encontrado <- df_flota %>% 
  filter(Matricula == matricula_ref) %>% 
  pull(Servicio)

# Asignamos (si el resultado tiene datos)
if(length(servicio_encontrado) > 0) {
  puntos_solapados <- puntos_solapados %>% 
    mutate(FRACCION = servicio_encontrado[1])
}

temp_path_puntos <- tempfile(fileext = ".geojson")
st_write(puntos_solapados, temp_path_puntos, driver = "GeoJSON")





# --- 3. LLAMAR A PYTHON CON DOS ARGUMENTOS ---
# El primer argumento será sys.argv[1] y el segundo sys.argv[2]
system2(python_venv, args = c("vistas/mapas/mapa_intra.py", 
                              temp_path_intra, 
                              temp_path_puntos))

system2(python_venv, args = c("vistas/mapas/mapa_intra_estatico.py", 
                              temp_path_intra, 
                              temp_path_puntos))


# system2(python_venv, args = "vistas/mapas/mapa_intra_hormiga.py")









##### MAPA BASE IM ----

# Instalación si no los tenés
# install.packages("leaflet")

library(leaflet)

# La URL base para el servicio WMS de GeoWebCache suele ser esta:
wms_url <- "https://montevideo.gub.uy/app/geowebcache/service/wms"

leaflet() %>%
  addTiles() %>% # Capa base de OpenStreetMap (opcional, para referencia)
  addWMSTiles(
    baseUrl = wms_url,
    layers = "mapstore-base:capas_base",
    options = WMSTileOptions(
      format = "image/png",
      transparent = TRUE,
      version = "1.1.1" # Versión estándar compatible
    ),
    attribution = "Cartografía Básica - Intendencia de Montevideo"
  ) %>%
  # Centramos el mapa en Montevideo
  setView(lng = -56.16, lat = -34.90, zoom = 12)


#### mapa prueba con base im y municipois ----


library(leaflet)
library(sf)

# 1. Preparar la capa de municipios (Asegurar WGS84)
municipios_web <- st_transform(capa_imm_municipios, 4326)

# 2. Crear el mapa con ambas capas
mapa_completo <- leaflet() %>%
  # --- CAPA 1: El fondo (WMS de la IM) ---
  addWMSTiles(
    baseUrl = "https://montevideo.gub.uy/app/geowebcache/service/wms",
    layers = "mapstore-base:capas_base",
    options = WMSTileOptions(
      format = "image/png", 
      transparent = TRUE
    ),
    attribution = "Cartografía Básica - IM",
    group = "Mapa Base (WMS)"
  ) %>%
  
  # --- CAPA 2: Los polígonos (Tus datos de municipios) ---
  addPolygons(
    data = municipios_web,
    color = "blue",          # Color de la línea del borde
    weight = 2,              # Grosor de la línea
    fillColor = "royalblue", # Color del relleno
    fillOpacity = 0.2,       # Opacidad baja para ver las calles debajo
    label = ~muninom,        # Etiqueta al pasar el mouse
    group = "Municipios"
  ) %>%
  
  addPolygons(
    data = capa_intra,
    color = "red",          # Borde rojo
    weight = 1,
    fillColor = "orange",   # Relleno naranja
    fillOpacity = 0.3,
    label = ~nombre, # Cambia esto por el nombre de la columna en tus datos
    group = "nombre"       # Nombre del grupo para el control
  ) %>%
  
  # --- EXTRAS: Controles ---
  addLayersControl(
    overlayGroups = c("Mapa Base (WMS)", "Municipios"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  setView(lng = -56.16, lat = -34.85, zoom = 11)

# Mostrar el mapa
mapa_completo

library(htmlwidgets)
saveWidget(mapa_completo, "Mapa_Total_Montevidex.html", selfcontained = TRUE)


#### mapa base + contenedores historico ----
library(leaflet)
library(leaflet.extras)
library(sf)
library(htmlwidgets)

# 1. Transformación de capas
municipios_web <- st_transform(capa_imm_municipios, 4326)
historico_web  <- st_transform(HISTORICO_posiciones_de_baja, 4326)

# 2. Construcción del Mapa
mapa_final <- leaflet() %>%
  addWMSTiles(
    baseUrl = "https://montevideo.gub.uy/app/geowebcache/service/wms",
    layers = "mapstore-base:capas_base",
    options = WMSTileOptions(format = "image/png", transparent = TRUE),
    group = "Mapa Base (IM)"
  ) %>%
  
  addPolygons(
    data = municipios_web,
    color = "#444444", weight = 1, fillColor = "blue", fillOpacity = 0.1,
    label = ~paste0("Municipio ", muninom),
    group = "Municipios"
  ) %>%
  
  addCircleMarkers(
    data = historico_web,
    radius = 5, color = "red", stroke = FALSE, fillOpacity = 0.7,
    group = "Puntos de Baja",
    label = ~as.character(GID),
    popup = ~paste0("<b>GID:</b> ", GID, "<br><b>Recorrido:</b> ", COD_RECORRIDO)
  ) %>%
  
  # --- AQUÍ ESTÁ EL CAMBIO IMPORTANTE ---
  # Usamos searchOptions() para pasarle el placeholder correctamente
  addSearchOSM(
    options = searchOptions(
      textPlaceholder = "Buscar dirección (ej: 18 de Julio y Ejido)",
      zoom = 16,
      collapsed = FALSE # Para que el buscador aparezca ya abierto
    )
  ) %>%
  
  # Buscador de tus datos (GID)
  addSearchFeatures(
    targetGroups = "Puntos de Baja",
    options = searchFeaturesOptions(
      zoom = 18, 
      openPopup = TRUE,
      textPlaceholder = "Buscar por GID..."
    )
  ) %>%
  
  addLayersControl(
    overlayGroups = c("Municipios", "Puntos de Baja"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  setView(lng = -56.16, lat = -34.85, zoom = 12)

# 3. Guardar el archivo
saveWidget(mapa_final, file = "Reporte_Geografico_IM.html", selfcontained = TRUE)

# Mostrar el mapa
mapa_final