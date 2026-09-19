# =============================================================================
# funciones_comunes.R
# -----------------------------------------------------------------------------
# Utilidades compartidas por los 4 pasos del pipeline:
#   - ordenar_historico(): orden canonico con el que se guarda cada .rds.
#   - fecha_maxima_en():   "marca de agua" para el modo incremental (que
#     Fecha es la mas reciente ya presente en un .rds de salida).
# =============================================================================

library(data.table)

#' Orden alfabetico de los prefijos de circuito. CH es letra propia, entre
#' C y D (A, B, C, CH, D, E, F, G, ...). No usar el orden alfabetico del
#' sistema (sort()/order() de base R): depende del locale y no es fiable
#' entre maquinas para decidir si "C_..." va antes o despues de "CH_...".
ALFABETO_CIRCUITO <- c("A", "B", "C", "CH", "D", "E", "F", "G")

#' Ordena el historico segun el criterio de guardado del pipeline:
#'   1) Fecha, de mas reciente a mas antigua.
#'   2) Circuito, alfabetico "de imprenta" (ver ALFABETO_CIRCUITO) y dentro
#'      de cada letra por el numero de circuito.
#'   3) Posicion, ascendente.
#'
#' @param historico data.frame/tibble/data.table con columnas `Fecha`,
#'   `Circuito` y `Posicion`.
#' @return El mismo `historico`, como data.frame, reordenado.
ordenar_historico <- function(historico) {

  stopifnot(all(c("Fecha", "Circuito", "Posicion") %in% names(historico)))

  dt <- data.table::as.data.table(historico)

  prefijo <- sub("^([A-Za-z]+)_.*", "\\1", dt$Circuito)
  numero  <- suppressWarnings(as.numeric(sub(".*_", "", dt$Circuito)))

  letra <- match(prefijo, ALFABETO_CIRCUITO)
  sin_match <- is.na(letra)
  if (any(sin_match)) {
    # Prefijos no contemplados en ALFABETO_CIRCUITO: se ordenan al final,
    # alfabeticamente entre si (no deberian existir; es solo un resguardo).
    extra <- sort(unique(prefijo[sin_match]))
    letra[sin_match] <- length(ALFABETO_CIRCUITO) + match(prefijo[sin_match], extra)
  }

  dt[, `:=`(.letra = letra, .numero = numero)]
  data.table::setorder(dt, -Fecha, .letra, .numero, Posicion)
  dt[, c(".letra", ".numero") := NULL]

  data.table::setDF(dt)
  dt
}


#' Fecha maxima presente en un .rds ya guardado (para saber, en modo
#' incremental, a partir de donde falta procesar). NA si el archivo no
#' existe o esta vacio.
#'
#' @param ruta .rds con una columna `Fecha`.
#' @return un Date, o NA_Date_ si no hay nada guardado todavia.
fecha_maxima_en <- function(ruta) {
  if (!file.exists(ruta)) return(as.Date(NA))
  x <- readRDS(ruta)
  if (nrow(x) == 0) return(as.Date(NA))
  max(as.Date(x$Fecha))
}
