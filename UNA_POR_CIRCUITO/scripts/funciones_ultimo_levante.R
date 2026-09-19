# =============================================================================
# funciones_ultimo_levante.R
# -----------------------------------------------------------------------------
# Para cada (dia, contenedor) del historico de ubicaciones, calcula el
# ULTIMO LEVANTE: el valor mas reciente de `Fecha_hora_pasaje` en
# historico_llenado para ese mismo gid, considerando SOLO registros de
# llenado cuya `Fecha` sea ESTRICTAMENTE ANTERIOR (< , nunca =) al dia del
# historico. Si no hay ninguno -> NA.
#
# Implementado con data.table (rolling join) para que escale a millones de
# filas y sea barato de re-ejecutar cuando se actualizan los datos.
#
# Modo incremental (actualizar_todo = FALSE): si ya existe `ruta_salida`,
# solo se calcula `ultimo_levante` para las filas de `historico` con Fecha
# posterior a la maxima ya guardada (el calculo es por (gid, Fecha) contra
# el historico de llenado completo, no depende de las demas filas del
# historico de ubicaciones), y se anexan.
# =============================================================================

library(data.table)
source("UNA_POR_CIRCUITO/scripts/funciones_comunes.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a


#' Anexa la columna `ultimo_levante` al historico de ubicaciones.
#'
#' @param historico data.frame/tibble con al menos las columnas `gid` y
#'   `Fecha` (Date). Se asume una fila por (Fecha, gid).
#' @param llenado   data.frame/tibble de historico_llenado con al menos
#'   `gid`, `Fecha` (Date) y `Fecha_hora_pasaje` (POSIXct).
#' @param col_salida nombre de la columna resultado. Default "ultimo_levante".
#'
#' @return El mismo `historico` (como data.frame) con una columna POSIXct
#'   adicional: para cada fila, el `Fecha_hora_pasaje` mas reciente de un
#'   llenado del mismo gid con `Fecha` < `Fecha` del historico; NA si no hay.
agregar_ultimo_levante <- function(historico,
                                   llenado,
                                   col_salida = "ultimo_levante") {

  stopifnot(all(c("gid", "Fecha") %in% names(historico)))
  stopifnot(all(c("gid", "Fecha", "Fecha_hora_pasaje") %in% names(llenado)))

  tz <- attr(llenado[["Fecha_hora_pasaje"]], "tzone") %||% ""

  h  <- as.data.table(historico)
  ll <- as.data.table(llenado)[, .(
    gid   = as.character(gid),
    Fecha = as.Date(Fecha),
    pasaje = as.POSIXct(Fecha_hora_pasaje)
  )]
  h[, `:=`(gid = as.character(gid), Fecha = as.Date(Fecha))]

  # 1) Un valor por (gid, dia de llenado): el pasaje mas reciente de ese dia.
  #    Descartamos filas sin pasaje: no aportan al "mas reciente".
  agg <- ll[!is.na(pasaje), .(pasaje = max(pasaje)), by = .(gid, Fecha)]

  # 2) Maximo acumulado por gid a lo largo de los dias de llenado:
  #    pasaje_acum[i] = max(Fecha_hora_pasaje) de TODOS los llenados del gid
  #    con Fecha <= Fecha[i]. Asi "el mas reciente" no se pierde aunque un
  #    dia de llenado posterior tenga un pasaje anterior.
  setorder(agg, gid, Fecha)
  agg[, pasaje_acum := as.POSIXct(cummax(as.numeric(pasaje)),
                                  origin = "1970-01-01", tz = tz),
      by = gid]

  # 3) Rolling join: para cada (gid, dia_historico D) buscamos el ultimo
  #    dia de llenado con Fecha < D. Como Fecha es diaria, Fecha < D
  #    equivale a Fecha <= D - 1 -> join contra (D - 1) con roll = +Inf
  #    (last observation carried forward).
  claves <- unique(h[, .(gid, Fecha)])
  claves[, Fecha_join := Fecha - 1L]

  setkey(agg, gid, Fecha)
  matched <- agg[claves,
                 on = .(gid, Fecha = Fecha_join),
                 roll = Inf,
                 .(gid, Fecha = i.Fecha, ultimo_levante = pasaje_acum)]

  # 4) Update join sobre el historico (preserva orden y columnas)
  h[matched, on = .(gid, Fecha), (col_salida) := i.ultimo_levante]

  setDF(h)
  h
}


#' Wrapper de archivo: lee los .rds, calcula y guarda el resultado.
#'
#' @param ruta_historico .rds del historico de ubicaciones (ya con PERIODO).
#' @param ruta_llenado   .rds de historico_llenadoGol.
#' @param ruta_salida    .rds a escribir con la columna `ultimo_levante`.
#' @param actualizar_todo TRUE reprocesa todo el historico desde cero.
#'   FALSE calcula solo las filas con Fecha posterior a la ya guardada en
#'   `ruta_salida` y las anexa (si `ruta_salida` no existe aun, igual
#'   procesa todo).
#' @return (invisible) el data.frame resultante.
actualizar_ultimo_levante <- function(
  ruta_historico = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_con_periodo.rds",
  ruta_llenado   = "db/GOL_reportes/historico_llenadoGol.rds",
  ruta_salida    = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_con_levante.rds",
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

  message("Leyendo ", ruta_llenado, " ...")
  llenado <- readRDS(ruta_llenado)

  message("Calculando ultimo levante por (dia, contenedor) ...")
  nuevas <- agregar_ultimo_levante(historico, llenado)
  res <- if (incremental) {
    data.table::rbindlist(list(readRDS(ruta_salida), nuevas), fill = TRUE)
  } else {
    nuevas
  }
  res <- ordenar_historico(res)

  n_ok <- sum(!is.na(res$ultimo_levante))
  message(sprintf("Filas: %s | con ultimo_levante: %s | NA: %s",
                  nrow(res), n_ok, nrow(res) - n_ok))

  saveRDS(res, ruta_salida)
  message("Guardado en: ", ruta_salida)
  invisible(res)
}
