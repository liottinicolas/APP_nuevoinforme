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


#' Tabla de circuitos: una fila por Circuito_corto con sus datos y PERIODO.
#'
#' Los valores se toman de la fila con la Fecha mas reciente de cada circuito
#' (si alguno cambiara en el tiempo, queda el vigente). Ultima_fecha es el
#' ultimo dia con ubicaciones: distingue los circuitos que ya no estan.
#'
#' @param historico data.frame con Circuito, Municipio, Circuito_corto,
#'   Oficina, PERIODO y Fecha (salida de agregar_periodo()).
#' @return data.frame con Circuito, Municipio, Circuito_corto, Oficina,
#'   Periodo, Ultima_fecha, ordenado por Municipio y Circuito_corto.
resumir_circuitos <- function(historico) {
  dt <- data.table::as.data.table(
    historico[, c("Circuito", "Municipio", "Circuito_corto", "Oficina", "PERIODO", "Fecha")]
  )
  dt[, Fecha := as.Date(Fecha)]
  res <- dt[order(Fecha), .(
    Circuito     = data.table::last(Circuito),
    Municipio    = data.table::last(Municipio),
    Oficina      = data.table::last(Oficina),
    Periodo      = data.table::last(PERIODO),
    Ultima_fecha = max(Fecha)
  ), by = Circuito_corto]
  res <- res[order(Municipio, Circuito_corto),
             .(Circuito, Municipio, Circuito_corto, Oficina, Periodo, Ultima_fecha)]
  as.data.frame(res)
}


#' Turno de recoleccion segun Id_turno del maestro de circuitos.
TURNOS <- c("1" = "Matutino", "2" = "Vespertino", "3" = "Nocturno")

#' Dias de recoleccion segun el prefijo del GRUPO (sin el sufijo _M/_V/_N).
#' Mismas reglas que DIAS_FIJOS_POR_GRUPO en Informe Diario.ipynb. Los grupos
#' *_48HS (G1/G2) rotan cada 2 dias: se traducen aparte como "48 Horas".
DIAS_POR_GRUPO <- c(
  "LMV"    = "Lunes, Miércoles y Viernes",
  "MJS"    = "Martes, Jueves y Sábado",
  "MJD"    = "Martes, Jueves y Domingo",
  "LJ"     = "Lunes y Jueves",
  "DM"     = "Miércoles y Domingo",
  "MaV"    = "Martes y Viernes",
  "DIARIA" = "Diario excepto sábado",
  "DIARIO" = "Diario"
)


#' Agrega frecuencia, turno, grupo y dias de recoleccion a la tabla de circuitos.
#'
#' `maestro` sale de db/planificados/maestro_circuitos.csv, una copia de
#' DATOS_MAESTRO_CIRCUITOS de Informe Diario.ipynb (si cambia un circuito hay
#' que actualizar los dos). Para los circuitos del maestro, Periodo y
#' Frecuencia salen del maestro; para el resto (Fideicomiso e inactivos),
#' Frecuencia = 7 / Periodo del DFR y el resto de columnas queda NA.
#'
#' @param circuitos salida de resumir_circuitos().
#' @param maestro   data.frame con Circuito, Id_turno, Grupo, Frecuencia, Periodo.
#' @return `circuitos` con Frecuencia, Id_turno, Turno, Grupo y Dias_recoleccion.
completar_circuitos <- function(circuitos, maestro) {
  stopifnot(all(c("Circuito", "Id_turno", "Grupo", "Frecuencia", "Periodo") %in% names(maestro)))

  m <- match(circuitos$Circuito, maestro$Circuito)
  en_maestro <- !is.na(m)

  # Diferencias entre el Periodo del DFR y el del maestro (se usa el del maestro)
  periodo_maestro <- round(maestro$Periodo[m], 2)
  difiere <- en_maestro & abs(circuitos$Periodo - periodo_maestro) > 0.01
  if (any(difiere)) {
    message("Periodo del DFR distinto al del maestro (se usa el del maestro): ",
            paste(sprintf("%s (DFR %s / maestro %s)", circuitos$Circuito_corto[difiere],
                          circuitos$Periodo[difiere], periodo_maestro[difiere]),
                  collapse = ", "))
  }

  circuitos$Periodo    <- ifelse(en_maestro, periodo_maestro, circuitos$Periodo)
  circuitos$Frecuencia <- ifelse(en_maestro, maestro$Frecuencia[m], round(7 / circuitos$Periodo, 2))
  circuitos$Id_turno   <- as.integer(maestro$Id_turno[m])
  circuitos$Turno      <- unname(TURNOS[as.character(circuitos$Id_turno)])
  circuitos$Grupo      <- maestro$Grupo[m]

  prefijo <- sub("_.*$", "", circuitos$Grupo)
  circuitos$Dias_recoleccion <- ifelse(
    grepl("48HS", circuitos$Grupo), "48 Horas", unname(DIAS_POR_GRUPO[prefijo])
  )
  sin_traducir <- !is.na(circuitos$Grupo) & is.na(circuitos$Dias_recoleccion)
  if (any(sin_traducir)) {
    warning("Grupos sin dias de recoleccion definidos en DIAS_POR_GRUPO: ",
            paste(unique(circuitos$Grupo[sin_traducir]), collapse = ", "))
  }

  vigente_sin_maestro <- !en_maestro & circuitos$Oficina == "IM" &
    circuitos$Ultima_fecha == max(circuitos$Ultima_fecha)
  if (any(vigente_sin_maestro)) {
    message("Circuitos vigentes de IM sin datos en el maestro: ",
            paste(circuitos$Circuito_corto[vigente_sin_maestro], collapse = ", "))
  }

  circuitos[, c("Circuito", "Municipio", "Circuito_corto", "Oficina", "Periodo", "Frecuencia",
                "Id_turno", "Turno", "Grupo", "Dias_recoleccion", "Ultima_fecha")]
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
#' @param ruta_circuitos .rds con la tabla de circuitos (resumir_circuitos() +
#'   completar_circuitos()), que limpieza_datos.R publica como pin para la app.
#' @param ruta_maestro .csv con turno, grupo y frecuencia de cada circuito.
#' @return (invisible) el data.frame resultante.
actualizar_periodo <- function(
  ruta_historico = "db/10393_ubicaciones/historico_ubicaciones.rds",
  ruta_zona      = "db/DFR/RDS/dfr_V_DF_ZONA_RECORRIDO_GEOM.rds",
  ruta_salida    = "UNA_POR_CIRCUITO/rds/historico_ubicaciones_con_periodo.rds",
  actualizar_todo = TRUE,
  ruta_circuitos = "UNA_POR_CIRCUITO/rds/circuitos_periodo.rds",
  ruta_maestro   = "db/planificados/maestro_circuitos.csv"
) {
  guardar_circuitos <- function(h) {
    maestro <- read.csv(ruta_maestro, stringsAsFactors = FALSE)
    circuitos <- completar_circuitos(resumir_circuitos(h), maestro)
    saveRDS(circuitos, ruta_circuitos)
    message(sprintf("Tabla de circuitos: %s circuitos -> %s", nrow(circuitos), ruta_circuitos))
  }

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
      guardado <- readRDS(ruta_salida)
      # La tabla de circuitos se regenera igual: si se edito el maestro, el
      # cambio llega sin esperar a que entren ubicaciones nuevas.
      guardar_circuitos(guardado)
      return(invisible(guardado))
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
  guardar_circuitos(res)
  invisible(res)
}
