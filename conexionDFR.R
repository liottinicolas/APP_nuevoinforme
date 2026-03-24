# Conectarse y cargar capas DFR ----

## 1) CARGAR PAQUETES NECESARIOS -----
if (!requireNamespace("rstudioapi", quietly = TRUE)) install.packages("rstudioapi")
library(httr)
library(xml2)
library(sf)
library(stringr)
library(rstudioapi)

## 2) PARÁMETROS DE CONEXIÓN (INTERACTIVOS) ----

url_base <- "https://geoserver-ed.imm.gub.uy/geoserver/wfs"

# Pedimos usuario y contraseña de forma segura
usuario    <- showPrompt("Acceso Geoserver", "Usuario IMM (ej: im4445285)", default = "im4445285")
contrasena <- askForPassword("Contraseña de la IMM")

# Validación simple por si el usuario cancela
if (is.null(usuario) || is.null(contrasena)) {
  stop("Operación cancelada: se requieren credenciales.")
}

## 3) OBTENER GetCapabilities CON AUTENTICACIÓN ----

resp_caps <- GET(
  url_base,
  authenticate(usuario, contrasena),
  query = list(
    service = "WFS",
    version = "1.0.0",
    request = "GetCapabilities"
  )
)

# Si el usuario o contraseña están mal, esto saltará aquí
stop_for_status(resp_caps) 

caps_xml <- content(resp_caps, as = "text", encoding = "UTF-8")

## 4) PARSEAR XML ----

doc <- read_xml(caps_xml)
ft_nodes <- xml_find_all(doc, "//*[local-name()='FeatureType']/*[local-name()='Name']")
ft_names <- xml_text(ft_nodes)

cat("Se encontraron", length(ft_names), "capas disponibles.\n")

## 5) DESCARGAR CAPAS AUTOMÁTICAMENTE ----

lista_sf <- list()

# Filtramos los nombres para que solo busque las que empiezan con 'dfr:'
# Esto hará que el script sea MUCHO más rápido.
capas_interes <- ft_names[str_detect(ft_names, "^dfr:")]


cat("Se encontraron", length(capas_interes), "capas del área DFR para descargar.\n")

for (nombre_ft in capas_interes) { 
  
  cat("Leyendo:", nombre_ft, "...\n")
  
  # Construcción del DSN con credenciales codificadas
  dsn <- paste0(
    "WFS:",
    "https://", URLencode(usuario, reserved = TRUE), ":", URLencode(contrasena, reserved = TRUE),
    "@geoserver-ed.imm.gub.uy/geoserver/wfs?",
    "service=WFS&version=1.0.0&request=GetFeature&typename=", nombre_ft,
    "&srsname=EPSG:32721&outputFormat=application/json"
  )
  
  sf_obj <- tryCatch({
    # Aumentamos el tiempo de espera (timeout) porque las capas HISTORICO son pesadas
    st_read(dsn = dsn, quiet = TRUE)
  }, error = function(e) {
    message("⚠️ Error al leer ", nombre_ft, ": ", e$message)
    return(NULL)
  })
  
  if (!is.null(sf_obj)) {
    # IMPORTANTE: Guardamos con el nombre completo (incluyendo dfr:)
    # para que tus líneas de código de abajo funcionen.
    lista_sf[[nombre_ft]] <- sf_obj
  }
}

# Limpiar contraseña de la memoria por seguridad
rm(contrasena)

cat("\nProceso terminado. Capas cargadas en la lista 'lista_sf'.\n")



# Leer las capas ----

HISTORICO_posiciones_de_baja <- lista_sf[["dfr:C_DF_POSICIONES_RECORRIDO_HISTORICO"]]
HISTORICO_Rutas_recorrido_de_baja <- lista_sf[["dfr:C_DF_RUTAS_RECORRIDO_HISTORICO"]]
# C_DF_ZONA_RECORRIDO_HISTORICO <- lista_sf[["dfr:C_DF_ZONA_RECORRIDO_HISTORICO"]]
# C_DIRECCIONES <- lista_sf[["dfr:C_DIRECCIONES"]]
# E_DF_CAP_CIRCUITOS <- lista_sf[["dfr:E_DF_CAP_CIRCUITOS"]]
# E_DF_CAP_CONTENEDORES <- lista_sf[["dfr:E_DF_CAP_CONTENEDORES"]]
# E_DF_CONTENEDORES_SOTERRADOS <- lista_sf[["dfr:E_DF_CONTENEDORES_SOTERRADOS"]]
# E_DF_POSICIONES_RECORRIDO <- lista_sf[["dfr:E_DF_POSICIONES_RECORRIDO"]]
# E_DF_POSICIONES_RECORRIDO_PL <- lista_sf[["dfr:E_DF_POSICIONES_RECORRIDO_PL"]]

# E_DF_RUTAS_RECORRIDO_PLAN <- lista_sf[["dfr:E_DF_RUTAS_RECORRIDO_PLAN"]]
# E_DF_ZONA_RECORRIDO <- lista_sf[["dfr:E_DF_ZONA_RECORRIDO"]]
# E_DF_ZONA_RECORRIDO_PLAN <- lista_sf[["dfr:E_DF_ZONA_RECORRIDO_PLAN"]]





## RUTAS ----

Rutas_recorrido_vigente <- lista_sf[["dfr:E_DF_RUTAS_RECORRIDO"]]

### Funcion para dibujar rutas ----

#' Dibuja rutas seleccionadas o todas, con opción de color único o distinto
#'
#' @param rutas_df sf con geometría LINESTRING/MULTILINESTRING.
#' @param valores vector con valores a filtrar. Si es NULL, dibuja TODO el dataframe.
#' @param campo nombre de columna por la que filtrar e identificar (p.ej. "NOM_RUT").
#' @param colorear_distinto lógico. Si es TRUE, cada ruta única tendrá un color distinto. 
#'                          Si es FALSE, todas serán de color único.
#' @param color_unico color para todas las líneas si colorear_distinto es FALSE.
#' @return htmlwidget leaflet.
drawRutasPorCodigoLeaflet <- function(rutas_df, 
                                      valores = NULL,
                                      campo = "NOM_RUT",
                                      geom_col = NULL,
                                      colorear_distinto = FALSE, # NUEVO PARÁMETRO
                                      color_unico = "blue",      # NUEVO PARÁMETRO
                                      tile_provider = c("OpenStreetMap","CartoDB","Stamen")) {
  
  tile_provider <- match.arg(tile_provider)
  stopifnot(inherits(rutas_df, "sf"))
  
  if (!is.null(geom_col)) sf::st_geometry(rutas_df) <- geom_col
  if (is.na(sf::st_crs(rutas_df))) stop("Definí el CRS del sf antes de transformar.")
  if (!campo %in% names(rutas_df)) stop("Campo inexistente para identificar: ", campo)
  
  # --- Lógica de Filtrado (igual que antes) ---
  if (is.null(valores)) {
    sel <- rutas_df
  } else {
    vals <- unique(as.character(valores))
    sel  <- rutas_df[rutas_df[[campo]] %in% vals, , drop = FALSE]
  }
  
  if (!nrow(sel)) stop("El dataframe está vacío o no hay coincidencias.")
  
  # --- Procesamiento Geográfico ---
  sel  <- sf::st_make_valid(sel)
  rutas_ll <- sf::st_transform(sel, 4326)
  
  # Popup robusto (igual que antes)
  cols <- intersect(c("id","COD_RECORRIDO","NOM_RUT","FECHA_DESDE","FECHA_HASTA","MUNICIPIO"), names(rutas_ll))
  if (length(cols)) {
    parts <- lapply(cols, function(k) sprintf("<strong>%s:</strong> %s", k, as.character(rutas_ll[[k]])))
    rutas_ll$popup <- vapply(seq_len(nrow(rutas_ll)), function(i) paste(vapply(parts, `[`, "", i), collapse="<br/>"), "")
  } else {
    rutas_ll$popup <- "Ruta"
  }
  
  # --- Renderizado Leaflet ---
  m <- leaflet::leaflet(rutas_ll)
  m <- switch(tile_provider,
              CartoDB       = leaflet::addProviderTiles(m, "CartoDB.Positron"),
              Stamen        = leaflet::addProviderTiles(m, "Stamen.TonerLite"),
              OpenStreetMap = leaflet::addTiles(m))
  
  # --- NUEVA LÓGICA DE COLOR Y LEYENDA ---
  
  if (colorear_distinto) {
    # 1. Crear paleta dinámica basada en los nombres únicos del campo
    # Usamos 'viridis' porque es buena para distinguir colores, pero puedes cambiarla.
    pal <- leaflet::colorFactor(palette = "viridis", domain = rutas_ll[[campo]])
    
    # 2. Dibujar polilíneas usando la paleta (~pal(...))
    # NOTA: Usamos get(campo) para extraer dinámicamente el valor de la columna
    m <- leaflet::addPolylines(m, color = ~pal(get(campo)), weight = 3, opacity = 0.8, popup = ~popup)
    
    # 3. Agregar leyenda completa que mapea colores a nombres
    m <- leaflet::addLegend(m, position = "bottomright", 
                            pal = pal, 
                            values = ~get(campo), 
                            title = paste("Rutas (", campo, ")", sep=""))
    
  } else {
    # Lógica de color ÚNICO (como antes)
    m <- leaflet::addPolylines(m, color = color_unico, weight = 3, opacity = 0.7, popup = ~popup)
    
    # Leyenda simple
    if (is.null(valores)) {
      label_leyenda <- "Todas las rutas"
    } else {
      label_leyenda <- paste0(campo, ": ", paste(valores, collapse=", "))
    }
    
    m <- leaflet::addLegend(m, position = "bottomright", 
                            colors = color_unico,
                            labels = label_leyenda,
                            title = "Líneas")
  }
  
  return(m)
}

# Dibujar todo, mismo color.
rutas_completas <- drawRutasPorCodigoLeaflet(Rutas_recorrido_vigente)

# Dibujar todo, distinto color.
rutas_completas_pintado <- drawRutasPorCodigoLeaflet(Rutas_recorrido_vigente,
                                             colorear_distinto = TRUE)

# Por defecto filtra por "COD_RECORRIDO"
mapa1 <- drawRutasPorCodigoLeaflet(E_DF_RUTAS_RECORRIDO, valores = "B_DU_RM_CL_101")

# Varios códigos
mapa2 <- drawRutasPorCodigoLeaflet(E_DF_RUTAS_RECORRIDO, valores = c("B_DU_RM_CL_101","B_DU_RM_CL_102"),
                                   colorear_distinto = TRUE)


dbDisconnect(con)