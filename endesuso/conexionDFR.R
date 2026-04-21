# Conectarse y cargar capas DFR ----

## 1) CARGAR PAQUETES NECESARIOS -----
if (!requireNamespace("rstudioapi", quietly = TRUE)) install.packages("rstudioapi")
library(httr)
library(xml2)
library(sf)
library(stringr)
library(rstudioapi)
library(leaflet)
library(leaflet.extras)
library(htmlwidgets)
library(dplyr)

## 2) FUNCIÓN DE CONEXIÓN Y DESCARGA ----

#' Conecta al GeoServer de la IMM y descarga capas WFS filtradas por prefijo.
#'
#' @param url_base URL del endpoint WFS.
#' @param prefijo  Regex para filtrar nombres de capas (ej: "^dfr:", "^urb:").
#' @param usuario  Opcional. Si es NULL, se pide por prompt interactivo.
#' @return Lista nombrada con los objetos sf descargados.
cargar_capas_wfs <- function(
  url_base = "https://geoserver-ed.imm.gub.uy/geoserver/wfs",
  prefijo = "^dfr:",
  usuario = NULL
) {
  # -- Credenciales --
  if (is.null(usuario)) {
    usuario <- rstudioapi::showPrompt(
      "Acceso Geoserver", "Usuario IMM (ej: im4445285)",
      default = "im4445285"
    )
  }
  contrasena <- rstudioapi::askForPassword("Contraseña de la IMM")

  if (is.null(usuario) || is.null(contrasena)) {
    stop("Operación cancelada: se requieren credenciales.")
  }

  on.exit(rm(contrasena), add = TRUE) # limpia aunque falle

  # -- GetCapabilities --
  resp_caps <- httr::GET(
    url_base,
    httr::authenticate(usuario, contrasena),
    query = list(service = "WFS", version = "1.0.0", request = "GetCapabilities")
  )
  httr::stop_for_status(resp_caps)

  doc <- xml2::read_xml(httr::content(resp_caps, as = "text", encoding = "UTF-8"))
  ft_names <- xml2::xml_text(xml2::xml_find_all(
    doc, "//*[local-name()='FeatureType']/*[local-name()='Name']"
  ))

  capas_interes <- ft_names[stringr::str_detect(ft_names, prefijo)]
  cat("Descargando", length(capas_interes), "capas (prefijo '", prefijo, "')...\n")

  # -- Descarga --
  lista_sf <- list()

  for (nombre_ft in capas_interes) {
    cat("  Leyendo:", nombre_ft, "...\n")

    dsn <- paste0(
      "WFS:https://",
      URLencode(usuario, reserved = TRUE), ":",
      URLencode(contrasena, reserved = TRUE),
      "@geoserver-ed.imm.gub.uy/geoserver/wfs?",
      "service=WFS&version=1.0.0&request=GetFeature&typename=", nombre_ft,
      "&srsname=EPSG:32721&outputFormat=application/json"
    )

    sf_obj <- tryCatch(
      sf::st_read(dsn = dsn, quiet = TRUE),
      error = function(e) {
        message("⚠️  Error en ", nombre_ft, ": ", e$message)
        NULL
      }
    )

    if (!is.null(sf_obj)) lista_sf[[nombre_ft]] <- sf_obj
  }

  cat("\nListo.", length(lista_sf), "/", length(capas_interes), "capas cargadas.\n")
  invisible(lista_sf)
}

## 3) GUARDAR / CARGAR CAPAS EN DISCO ----

#' Guarda una lista de capas sf en disco en formato RDS y GPKG.
#'
#' Estructura generada:
#'   <base_dir>/RDS/<nombre_capa>.rds   (un archivo por capa)
#'   <base_dir>/GPKG/capas.gpkg         (todas las capas en un único GeoPackage)
#'
#' @param lista_sf   Lista nombrada de objetos sf (salida de cargar_capas_wfs).
#' @param base_dir   Carpeta raíz de almacenamiento (ej: "db/DFR").
guardar_capas_wfs <- function(lista_sf, base_dir = "db/DFR") {
  dir_rds <- file.path(base_dir, "RDS")
  dir_gpkg <- file.path(base_dir, "GPKG")
  dir.create(dir_rds, recursive = TRUE, showWarnings = FALSE)
  dir.create(dir_gpkg, recursive = TRUE, showWarnings = FALSE)

  gpkg_path <- file.path(dir_gpkg, "capas.gpkg")

  # Borramos el GPKG anterior para reconstruirlo limpio
  if (file.exists(gpkg_path)) file.remove(gpkg_path)

  for (nombre in names(lista_sf)) {
    sf_obj <- lista_sf[[nombre]]

    # Nombre seguro para archivo (reemplaza ":" y "/" por "_")
    nombre_archivo <- gsub("[:/]", "_", nombre)

    # --- RDS ---
    ruta_rds <- file.path(dir_rds, paste0(nombre_archivo, ".rds"))
    saveRDS(sf_obj, ruta_rds)

    # --- GPKG ---
    # st_write acepta nombre de capa hasta 63 chars; usamos el mismo nombre seguro
    sf::st_write(sf_obj,
      dsn = gpkg_path, layer = nombre_archivo,
      driver = "GPKG", append = TRUE, quiet = TRUE
    )

    cat("  Guardado:", nombre_archivo, "\n")
  }

  cat("\nGuardado completo.\n")
  cat("  RDS  ->", dir_rds, "\n")
  cat("  GPKG ->", gpkg_path, "\n")
  invisible(lista_sf)
}

# ---------------------------------------------------------------

#' Carga capas sf desde disco (sin necesitar servidor ni credenciales).
#'
#' @param base_dir  Carpeta raíz (ej: "db/DFR").
#' @param formato   "RDS" (un archivo por capa) o "GPKG" (GeoPackage único).
#' @return Lista nombrada de objetos sf.
cargar_capas_local <- function(base_dir = "db/DFR", formato = c("RDS", "GPKG")) {
  formato <- match.arg(formato)

  if (formato == "RDS") {
    dir_rds <- file.path(base_dir, "RDS")
    archivos <- list.files(dir_rds, pattern = "\\.rds$", full.names = TRUE)
    if (length(archivos) == 0) stop("No se encontraron archivos .rds en: ", dir_rds)

    lista_sf <- lapply(archivos, readRDS)
    # Restauramos el nombre original (reemplazamos "_" inicial de "dfr_" → "dfr:")
    nombres <- tools::file_path_sans_ext(basename(archivos))
    # Inversa del gsub: "dfr_X" → "dfr:X"  y  "dfr_X_Y" → "dfr:X/Y" (si hubiera)
    nombres_orig <- sub("^(\\w+)_", "\\1:", nombres)
    names(lista_sf) <- nombres_orig
  } else {
    gpkg_path <- file.path(base_dir, "GPKG", "capas.gpkg")
    if (!file.exists(gpkg_path)) stop("No se encontró el archivo: ", gpkg_path)

    capas <- sf::st_layers(gpkg_path)$name
    lista_sf <- lapply(capas, function(lyr) sf::st_read(gpkg_path, layer = lyr, quiet = TRUE))
    nombres_orig <- sub("^(\\w+)_", "\\1:", capas)
    names(lista_sf) <- nombres_orig
  }

  cat("Capas cargadas desde disco:", length(lista_sf), "(formato:", formato, ")\n")
  invisible(lista_sf)
}

# ---------------------------------------------------------------

#' Descarga las capas del servidor, las guarda en disco y las retorna.
#' Usar cuando hay datos nuevos en el GeoServer (ej: una vez por mes).
#'
#' @param base_dir  Carpeta raíz de almacenamiento.
#' @param ...       Parámetros adicionales pasados a cargar_capas_wfs().
#' @return Lista nombrada de objetos sf (ya guardada).
actualizar_capas_wfs <- function(base_dir = "db/DFR", ...) {
  cat("=== Actualizando capas desde el servidor ===\n")
  lista_sf <- cargar_capas_wfs(...)
  guardar_capas_wfs(lista_sf, base_dir = base_dir)
  cat("=== Actualización completa ===\n")
  invisible(lista_sf)
}

## 4) LLAMADA ----

# --- Actualizar desde el servidor (una vez por mes aprox.) ---
# actualizar_capas_wfs(base_dir = "db/DFR")

# --- Uso diario: cargar desde disco, sin credenciales ---
# lista_sf <- cargar_capas_local(base_dir = "db/DFR", formato = "RDS")
# lista_sf <- cargar_capas_local(base_dir = "db/DFR", formato = "GPKG")

# --- Ejemplos con prefijo o usuario fijos ---
# actualizar_capas_wfs(base_dir = "db/DFR", usuario = "im4445285")
# actualizar_capas_wfs(base_dir = "db/DFR", prefijo = "^urb:")

# posiciones_dfr <- lista_sf[["dfr_E_DF_POSICIONES:RECORRIDO"]]
# recorridos_dfr <- lista_sf[["dfr_E_DF_RUTAS:RECORRIDO"]]

## RUTAS ----

# Rutas_recorrido_vigente <- lista_sf[["dfr:E_DF_RUTAS_RECORRIDO"]]

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
# drawRutasPorCodigoLeaflet <- function(rutas_df,
#                                       valores = NULL,
#                                       campo = "NOM_RUT",
#                                       geom_col = NULL,
#                                       colorear_distinto = FALSE, # NUEVO PARÁMETRO
#                                       color_unico = "blue", # NUEVO PARÁMETRO
#                                       tile_provider = c("OpenStreetMap", "CartoDB", "Stamen")) {
#   tile_provider <- match.arg(tile_provider)
#   stopifnot(inherits(rutas_df, "sf"))
# 
#   if (!is.null(geom_col)) sf::st_geometry(rutas_df) <- geom_col
#   if (is.na(sf::st_crs(rutas_df))) stop("Definí el CRS del sf antes de transformar.")
#   if (!campo %in% names(rutas_df)) stop("Campo inexistente para identificar: ", campo)
# 
#   # --- Lógica de Filtrado (igual que antes) ---
#   if (is.null(valores)) {
#     sel <- rutas_df
#   } else {
#     vals <- unique(as.character(valores))
#     sel <- rutas_df[rutas_df[[campo]] %in% vals, , drop = FALSE]
#   }
# 
#   if (!nrow(sel)) stop("El dataframe está vacío o no hay coincidencias.")
# 
#   # --- Procesamiento Geográfico ---
#   sel <- sf::st_make_valid(sel)
#   rutas_ll <- sf::st_transform(sel, 4326)
# 
#   # Popup robusto (igual que antes)
#   cols <- intersect(c("id", "COD_RECORRIDO", "NOM_RUT", "FECHA_DESDE", "FECHA_HASTA", "MUNICIPIO"), names(rutas_ll))
#   if (length(cols)) {
#     parts <- lapply(cols, function(k) sprintf("<strong>%s:</strong> %s", k, as.character(rutas_ll[[k]])))
#     rutas_ll$popup <- vapply(seq_len(nrow(rutas_ll)), function(i) paste(vapply(parts, `[`, "", i), collapse = "<br/>"), "")
#   } else {
#     rutas_ll$popup <- "Ruta"
#   }
# 
#   # --- Renderizado Leaflet ---
#   m <- leaflet::leaflet(rutas_ll)
#   m <- switch(tile_provider,
#     CartoDB       = leaflet::addProviderTiles(m, "CartoDB.Positron"),
#     Stamen        = leaflet::addProviderTiles(m, "Stamen.TonerLite"),
#     OpenStreetMap = leaflet::addTiles(m)
#   )
# 
#   # --- NUEVA LÓGICA DE COLOR Y LEYENDA ---
# 
#   if (colorear_distinto) {
#     # 1. Crear paleta dinámica basada en los nombres únicos del campo
#     # Usamos 'viridis' porque es buena para distinguir colores, pero puedes cambiarla.
#     pal <- leaflet::colorFactor(palette = "viridis", domain = rutas_ll[[campo]])
# 
#     # 2. Dibujar polilíneas usando la paleta (~pal(...))
#     # NOTA: Usamos get(campo) para extraer dinámicamente el valor de la columna
#     m <- leaflet::addPolylines(m, color = ~ pal(get(campo)), weight = 3, opacity = 0.8, popup = ~popup)
# 
#     # 3. Agregar leyenda completa que mapea colores a nombres
#     m <- leaflet::addLegend(m,
#       position = "bottomright",
#       pal = pal,
#       values = ~ get(campo),
#       title = paste("Rutas (", campo, ")", sep = "")
#     )
#   } else {
#     # Lógica de color ÚNICO (como antes)
#     m <- leaflet::addPolylines(m, color = color_unico, weight = 3, opacity = 0.7, popup = ~popup)
# 
#     # Leyenda simple
#     if (is.null(valores)) {
#       label_leyenda <- "Todas las rutas"
#     } else {
#       label_leyenda <- paste0(campo, ": ", paste(valores, collapse = ", "))
#     }
# 
#     m <- leaflet::addLegend(m,
#       position = "bottomright",
#       colors = color_unico,
#       labels = label_leyenda,
#       title = "Líneas"
#     )
#   }
# 
#   return(m)
# }

# Dibujar todo, mismo color.
# rutas_completas <- drawRutasPorCodigoLeaflet(Rutas_recorrido_vigente)

# Dibujar todo, distinto color.
# rutas_completas_pintado <- drawRutasPorCodigoLeaflet(Rutas_recorrido_vigente,
#   colorear_distinto = TRUE
# )

# Por defecto filtra por "COD_RECORRIDO"
# mapa1 <- drawRutasPorCodigoLeaflet(E_DF_RUTAS_RECORRIDO, valores = "B_DU_RM_CL_101")

# Varios códigos
# mapa2 <- drawRutasPorCodigoLeaflet(E_DF_RUTAS_RECORRIDO,
#   valores = c("B_DU_RM_CL_101", "B_DU_RM_CL_102"),
#   colorear_distinto = TRUE
# )



# drawMapa_IM_Pro <- function(zona_df,
#                             col_id = "id",
#                             col_label = "nombre",
#                             filtro_ids = NULL,
#                             color_relleno = "darkgreen",
#                             opacidad = 0.3) {
#   # 1. FILTRADO Y PREPARACIÓN
#   data_mapa <- zona_df
# 
#   if (!is.null(filtro_ids)) {
#     # Filtramos usando el nombre de columna dinámico
#     data_mapa <- data_mapa %>% filter(.data[[col_id]] %in% filtro_ids)
#   }
# 
#   # Verificación: ¿quedó algo después del filtro?
#   if (nrow(data_mapa) == 0) {
#     stop("El filtro no devolvió resultados. Verificá si los IDs existen en la columna seleccionada.")
#   }
# 
#   # 2. CREAR COLUMNAS ESTÁTICAS (Esto evita el error de 'type list')
#   # Extraemos los valores como vectores simples para que leaflet no se confunda
#   data_mapa$.id_display <- as.character(data_mapa[[col_id]])
#   data_mapa$.label_display <- as.character(data_mapa[[col_label]])
# 
#   # Reproyectar a WGS84
#   data_mapa <- st_transform(data_mapa, 4326)
# 
#   # 3. LÓGICA DE COLORES
#   if (color_relleno %in% names(data_mapa)) {
#     pal <- colorFactor(palette = "Set1", domain = data_mapa[[color_relleno]])
#     fill_color_final <- pal(data_mapa[[color_relleno]])
#   } else {
#     fill_color_final <- color_relleno
#   }
# 
#   # 4. CONSTRUCCIÓN DEL MAPA
#   leaflet(data_mapa) %>%
#     addWMSTiles(
#       baseUrl = "https://montevideo.gub.uy/app/geowebcache/service/wms",
#       layers = "mapstore-base:capas_base",
#       options = WMSTileOptions(format = "image/png", transparent = TRUE),
#       group = "Mapa Base IM"
#     ) %>%
#     addPolygons(
#       color = "black", weight = 1,
#       fillColor = fill_color_final,
#       fillOpacity = opacidad,
#       # Usamos las columnas estáticas que creamos arriba con ~
#       label = ~.label_display,
#       popup = ~ paste0(
#         "<strong>ID:</strong> ", .id_display, "<br>",
#         "<strong>Etiqueta:</strong> ", .label_display
#       ),
#       group = "Capa Activa"
#     ) %>%
#     addSearchOSM(
#       options = searchOptions(textPlaceholder = "Buscar dirección...", collapsed = FALSE)
#     ) %>%
#     addSearchFeatures(
#       targetGroups = "Capa Activa",
#       options = searchFeaturesOptions(zoom = 16, openPopup = TRUE, textPlaceholder = "Buscar por ID...")
#     ) %>%
#     addLayersControl(
#       overlayGroups = c("Capa Activa"),
#       options = layersControlOptions(collapsed = FALSE)
#     )
# }
# 
# # Todos
# drawMapa_IM_Pro(Vigente_Circuitos_CAP,
#   col_id = "GID",
#   col_label = "CIRCUITO",
#   color_relleno = "orange"
# )
# 
# # Para dibujar circuitos específicos con color fijo
# mapa_especifico <- drawMapa_IM_Pro(
#   Vigente_Circuitos_CAP,
#   col_id = "CIRCUITO",
#   col_label = "CIRCUITO",
#   filtro_ids = c(1, 9, 6), # Asegurate que estos GID existan
#   color_relleno = "red"
# )
# 
# # Para dibujar circuitos específicos con color diferentes
# mapa_especifico <- drawMapa_IM_Pro(
#   Vigente_Circuitos_CAP,
#   col_id = "CIRCUITO",
#   col_label = "CIRCUITO",
#   color_relleno = "CIRCUITO"
# )
# 
# mapa_especifico
#
# Guía rápida de personalización (Comentarios para vos):
#   Para dibujar TODO el data frame: Simplemente no pongas el argumento filtro_ids (quedará como NULL por defecto).
#
# Para colores diferentes por polígono: Si querés que cada circuito tenga un color distinto, usá color_relleno = "CIRCUITO". La función detectará que es una columna y creará una paleta de colores.
#
# Para cambiar la transparencia: Si los polígonos tapan mucho el mapa base de la IM, bajá la opacidad a 0.1 o 0.2.

# =============================================================================
## FUNCIONES DE MAPAS (UNIVERSALES) ----
# =============================================================================

# Mapa base IM -----------------------------------------------------------------

#' Crea un mapa Leaflet centrado en Montevideo con el mapa base de la IMM.
#'
#' Usa OpenStreetMap como fondo base (siempre visible) y el WMS de la IMM
#' como capa superior conmutable. El WMS solo cubre Montevideo, por eso
#' se centra ahí automáticamente.
#'
#' @param lat    Latitud inicial (por defecto centro de Montevideo).
#' @param lng    Longitud inicial (por defecto centro de Montevideo).
#' @param zoom   Nivel de zoom inicial.
#' @param wms    Si TRUE, agrega el WMS de la IMM sobre OSM.
#' @param buscar Si TRUE, agrega barra de búsqueda de direcciones.
#' @return Un objeto leaflet listo para recibir capas con im_add_capa().
im_base_map <- function(lat = -34.895, lng = -56.165, zoom = 13,
                        wms = TRUE, buscar = TRUE) {

  m <- leaflet::leaflet() |>
    leaflet::setView(lng = lng, lat = lat, zoom = zoom) |>
    # OSM como fondo base siempre visible
    leaflet::addProviderTiles(
      "OpenStreetMap",
      group   = "OSM (base)",
      options = leaflet::providerTileOptions(opacity = 1)
    )

  # WMS de la IMM encima (opcional, se puede apagar)
  if (wms) {
    m <- leaflet::addWMSTiles(
      m,
      baseUrl     = "https://montevideo.gub.uy/app/geowebcache/service/wms",
      layers      = "mapstore-base:capas_base",
      options     = leaflet::WMSTileOptions(
        format      = "image/png",
        transparent = TRUE,
        opacity     = 1
      ),
      attribution = "© Intendencia de Montevideo",
      group       = "Mapa IMM"
    )
  }

  if (buscar) {
    m <- leaflet.extras::addSearchOSM(
      m,
      options = leaflet.extras::searchOptions(
        textPlaceholder = "Buscar dirección...",
        collapsed       = FALSE
      )
    )
  }

  # Control para alternar entre mapa base OSM y WMS de la IMM
  if (wms) {
    m <- leaflet::addLayersControl(
      m,
      baseGroups    = c("Mapa IMM", "OSM (base)"),
      options       = leaflet::layersControlOptions(collapsed = TRUE)
    )
  }

  m
}


# Agregar capa -----------------------------------------------------------------

#' Agrega una capa sf a un mapa Leaflet. Detecta automáticamente el tipo de
#' geometría (puntos, líneas, polígonos) y aplica el método correcto.
#'
#' @param mapa          Objeto leaflet (ej: salida de im_base_map()).
#' @param sf_obj        Objeto sf con la capa a dibujar.
#' @param col_color     Nombre de columna para colorear por categoría. Si NULL usa 'color'.
#' @param color         Color fijo cuando col_color es NULL (ej: "red", "#336699").
#' @param paleta        Paleta para col_color: "Set1","viridis","Spectral", etc.
#' @param opacidad      Opacidad del relleno/línea (0 a 1).
#' @param col_popup     Vector de columnas a mostrar en el popup. NULL = todas.
#' @param col_label     Columna para la etiqueta de hover. NULL = ninguna.
#' @param nombre_grupo  Nombre del grupo (para el control de capas).
#' @param peso          Grosor de líneas / borde de polígonos (px).
#' @param radio         Radio de los puntos (px).
#' @param leyenda       Si TRUE, agrega leyenda cuando se usa col_color.
#' @return El objeto leaflet con la capa agregada.
im_add_capa <- function(
  mapa,
  sf_obj,
  col_color    = NULL,
  color        = "steelblue",
  paleta       = "Set1",
  opacidad     = 0.7,
  col_popup    = NULL,
  col_label    = NULL,
  nombre_grupo = "Capa",
  peso         = 2,
  radio        = 6,
  leyenda      = TRUE
) {
  stopifnot(inherits(sf_obj, "sf"))

  # Reproyectar a WGS84
  sf_obj <- sf::st_make_valid(sf_obj)
  sf_obj <- sf::st_transform(sf_obj, 4326)

  # --- Paleta de colores ---
  if (!is.null(col_color) && col_color %in% names(sf_obj)) {
    pal      <- leaflet::colorFactor(palette = paleta, domain = sf_obj[[col_color]])
    col_calc <- pal(sf_obj[[col_color]])
    usar_pal <- TRUE
  } else {
    col_calc <- color
    usar_pal <- FALSE
  }

  # --- Popup dinámico ---
  cols_popup <- if (is.null(col_popup)) {
    setdiff(names(sf_obj), attr(sf_obj, "sf_column"))
  } else {
    intersect(col_popup, names(sf_obj))
  }
  sf_obj$.popup_html <- apply(
    sf::st_drop_geometry(sf_obj[, cols_popup, drop = FALSE]), 1,
    function(fila) {
      paste0(
        "<strong>", names(fila), ":</strong> ", as.character(fila),
        collapse = "<br/>"
      )
    }
  )

  # --- Etiqueta hover ---
  if (!is.null(col_label) && col_label %in% names(sf_obj)) {
    sf_obj$.label_txt <- as.character(sf_obj[[col_label]])
  } else {
    sf_obj$.label_txt <- nombre_grupo
  }

  # --- Detectar tipo de geometría ---
  tipo_geom <- unique(as.character(sf::st_geometry_type(sf_obj)))
  es_punto  <- any(grepl("POINT",   tipo_geom, ignore.case = TRUE))
  es_linea  <- any(grepl("LINE",    tipo_geom, ignore.case = TRUE))
  es_polig  <- any(grepl("POLYGON", tipo_geom, ignore.case = TRUE))

  # --- Dibujar según tipo ---
  if (es_polig) {
    mapa <- leaflet::addPolygons(
      mapa,
      data        = sf_obj,
      color       = "black",
      weight      = peso,
      fillColor   = col_calc,
      fillOpacity = opacidad,
      label       = ~.label_txt,
      popup       = ~.popup_html,
      group       = nombre_grupo
    )

  } else if (es_linea) {
    mapa <- leaflet::addPolylines(
      mapa,
      data    = sf_obj,
      color   = col_calc,
      weight  = peso,
      opacity = opacidad,
      label   = ~.label_txt,
      popup   = ~.popup_html,
      group   = nombre_grupo
    )

  } else if (es_punto) {
    mapa <- leaflet::addCircleMarkers(
      mapa,
      data        = sf_obj,
      color       = "black",
      weight      = 1,
      fillColor   = col_calc,
      fillOpacity = opacidad,
      radius      = radio,
      label       = ~.label_txt,
      popup       = ~.popup_html,
      group       = nombre_grupo
    )

  } else {
    warning("Tipo de geometría no soportado: ", paste(tipo_geom, collapse = ", "))
  }

  # --- Leyenda ---
  if (leyenda && usar_pal) {
    mapa <- leaflet::addLegend(
      mapa,
      position = "bottomright",
      pal      = pal,
      values   = sf_obj[[col_color]],
      title    = col_color
    )
  }

  mapa
}

# Control de capas -------------------------------------------------------------

#' Agrega el control de capas (toggle on/off) a un mapa con grupos definidos.
#'
#' @param mapa    Objeto leaflet.
#' @param grupos  Vector de nombres de grupos a controlar.
#' @return El objeto leaflet con el control de capas.
im_capas_control <- function(mapa, grupos) {
  leaflet::addLayersControl(
    mapa,
    overlayGroups = grupos,
    options       = leaflet::layersControlOptions(collapsed = FALSE)
  )
}

# =============================================================================
## EJEMPLOS im_base_map / im_add_capa ----
# =============================================================================

# Un solo tipo de geometría (polígonos coloreados por columna):
# im_base_map() |>
#   im_add_capa(Vigente_Circuitos_CAP, col_color = "CIRCUITO",
#               col_label = "CIRCUITO", nombre_grupo = "Circuitos")

# Múltiples capas combinadas con control on/off:
# im_base_map() |>
#   im_add_capa(Vigente_Circuitos_CAP, col_color = "CIRCUITO",
#               nombre_grupo = "Circuitos", opacidad = 0.2) |>
#   im_add_capa(Rutas_recorrido_vigente, color = "red",
#               nombre_grupo = "Rutas", peso = 2) |>
#   im_capas_control(c("Circuitos", "Rutas"))

# Puntos con color fijo:
# im_base_map() |>
#   im_add_capa(puntos_sf, color = "orange", radio = 8,
#               col_label = "nombre", nombre_grupo = "Puntos")

# Exportar a HTML --------------------------------------------------------------

#' Exporta un mapa Leaflet a un archivo HTML autocontenido.
#'
#' El HTML resultante funciona sin internet (todos los assets quedan embebidos),
#' salvo las tiles del mapa base que siempre requieren conexión.
#'
#' @param mapa      Objeto leaflet a exportar.
#' @param ruta      Ruta del archivo de salida (ej: "mapas/circuitos.html").
#'                  Si la carpeta no existe, se crea automáticamente.
#' @param titulo    Título que aparece en la pestaña del navegador.
#' @param abrir     Si TRUE, abre el HTML en el navegador al terminar.
#' @return La ruta del archivo generado (invisible).
im_exportar_html <- function(mapa, ruta = "mapa.html", titulo = "Mapa IMM", abrir = FALSE) {
  dir.create(dirname(ruta), recursive = TRUE, showWarnings = FALSE)

  # Ruta absoluta (necesaria para saveWidget)
  ruta_abs <- normalizePath(ruta, mustWork = FALSE)

  htmlwidgets::saveWidget(
    widget   = mapa,
    file     = ruta_abs,
    selfcontained = TRUE,   # todo embebido en un solo .html
    title    = titulo
  )

  cat("Mapa exportado:", ruta_abs, "\n")
  if (abrir) utils::browseURL(ruta_abs)
  invisible(ruta_abs)
}

# Ejemplos:
# mapa <- im_base_map() |>
#   im_add_capa(Vigente_Circuitos_CAP, col_color = "CIRCUITO",
#               col_label = "CIRCUITO", nombre_grupo = "Circuitos")
#
# im_exportar_html(mapa, ruta = "mapas/circuitos.html", titulo = "Circuitos CAP", abrir = TRUE)
