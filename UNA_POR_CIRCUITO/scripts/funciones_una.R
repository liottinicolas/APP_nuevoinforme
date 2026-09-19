# =============================================================================
# funciones_una.R
# -----------------------------------------------------------------------------
# UNA = Unidad de Acumulacion Normalizada.
# Relacion adimensional entre el tiempo de acumulacion de residuos en el
# contenedor y el tiempo maximo admisible de acumulacion.
#
#   %UNA = (tiempo_acumulacion / tiempo_maximo_admisible) * 100
#        = (tiempo_acumulacion / (7 / f)) * 100        con  f = 7 / PERIODO
#
# donde f es la frecuencia semanal de levante y PERIODO los dias entre
# levantes (columna ya presente en el historico).
#
#   - Dia_acumulacion : dias calendario que el contenedor lleva sin levantarse.
#                     Minimo 1: si se levanto el dia anterior, aunque haya sido
#                     unas horas antes, vale 1; de ahi suma de a 1 dia.
#                     NA si no hubo levante previo.
#                       Dia_acumulacion = max(1, dia_historico - dia_levante)
#
#   - UNA_pordia    : Dia_acumulacion normalizado por PERIODO (dias admisibles).
#                       UNA_pordia = Dia_acumulacion / PERIODO * 100
#
#   - UNA_matutino / UNA_vespertino / UNA_nocturno :
#     misma UNA pero con resolucion de TURNO (8 h). Los turnos arrancan a las
#     06:00 (matutino, primer turno del dia), 14:00 (vespertino) y 22:00
#     (nocturno) -> grilla uniforme de 8 h anclada a las 06:00.
#     El turno SIGUIENTE al turno en que se levanto (aunque el levante haya
#     sido un rato antes) arranca en 100 / (3 * PERIODO)  -- es decir la UNA
#     de 24 h dividida en los 3 turnos -- no en 0. Cada turno siguiente sin
#     recoleccion suma otro 100 / (3 * PERIODO). Asi, 3 turnos (24 h) despues
#     del turno del levante la UNA por turno iguala a la UNA del dia.
#       k_lev    = floor((ultimo_levante - 06:00) / 8h)   # turno del levante
#       turnos_X = max(1, indice_turno_X - k_lev)
#       UNA_X    = turnos_X / (3 * PERIODO) * 100
#     Indices de turno del dia D (dias desde epoch): matutino 3D, vespertino
#     3D+1, nocturno 3D+2.
#
# Nota: los levantes del turno nocturno llevan en `Fecha` (del llenado) el
# dia operativo y en `Fecha_hora_pasaje` la hora real (misma noche o
# madrugada siguiente). La grilla anclada a las 06:00 asigna ambos casos al
# "nocturno" del dia operativo, consistente con esa `Fecha`.
# =============================================================================

library(data.table)
source("UNA_POR_CIRCUITO/scripts/funciones_comunes.R")


#' Anexa las columnas de UNA al historico.
#'
#' @param historico data.frame/tibble con columnas `Fecha` (Date),
#'   `PERIODO` (numeric) y `ultimo_levante` (POSIXct).
#'
#' @return El mismo `historico` (data.frame) con, a continuacion de
#'   `ultimo_levante`, las columnas `Dia_acumulacion` (dias enteros),
#'   `UNA_pordia`, `UNA_matutino`, `UNA_vespertino` y `UNA_nocturno` (%).
#'   Todas son NA en las filas sin `ultimo_levante`.
agregar_una <- function(historico) {

  stopifnot(all(c("Fecha", "PERIODO", "ultimo_levante") %in% names(historico)))

  # data.table + asignacion por referencia (:=): evita copiar el frame entero
  # en cada columna nueva (clave con datasets de millones de filas).
  dt <- data.table::as.data.table(historico)

  viejas <- intersect(c("UNA_porturnos", "UNA_porhora"), names(dt))
  if (length(viejas)) dt[, (viejas) := NULL]

  seg_turno <- 8 * 3600

  # --- Dia_acumulacion: dias calendario sin levante, piso 1 ---
  dt[, Dia_acumulacion := as.integer(
        pmax(1, as.numeric(as.Date(Fecha) - as.Date(ultimo_levante))))]

  # --- UNA_pordia: Dia_acumulacion normalizado por PERIODO ---
  dt[, UNA_pordia := Dia_acumulacion / PERIODO * 100]

  # --- UNA por turno: acumulacion en turnos de 8 h (grilla anclada 06:00) ---
  # .klev = indice del turno en que ocurrio el levante.
  # .D    = dia del historico en dias desde epoch (matutino 3D, vesp 3D+1,
  #         noc 3D+2). Cada turno aporta 100 / (3 * PERIODO).
  # El turno siguiente al del levante ya vale 1 escalon (no 0): piso en 1.
  dt[, .klev := floor((as.numeric(ultimo_levante) - 6 * 3600) / seg_turno)]
  dt[, .D := as.integer(as.Date(Fecha))]

  dt[, UNA_matutino   := pmax(1, (3L * .D + 0L) - .klev) / (3 * PERIODO) * 100]
  dt[, UNA_vespertino := pmax(1, (3L * .D + 1L) - .klev) / (3 * PERIODO) * 100]
  dt[, UNA_nocturno   := pmax(1, (3L * .D + 2L) - .klev) / (3 * PERIODO) * 100]

  dt[, c(".klev", ".D") := NULL]

  # Columnas nuevas justo despues de `ultimo_levante`, en orden.
  nuevas <- c("Dia_acumulacion", "UNA_pordia",
              "UNA_matutino", "UNA_vespertino", "UNA_nocturno")
  data.table::setcolorder(dt, c(setdiff(names(dt), nuevas), nuevas))

  data.table::setDF(dt)
  dt
}


#' Wrapper de archivo: lee el .rds, agrega UNA y guarda (sobrescribe).
#'
#' Modo incremental (actualizar_todo = FALSE): este paso sobrescribe el
#' mismo archivo que produce el paso 3, asi que una fila sin `ultimo_levante`
#' (UNA = NA "de verdad") y una fila nueva todavia sin procesar se ven
#' identicas si solo miramos las columnas. Por eso se usa un checkpoint
#' aparte (`ruta_checkpoint`) con la maxima Fecha ya procesada por este
#' paso; solo se recalcula UNA para las filas posteriores a esa Fecha.
#'
#' @param ruta_historico .rds del historico depurado (con PERIODO y
#'   ultimo_levante). Por defecto se sobrescribe el mismo archivo.
#' @param ruta_salida    .rds de salida. Default = ruta_historico.
#' @param actualizar_todo TRUE reprocesa UNA para todo el historico desde
#'   cero. FALSE calcula solo las filas con Fecha posterior al checkpoint
#'   (si no hay checkpoint aun, igual procesa todo).
#' @param ruta_checkpoint .rds donde se guarda la marca de agua del modo
#'   incremental (un unico Date).
#' @return (invisible) el data.frame resultante.
actualizar_una <- function(
  ruta_historico = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_depurado.rds",
  ruta_salida    = ruta_historico,
  actualizar_todo = TRUE,
  ruta_checkpoint = "UNA_POR_CIRCUITO/rds/checkpoint_una.rds"
) {
  message("Leyendo ", ruta_historico, " ...")
  historico <- readRDS(ruta_historico)

  corte <- if (actualizar_todo || !file.exists(ruta_checkpoint)) {
    as.Date(NA)
  } else {
    readRDS(ruta_checkpoint)
  }
  incremental <- !is.na(corte)

  if (incremental) {
    es_nueva <- as.Date(historico$Fecha) > corte
    message(sprintf("Modo incremental: %s filas nuevas desde %s.",
                    sum(es_nueva), format(corte)))
    if (!any(es_nueva)) {
      message("Sin filas nuevas. No se modifica ", ruta_salida)
      return(invisible(historico))
    }
    viejas <- historico[!es_nueva, , drop = FALSE]
    nuevas <- agregar_una(historico[es_nueva, , drop = FALSE])
    rm(historico); gc(FALSE)
    res <- data.table::rbindlist(list(viejas, nuevas), fill = TRUE)
  } else {
    res <- agregar_una(historico)
    rm(historico); gc(FALSE)
  }
  res <- ordenar_historico(res)

  n_ok <- sum(!is.na(res$UNA_pordia))
  resumen <- function(x) paste(names(summary(x)), round(summary(x), 1),
                               sep = "=", collapse = "  ")
  message(sprintf(
    paste0("Filas: %s | con dato (ultimo_levante no NA): %s | NA: %s\n",
           "  Dia_acumulacion   : %s\n",
           "  UNA_pordia (%%)    : %s\n",
           "  UNA_matutino (%%)  : %s\n",
           "  UNA_vespertino (%%): %s\n",
           "  UNA_nocturno (%%)  : %s"),
    nrow(res), n_ok, nrow(res) - n_ok,
    resumen(res$Dia_acumulacion), resumen(res$UNA_pordia),
    resumen(res$UNA_matutino), resumen(res$UNA_vespertino),
    resumen(res$UNA_nocturno)
  ))

  saveRDS(res, ruta_salida)
  saveRDS(max(as.Date(res$Fecha)), ruta_checkpoint)
  message("Guardado en: ", ruta_salida)
  invisible(res)
}
