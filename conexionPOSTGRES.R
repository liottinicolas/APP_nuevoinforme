library(DBI)
library(RPostgres)
library(sf)

# 1. Creamos la conexión (usando los datos de tu cadena de texto)
con <- dbConnect(
  RPostgres::Postgres(),
  dbname = 'qgis',
  host = 'pdbqgistest.imm.gub.uy',
  port = 5411,
  user = 'qgis',      # El usuario que mencionaste
  password = 'mapa22' # La contraseña que mencionaste
)

# Consultar el catálogo de la base de datos
query <- "
  SELECT table_schema, table_name 
  FROM information_schema.tables 
  WHERE table_type = 'BASE TABLE' 
  AND table_schema NOT IN ('information_schema', 'pg_catalog')
  ORDER BY table_schema, table_name;
"

info_tablas <- dbGetQuery(con, query)
print(info_tablas)

#####

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





## PRUEBA MAPAS
#st_write(capa_intra, "vistas/mapas/capa_intra_montevideo.geojson", driver = "GeoJSON", delete_dsn = TRUE)
capa_filtrada_CAPURRO_2 <- capa_intra[capa_intra$nombre == "CAPURRO 2", ] # Ejemplo de filtro

# --- 1. PREPARAR CAPA TERRITORIAL FILTRADA ---
temp_path_intra <- tempfile(fileext = ".geojson")
st_write(capa_filtrada_CAPURRO_2, temp_path_intra, driver = "GeoJSON")

# Capa json del recorrido del camion
capa_recorrido <- st_read("vistas/mapas/SIM.json")

# --- 2. CALCULAR PUNTOS SUPERPUESTOS (INTERSECCIÓN) ---
# Aseguramos misma proyección
capa_recorrido <- st_transform(capa_recorrido, st_crs(capa_filtrada_CAPURRO_2))
# Intersección: Solo los puntos que cayeron dentro de Capurro
puntos_solapados <- st_intersection(capa_recorrido, capa_filtrada_CAPURRO_2)

temp_path_puntos <- tempfile(fileext = ".geojson")
st_write(puntos_solapados, temp_path_puntos, driver = "GeoJSON")

# --- 3. LLAMAR A PYTHON CON DOS ARGUMENTOS ---
# El primer argumento será sys.argv[1] y el segundo sys.argv[2]
system2(python_venv, args = c("vistas/mapas/mapa_intra.py", 
                              temp_path_intra, 
                              temp_path_puntos))


system2(python_venv, args = "vistas/mapas/mapa_intra_hormiga.py")









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