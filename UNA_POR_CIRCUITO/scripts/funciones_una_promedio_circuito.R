# =============================================================================
# funciones_una_promedio_circuito.R
# -----------------------------------------------------------------------------
# UNA promedio por circuito y por dia, a partir del historico depurado
# (historico_ubicaciones_depurado.rds, que ya trae UNA_pordia).
#
# Antes de promediar se excluyen:
#   1) Contenedores con Dia_acumulacion > dia_acumulacion_max (default 12):
#      outliers -- contenedores rotos, perdidos o abandonados que
#      distorsionarian el promedio. Tambien quedan afuera los que nunca
#      tuvieron levante (Dia_acumulacion NA).
#   2) Contenedores con Estado distinto de NA (p.ej. "Mantenimiento" o
#      "Sin instalar"): no estan operando con normalidad. Estado = NA es
#      el estado normal/operativo (la gran mayoria de las filas).
#
# A cada fila (Circuito, Fecha) resultante se le agrega Municipio,
# Circuito_corto y Oficina (IM / Fideicomiso) -- son atributos fijos de
# cada circuito (relacion 1 a 1 verificada contra el historico).
#
# Salida: UNA_POR_CIRCUITO/salidas/una_promedio_por_circuito.xlsx
# =============================================================================

library(data.table)
library(writexl)
source("UNA_POR_CIRCUITO/scripts/funciones_comunes.R")


#' Calcula la UNA promedio por (Circuito, Fecha).
#'
#' @param historico data.frame/tibble/data.table con columnas `Fecha`,
#'   `Circuito`, `Circuito_corto`, `Municipio`, `Oficina`, `Estado`,
#'   `Dia_acumulacion` y `UNA_pordia` (ver funciones_una.R).
#' @param dia_acumulacion_max dias de acumulacion maximos a incluir en el
#'   promedio (exclusive del limite, es decir se conserva <= este valor).
#'   Default 12.
#'
#' @return data.frame con una fila por (Fecha, Circuito): `Municipio`,
#'   `Circuito_corto`, `Oficina`, `UNA_promedio` (%, redondeado a 1 decimal)
#'   y `n_contenedores` (cuantos contenedores entraron en ese promedio).
#'   Ordenado igual que ordenar_historico(): Fecha descendente y Circuito
#'   alfabetico (A, B, C, CH, D, E, F, G, ...).
calcular_una_promedio_circuito <- function(historico, dia_acumulacion_max = 12) {

  columnas <- c("Fecha", "Circuito", "Circuito_corto", "Municipio", "Oficina",
               "Estado", "Dia_acumulacion", "UNA_pordia")
  stopifnot(all(columnas %in% names(historico)))

  dt <- data.table::as.data.table(historico)

  # --- filtros: fuera Estado != NA y Dia_acumulacion > limite (o NA) ---
  dt <- dt[is.na(Estado) &
             !is.na(Dia_acumulacion) & Dia_acumulacion <= dia_acumulacion_max]

  res <- dt[, .(
    UNA_promedio   = round(mean(UNA_pordia, na.rm = TRUE), 1),
    n_contenedores = .N
  ), by = .(Fecha, Circuito, Circuito_corto, Municipio, Oficina)]

  # --- orden: Fecha desc, Circuito alfabetico (A,B,C,CH,D,E,F,G) ---
  prefijo <- sub("^([A-Za-z]+)_.*", "\\1", res$Circuito)
  numero  <- suppressWarnings(as.numeric(sub(".*_", "", res$Circuito)))
  letra   <- match(prefijo, ALFABETO_CIRCUITO)
  sin_match <- is.na(letra)
  if (any(sin_match)) {
    extra <- sort(unique(prefijo[sin_match]))
    letra[sin_match] <- length(ALFABETO_CIRCUITO) + match(prefijo[sin_match], extra)
  }
  res[, `:=`(.letra = letra, .numero = numero)]
  data.table::setorder(res, -Fecha, .letra, .numero)
  res[, c(".letra", ".numero") := NULL]

  data.table::setDF(res)
  res
}


#' Wrapper de archivo: lee el historico depurado, calcula la UNA promedio
#' por circuito y dia, y exporta el resultado a Excel.
#'
#' @param ruta_historico .rds del historico depurado (con UNA_pordia).
#' @param ruta_salida    .xlsx a generar.
#' @param dia_acumulacion_max ver calcular_una_promedio_circuito().
#' @return (invisible) el data.frame resultante.
actualizar_una_promedio_circuito <- function(
  ruta_historico = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_depurado.rds",
  ruta_salida    = "UNA_POR_CIRCUITO/salidas/una_promedio_por_circuito.xlsx",
  dia_acumulacion_max = 12
) {
  message("Leyendo ", ruta_historico, " ...")
  historico <- readRDS(ruta_historico)

  res <- calcular_una_promedio_circuito(historico, dia_acumulacion_max)

  message(sprintf(
    paste0("Filas (Circuito x Fecha): %s\n",
           "  Excluidos del promedio: Estado != NA (Mantenimiento/Sin instalar)\n",
           "                          o Dia_acumulacion > %s (o sin dato).\n",
           "  UNA_promedio (%%): min=%.1f  mediana=%.1f  media=%.1f  max=%.1f"),
    nrow(res), dia_acumulacion_max,
    min(res$UNA_promedio), median(res$UNA_promedio),
    mean(res$UNA_promedio), max(res$UNA_promedio)
  ))

  dir.create(dirname(ruta_salida), showWarnings = FALSE, recursive = TRUE)
  writexl::write_xlsx(list("UNA promedio por circuito" = res), path = ruta_salida)
  message("Excel exportado a: ", ruta_salida)

  invisible(res)
}

# --- Uso: ---
# source("UNA_POR_CIRCUITO/scripts/funciones_una_promedio_circuito.R")
# actualizar_una_promedio_circuito()
