# ==============================================================================
# conexion_GOL_circuitos.R
# Descarga directa (sin QGIS) de datos de Gestión Operativa de Limpieza (GOL)
# usando las mismas fuentes públicas que respaldan al plugin im_gol.
#
# Fuentes verificadas (2026-08-18):
#   1. WFS público "gol_publico" -> circuitos y segmentos INTRADOMICILIARIOS
#      (reciclable / mezclado). Es la fuente real de
#      gol:intradomiciliario_circuito(_segmento) que usa el plugin.
#   2. API REST "limpieza-gestion-operativa" -> contenedores y sus circuitos.
#
# NOTA IMPORTANTE sobre "circuito_manual" (recolección manual por calles,
# la que usa cb_v_sig_vias):
#   No encontré ese dato en el WFS público (gol_publico solo publica
#   intradomiciliario_circuito e intradomiciliario_circuito_segmento), ni en
#   el WFS interno (geoserver.montevideo.gub.uy, workspace "gol", mismo
#   resultado), ni en la API frontend/v1 de limpieza-gestion-operativa (sus
#   endpoints son de contenedores/intradomiciliario, no de vías), ni en la
#   base Postgres de test (confirmado que ya no se actualiza).
#   Todo indica que "circuito_manual" se gestiona *solo* desde QGIS contra
#   la base de producción real, sin exponerse por ninguna API pública. Para
#   conseguirlo hay dos caminos:
#     a) Pedir a quien mantiene el plugin (alvaro.rettich@imm.gub.uy, ver
#        metadata.txt) la cadena de conexión de producción.
#     b) Con el proyecto QGIS real abierto: clic derecho en la capa
#        circuito_manual_segmentos -> Exportar -> Guardar objetos como...
#        -> GeoJSON/CSV, y leer ese archivo con sf::st_read() o read.csv().
# ==============================================================================

library(httr2)
library(sf)
library(dplyr)

# --- 1. Circuitos intradomiciliarios (reciclable / mezclado) -------------
# Fuente: WFS público de GeoServer, workspace "gol_publico"

url_wfs_gol_publico <- "https://montevideo.gub.uy/app/geoserver/gol_publico/ows"

#' Descarga una capa del WFS público gol_publico como objeto sf
#'
#' @param nombre_capa Nombre técnico sin workspace (ej. "intradomiciliario_circuito")
#' @param cql_filter Filtro CQL opcional (ej. "tipo_residuo='reciclable'")
descargar_capa_gol_publico <- function(nombre_capa, cql_filter = NULL) {
  typename <- paste0("gol_publico:", nombre_capa)
  message("⏳ Solicitando: ", typename, if (!is.null(cql_filter)) paste0(" [", cql_filter, "]") else "", " ...")

  query_params <- list(
    service = "WFS",
    version = "1.0.0",
    request = "GetFeature",
    typeName = typename,
    outputFormat = "application/json"
  )
  if (!is.null(cql_filter)) query_params$CQL_FILTER <- cql_filter

  resp <- tryCatch(
    request(url_wfs_gol_publico) |> req_url_query(!!!query_params) |> req_perform(),
    error = function(e) { message("❌ Error de conexión: ", conditionMessage(e)); NULL }
  )
  if (is.null(resp)) return(NULL)

  capa <- tryCatch(st_read(resp_body_string(resp), quiet = TRUE), error = function(e) {
    message("❌ No se pudo leer como GeoJSON: ", conditionMessage(e)); NULL
  })
  if (!is.null(capa)) message("✅ ", typename, ": ", nrow(capa), " features")
  capa
}

# Circuitos y segmentos intradomiciliarios, separados por tipo de residuo
circuitos_reciclable <- descargar_capa_gol_publico("intradomiciliario_circuito", "tipo_residuo='reciclable'")
circuitos_mezclado   <- descargar_capa_gol_publico("intradomiciliario_circuito", "tipo_residuo='mezclado'")
segmentos_intra      <- descargar_capa_gol_publico("intradomiciliario_circuito_segmento")

# Segmentos + su circuito, ordenados por posición de recorrido
if (!is.null(segmentos_intra)) {
  segmentos_intra_ordenados <- segmentos_intra |>
    arrange(intradomiciliario_circuito_id, posicion_en_circuito)

  resumen_por_circuito <- segmentos_intra_ordenados |>
    st_drop_geometry() |>
    count(intradomiciliario_circuito_id, tipo_residuo, name = "cantidad_segmentos")

  print(resumen_por_circuito)
}

# --- 2. Contenedores y sus circuitos --------------------------------------
# Fuente: API REST frontend de limpieza-gestion-operativa (devuelve GeoJSON)

# url_api_gol y descargar_api_gol() están definidas en este archivo compartido
# (también lo usa nuevoinforme.R para el historial de circuitos)
source("db/GOL_reportes/funciones_db_circuitosGOL.R")

contenedores          <- descargar_api_gol("contenedores")
contenedores_circuitos <- descargar_api_gol("contenedores/circuitos")

# --- 3. Capas con autenticación (geoserver-ed.imm.gub.uy) -----------------
# GeoServer interno "de edición", requiere usuario/contraseña de dominio IMM.
# La contraseña se pide de forma interactiva (nunca queda en el archivo).

url_wfs_gol_ed <- "https://geoserver-ed.imm.gub.uy/geoserver/wfs"
usuario_ed     <- "im4445285"
contrasena_ed  <- NULL  # se completa la primera vez que se llama a descargar_capa_gol_ed()

#' Descarga una capa del WFS interno geoserver-ed (requiere autenticación)
#'
#' @param nombre_capa Nombre técnico con workspace (ej. "gol:hogares_sustentables")
#' @param cql_filter Filtro CQL opcional
descargar_capa_gol_ed <- function(nombre_capa, cql_filter = NULL) {
  if (is.null(contrasena_ed)) {
    contrasena_ed <<- rstudioapi::askForPassword(paste("Contraseña IMM para", usuario_ed))
  }

  message("⏳ Solicitando: ", nombre_capa, if (!is.null(cql_filter)) paste0(" [", cql_filter, "]") else "", " ...")

  query_params <- list(
    service = "WFS",
    version = "1.0.0",
    request = "GetFeature",
    typeName = nombre_capa,
    srsname = "EPSG:32721",
    outputFormat = "application/json"
  )
  if (!is.null(cql_filter)) query_params$CQL_FILTER <- cql_filter

  resp <- tryCatch(
    request(url_wfs_gol_ed) |>
      req_url_query(!!!query_params) |>
      req_auth_basic(usuario_ed, contrasena_ed) |>
      req_perform(),
    error = function(e) { message("❌ Error de conexión o autenticación: ", conditionMessage(e)); NULL }
  )
  if (is.null(resp)) return(NULL)

  capa <- tryCatch(st_read(resp_body_string(resp), quiet = TRUE), error = function(e) {
    message("❌ No se pudo leer como GeoJSON: ", conditionMessage(e)); NULL
  })
  if (!is.null(capa)) message("✅ ", nombre_capa, ": ", nrow(capa), " features")
  capa
}

hogares_sustentables <- descargar_capa_gol_ed("gol:hogares_sustentables")

# --- Ejemplo de visualización rápida --------------------------------------
# plot(st_geometry(segmentos_intra), col = as.factor(segmentos_intra$tipo_residuo))
