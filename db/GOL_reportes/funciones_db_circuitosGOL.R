# ==============================================================================
# funciones_db_circuitosGOL.R
# Circuitos de contenedores desde la API frontend de limpieza-gestion-operativa
# y su historial de cambios de "periodo" en db/GOL_reportes/.
#
# Solo define funciones: no descarga ni guarda nada al hacer source().
# ==============================================================================

library(httr2)
library(sf)
library(dplyr)

# Fuente: API REST frontend de limpieza-gestion-operativa (devuelve GeoJSON)
url_api_gol <- "https://intranet.imm.gub.uy/app/limpieza-gestion-operativa/api/frontend/v1"

#' Descarga un endpoint GeoJSON de la API frontend de limpieza-gestion-operativa
descargar_api_gol <- function(path) {
  url <- paste0(url_api_gol, "/", path)
  message("⏳ Solicitando: ", path, " ...")

  resp <- tryCatch(
    request(url) |> req_headers(`Accept` = "application/json, text/plain, */*") |> req_perform(),
    error = function(e) { message("❌ Error de conexión: ", conditionMessage(e)); NULL }
  )
  if (is.null(resp)) return(NULL)

  capa <- tryCatch(st_read(resp_body_string(resp), quiet = TRUE), error = function(e) {
    message("❌ No se pudo leer como GeoJSON: ", conditionMessage(e)); NULL
  })
  if (!is.null(capa)) message("✅ ", path, ": ", nrow(capa), " features")
  capa
}

#' Actualiza el historial de circuitos de contenedores GOL
#'
#' Guarda una fila por circuito y versión. La primera corrida guarda todos los
#' circuitos; las siguientes solo agregan una versión nueva cuando:
#'   - el circuito no estaba en el historial, o
#'   - su "fact" es posterior al último guardado Y cambió el "periodo".
#' Si cambia "fact" pero el periodo es el mismo, no se guarda nada.
#'
#' @param ruta Archivo .rds del historial.
#' @return (invisible) las filas agregadas, o NULL si falló la descarga.
actualizar_historico_circuitos_gol <- function(ruta = "db/GOL_reportes/historico_circuitos_gol.rds") {
  capa <- descargar_api_gol("contenedores/circuitos")
  if (is.null(capa)) {
    warning("No se pudo descargar contenedores/circuitos; el historial no se actualizó.")
    return(invisible(NULL))
  }

  # El GeoJSON trae el CRS dentro de cada geometría (formato no estándar) y
  # sf puede leerlo como WGS84; las coordenadas en realidad son UTM 21S.
  if (is.na(st_crs(capa)) || st_crs(capa)$epsg != 32721) {
    capa <- st_set_crs(capa, NA) |> st_set_crs(32721)
  }

  actual <- capa |>
    mutate(
      id             = as.integer(id),
      periodo        = as.numeric(periodo),
      fecha_desde    = as.Date(fecha_desde),
      fecha_hasta    = as.Date(fecha_hasta),
      fact           = as.Date(fact),
      fecha_registro = Sys.Date()
    ) |>
    select(id, nombre, periodo, fecha_desde, fecha_hasta, fact, fecha_registro)

  if (!file.exists(ruta)) {
    saveRDS(actual, ruta)
    message("✅ Historial de circuitos GOL creado: ", nrow(actual), " circuitos (", ruta, ")")
    return(invisible(actual))
  }

  hist <- readRDS(ruta)

  # Última versión guardada de cada circuito
  ultima <- hist |>
    st_drop_geometry() |>
    group_by(id) |>
    slice_max(fact, with_ties = FALSE) |>
    ungroup() |>
    select(id, periodo_guardado = periodo, fact_guardado = fact)

  comparacion <- actual |>
    left_join(ultima, by = "id") |>
    mutate(
      es_nuevo = is.na(fact_guardado),
      periodo_cambio = !es_nuevo &
        fact > fact_guardado &
        round(periodo, 2) != round(periodo_guardado, 2)
    )

  nuevas <- comparacion |> filter(es_nuevo | periodo_cambio)

  if (nrow(nuevas) == 0) {
    message("✅ Sin cambios de periodo en circuitos GOL")
    return(invisible(actual[0, ]))
  }

  num_txt <- function(x) sub(".", ",", as.character(x), fixed = TRUE)
  resumen <- nuevas |>
    st_drop_geometry() |>
    mutate(texto = ifelse(
      es_nuevo,
      paste0(nombre, ": circuito nuevo, periodo ", num_txt(periodo), " (fact ", fact, ")"),
      paste0(nombre, ": periodo ", num_txt(periodo_guardado), " → ", num_txt(periodo), " (fact ", fact, ")")
    ))
  message("🔄 Circuitos GOL con cambios (", nrow(nuevas), "):\n  ", paste(resumen$texto, collapse = "\n  "))

  nuevas <- nuevas |> select(names(actual))
  saveRDS(rbind(hist, nuevas), ruta)
  message("✅ Historial de circuitos GOL actualizado (", ruta, ")")

  invisible(nuevas)
}
