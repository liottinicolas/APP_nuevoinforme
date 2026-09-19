# =============================================================================
# funciones_filtrar_cerrados.R
# -----------------------------------------------------------------------------
# Depura el historico de ubicaciones:
#   1) Elimina las filas de contenedores dados de baja. Criterio: si el `gid`
#      del historico existe en la capa de posiciones de recorrido HISTORICO
#      (dfr_C_DF_POSICIONES_RECORRIDO:HISTORICO), se toma su `FECHA_HASTA`
#      (fecha de cierre de esa posicion) y se descartan las filas cuya `Fecha`
#      sea MAYOR O IGUAL (>=) a esa FECHA_HASTA.
#   2) Recorta al periodo con datos de llenado confiables: conserva solo las
#      filas con `Fecha >= fecha_min` (ese dia incluido; default 2025-04-01).
#
# Modo incremental (actualizar_todo = FALSE): si ya existe `ruta_salida`,
# solo se filtran las filas de `historico` con Fecha posterior a la maxima
# ya guardada (el filtro es por fila, no depende de las demas filas), y se
# anexan las que sobreviven.
# =============================================================================

library(data.table)
source("UNA_POR_CIRCUITO/scripts/funciones_comunes.R")


#' Depura el historico: quita contenedores cerrados y recorta por fecha.
#'
#' @param historico data.frame/tibble con columnas `gid` y `Fecha` (Date).
#' @param pos_hist  capa `dfr_C_DF_POSICIONES_RECORRIDO:HISTORICO` (sf o
#'   data.frame) con columnas `GID` y `FECHA_HASTA` (Date).
#' @param fecha_min fecha minima a conservar (inclusive). Si es NULL no se
#'   recorta por fecha. Default: 2025-04-01 (inicio de datos de llenado).
#' @param reporte   si TRUE imprime un resumen de lo eliminado.
#'
#' @return El `historico` (como data.frame) sin las filas con
#'   `Fecha >= FECHA_HASTA` del gid correspondiente y sin las filas con
#'   `Fecha < fecha_min`. Las filas de gids que no estan en `pos_hist` se
#'   conservan (salvo por el recorte de fecha).
filtrar_contenedores_cerrados <- function(historico, pos_hist,
                                          fecha_min = as.Date("2025-04-01"),
                                          reporte = TRUE) {

  stopifnot(all(c("gid", "Fecha") %in% names(historico)))
  stopifnot(all(c("GID", "FECHA_HASTA") %in% names(pos_hist)))

  # --- pos_hist -> tabla GID (chr) -> FECHA_HASTA de cierre ---
  ph <- as.data.frame(pos_hist)
  gcol <- attr(pos_hist, "sf_column")
  if (!is.null(gcol) && gcol %in% names(ph)) ph[[gcol]] <- NULL
  ph <- as.data.table(ph)[!is.na(FECHA_HASTA),
                          .(FECHA_HASTA = min(as.Date(FECHA_HASTA))),
                          by = .(GID = as.character(GID))]

  # --- marcar filas a descartar ---
  h <- as.data.table(historico)
  h[, `:=`(.gid_chr = as.character(gid), .Fecha_d = as.Date(Fecha))]
  h[ph, on = .(.gid_chr = GID), .fecha_hasta := i.FECHA_HASTA]

  cerrado <- !is.na(h$.fecha_hasta) & h$.Fecha_d >= h$.fecha_hasta
  previo  <- if (is.null(fecha_min)) rep(FALSE, nrow(h)) else h$.Fecha_d < as.Date(fecha_min)
  a_borrar <- cerrado | previo

  if (reporte) {
    message(sprintf(
      paste0("Contenedores cerrados: %s gids del historico figuran en pos_hist.\n",
             "  - Filas por contenedor cerrado (Fecha >= FECHA_HASTA): %s\n",
             "  - Filas previas a %s: %s\n",
             "Total eliminadas: %s de %s (%.2f%%). Filas resultantes: %s."),
      length(unique(h$.gid_chr[!is.na(h$.fecha_hasta)])),
      sum(cerrado),
      if (is.null(fecha_min)) "-" else format(as.Date(fecha_min)), sum(previo),
      sum(a_borrar), nrow(h), 100 * mean(a_borrar), sum(!a_borrar)
    ))
  }

  out <- h[!a_borrar]
  out[, c(".gid_chr", ".Fecha_d", ".fecha_hasta") := NULL]
  setDF(out)
  out
}


#' Wrapper de archivo: lee los .rds, depura y guarda.
#'
#' @param ruta_historico .rds del historico (con PERIODO y ultimo_levante).
#' @param ruta_pos_hist  .rds de dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.
#' @param ruta_salida    .rds a escribir ya depurado.
#' @param fecha_min      fecha minima a conservar (inclusive). Default 2025-04-01.
#' @param actualizar_todo TRUE reprocesa todo el historico desde cero.
#'   FALSE filtra solo las filas con Fecha posterior a la ya guardada en
#'   `ruta_salida` y las anexa (si `ruta_salida` no existe aun, igual
#'   procesa todo).
#' @return (invisible) el data.frame resultante.
actualizar_filtrar_cerrados <- function(
  ruta_historico = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_con_levante.rds",
  ruta_pos_hist  = "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds",
  ruta_salida    = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_depurado.rds",
  fecha_min      = as.Date("2025-04-01"),
  actualizar_todo = TRUE
) {
  message("Leyendo ", ruta_historico, " ...")
  historico <- readRDS(ruta_historico)

  corte <- if (actualizar_todo) as.Date(NA) else fecha_maxima_en(ruta_salida)
  incremental <- !is.na(corte)
  if (incremental) {
    historico <- historico[as.Date(historico$Fecha) > corte, , drop = FALSE]
    message(sprintf("Modo incremental: %s filas nuevas desde %s.",
                    nrow(historico), format(corte)))
    if (nrow(historico) == 0) {
      message("Sin filas nuevas. No se modifica ", ruta_salida)
      return(invisible(readRDS(ruta_salida)))
    }
  }

  message("Leyendo ", ruta_pos_hist, " ...")
  pos_hist <- readRDS(ruta_pos_hist)

  nuevas <- filtrar_contenedores_cerrados(historico, pos_hist, fecha_min = fecha_min)
  res <- if (incremental) {
    data.table::rbindlist(list(readRDS(ruta_salida), nuevas), fill = TRUE)
  } else {
    nuevas
  }
  res <- ordenar_historico(res)

  saveRDS(res, ruta_salida)
  message("Guardado en: ", ruta_salida)
  invisible(res)
}
