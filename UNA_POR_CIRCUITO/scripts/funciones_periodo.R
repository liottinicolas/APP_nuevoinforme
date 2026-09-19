# =============================================================================
# funciones_periodo.R
# -----------------------------------------------------------------------------
# Paso 1 del pipeline UNA POR CIRCUITO.
# Copia `historico_ubicaciones` y le anexa la columna PERIODO tomada de la
# capa de zonas de recorrido (dfr_V_DF_ZONA_RECORRIDO:GEOM), cruzando
#     historico_ubicaciones$Circuito_corto  ==  zona$COD_RECORRIDO
# Los circuitos que no estan en la capa se cargan a mano.
#
# Modo incremental (actualizar_todo = FALSE): si ya existe `ruta_salida`,
# solo se procesan las filas de `ruta_historico` con Fecha posterior a la
# maxima ya guardada, y se anexan (el join contra `zona` es por fila, no
# depende de las demas filas del historico).
# =============================================================================

source("UNA_POR_CIRCUITO/scripts/funciones_comunes.R")


#' Circuitos sin poligono en la capa de zonas -> PERIODO asignado a mano.
PERIODO_MANUAL <- c(
  "A_103" = 2,
  "A_104" = 2.33,
  "A_119" = 2.33,
  "A_201" = 2.33,
  "D_121" = 2.33,
  "E_116" = 3.5
)


#' Anexa la columna PERIODO al historico de ubicaciones.
#'
#' @param historico data.frame/tibble con la columna `Circuito_corto`.
#' @param zona      capa `dfr_V_DF_ZONA_RECORRIDO:GEOM` (sf o data.frame) con
#'   columnas `COD_RECORRIDO` y `PERIODO`.
#' @param manual    vector nombrado circuito -> PERIODO para los que no estan
#'   en `zona`. Default `PERIODO_MANUAL`.
#'
#' @return El `historico` (data.frame) con la columna numerica `PERIODO`.
agregar_periodo <- function(historico, zona, manual = PERIODO_MANUAL) {

  stopifnot("Circuito_corto" %in% names(historico))
  stopifnot(all(c("COD_RECORRIDO", "PERIODO") %in% names(zona)))

  h <- as.data.frame(historico)

  za <- as.data.frame(zona)
  gcol <- attr(zona, "sf_column")
  if (!is.null(gcol) && gcol %in% names(za)) za[[gcol]] <- NULL

  # COD_RECORRIDO -> PERIODO (la capa repite codigos; PERIODO es igual dentro
  # de cada uno, tomamos el primero).
  lookup <- za[!duplicated(za$COD_RECORRIDO), c("COD_RECORRIDO", "PERIODO")]
  h$PERIODO <- lookup$PERIODO[match(h$Circuito_corto, lookup$COD_RECORRIDO)]

  # Asignacion manual de los circuitos sin match.
  for (circ in names(manual)) {
    h$PERIODO[h$Circuito_corto == circ] <- manual[[circ]]
  }

  h
}


#' Wrapper de archivo: lee los .rds, agrega PERIODO y guarda.
#'
#' @param ruta_historico .rds del historico de ubicaciones original.
#' @param ruta_zona      .rds de dfr_V_DF_ZONA_RECORRIDO_GEOM.
#' @param ruta_salida    .rds a escribir con la columna PERIODO.
#' @param actualizar_todo TRUE reprocesa todo el historico desde cero.
#'   FALSE procesa solo las filas con Fecha posterior a la ya guardada en
#'   `ruta_salida` y las anexa (si `ruta_salida` no existe aun, igual
#'   procesa todo).
#' @return (invisible) el data.frame resultante.
actualizar_periodo <- function(
  ruta_historico = "db/10393_ubicaciones/historico_ubicaciones.rds",
  ruta_zona      = "db/DFR/RDS/dfr_V_DF_ZONA_RECORRIDO_GEOM.rds",
  ruta_salida    = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_con_periodo.rds",
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

  message("Leyendo ", ruta_zona, " ...")
  zona <- readRDS(ruta_zona)

  nuevas <- agregar_periodo(historico, zona)
  res <- if (incremental) {
    data.table::rbindlist(list(readRDS(ruta_salida), nuevas), fill = TRUE)
  } else {
    nuevas
  }
  res <- ordenar_historico(res)

  n_sin    <- sum(is.na(res$PERIODO))
  circ_sin <- sort(unique(res$Circuito_corto[is.na(res$PERIODO)]))
  message(sprintf(
    "Filas: %s | con PERIODO: %s | sin PERIODO: %s%s",
    nrow(res), sum(!is.na(res$PERIODO)), n_sin,
    if (n_sin) paste0(" (", paste(circ_sin, collapse = ", "), ")") else ""
  ))

  saveRDS(res, ruta_salida)
  message("Guardado en: ", ruta_salida)
  invisible(res)
}
