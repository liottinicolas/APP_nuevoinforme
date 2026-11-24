# =============================================================================
# Funciones del análisis de servicios (viajes GOL) por día y turno
# Circuitos: B_101, B_102, B_103, todos los de CH y los de C hasta C_109.
# Definiciones completas en tasks/plan.md
# =============================================================================

suppressMessages(library(data.table))

CIRCUITOS_B <- c("B_101", "B_102", "B_103")
# Circuitos de C que no entran en el análisis (decisión del usuario, 2026-10-15).
# Siguen siendo de la IM: sus camiones cuentan en el uso de la flota.
CIRCUITOS_C_EXCLUIDOS <- sprintf("C_%d", 110:116)

# Los sábados no hay turno nocturno. Los pocos registros con esa combinación se
# excluyen y el sábado-nocturno no se cuenta en ninguna cuenta (ni como turno con 0).
es_sabado_noche <- function(fecha, turno) format(fecha, "%u") == "6" & turno == "Nocturno"

grid_dia_turno <- function(desde, hasta) {
  g <- CJ(Fecha = seq(desde, hasta, by = "day"), Turno = c("Matutino", "Vespertino", "Nocturno"))
  g[!es_sabado_noche(Fecha, Turno)]
}

# Motivos que derivan a grúa (ver vistas/informe_operativa/informeOP_generar_pdf.py, procesar_grua)
MOTIVOS_GRUA <- c("Sobrepeso", "Contenedor Fuera de Alcance", "Contenedor Cruzado", "Calle Cerrada",
                  "Contenedor Roto (choque, desfonde, etc.)", "Rotura sin retorno a circuito",
                  "Rotura con retorno a circuito", "Tapa Bloqueda", "Contenedor Volcado",
                  "Buzonera Girada")

# -----------------------------------------------------------------------------
# Viajes de grúa probables (levantes puntuales). Sin matrícula, se detectan por
# forma del viaje, calculada sobre TODOS sus circuitos (no solo los seleccionados):
#   regla A : <= 40 contenedores y posiciones dispersas (densidad <= 0.5)
#             densidad = contenedores / (máx - mín posición + 1), sumado por circuito
#   regla B : <= 40 contenedores, >= 3 circuitos y <= 2 contenedores por circuito
#             (la densidad no detecta 1 contenedor por circuito)
# pct_motivo_grua_previo (validación, no se usa para marcar): % de contenedores
# cuya visita previa (hasta 7 días antes) tuvo un motivo de grúa.
# -----------------------------------------------------------------------------
marcar_viajes_grua <- function(llenado, desde = NULL, hasta = NULL,
                               max_cont = 40, max_densidad = 0.5) {
  ll <- as.data.table(llenado)[contenedor_activo == "S",
                               .(Fecha, Id_viaje_GOL, Circuito_corto, Posicion, gid, Levantado, Incidencia)]
  if (!is.null(hasta)) ll <- ll[Fecha <= hasta]

  previas <- ll[!is.na(Levantado), .(motivo_grua = any(Incidencia %in% MOTIVOS_GRUA)), by = .(gid, Fecha)]
  setkey(previas, gid, Fecha)
  if (!is.null(desde)) ll <- ll[Fecha >= desde]
  ll[, fecha_ant := Fecha - 1]
  ll[, motivo_previo := previas[ll, on = .(gid, Fecha = fecha_ant), roll = 7, x.motivo_grua] %in% TRUE]

  vc <- ll[, .(n = .N, span = max(Posicion) - min(Posicion) + 1), by = .(Id_viaje_GOL, Circuito_corto)]
  v <- vc[, .(contenedores_viaje = sum(n), circuitos_viaje = .N, densidad = sum(n) / sum(span)),
          by = Id_viaje_GOL]
  v <- ll[, .(pct_motivo_grua_previo = mean(motivo_previo)), by = Id_viaje_GOL][v, on = "Id_viaje_GOL"]

  v[, regla_grua := fcase(
    contenedores_viaje <= max_cont & densidad <= max_densidad, "A: posiciones dispersas",
    contenedores_viaje <= max_cont & circuitos_viaje >= 3 &
      contenedores_viaje / circuitos_viaje <= 2, "B: pocos por circuito",
    default = NA_character_)]
  v[, es_grua := !is.na(regla_grua)][]
}

# -----------------------------------------------------------------------------
# Tarea 1: universo de análisis
#   - filtra circuitos seleccionados, período y contenedores activos
#   - grupo:     "B_10x" | "CH" | "C"
#   - visitado:  se fue al contenedor (Levantado S/N o tiene hora de pasaje)
#   - levantado: Levantado == "S"
# desde/hasta: Date o NULL (sin límite)
# -----------------------------------------------------------------------------
preparar_universo <- function(llenado, desde = NULL, hasta = NULL, verbose = TRUE) {
  dt <- as.data.table(llenado)

  dt <- dt[(Circuito_corto %in% CIRCUITOS_B | Municipio %in% c("CH", "C")) &
            !Circuito_corto %in% CIRCUITOS_C_EXCLUIDOS]
  if (!is.null(desde)) dt <- dt[Fecha >= desde]
  if (!is.null(hasta)) dt <- dt[Fecha <= hasta]

  n_inactivos <- dt[contenedor_activo != "S" | is.na(contenedor_activo), .N]
  dt <- dt[contenedor_activo == "S"]

  dt[, grupo := fifelse(Circuito_corto %in% CIRCUITOS_B, "B_10x", Municipio)]
  dt[, visitado := Levantado %in% c("S", "N") | !is.na(Fecha_hora_pasaje)]
  dt[, levantado := Levantado %in% "S"]
  dt[, Turno := as.character(Turno_levantado)]

  n_sab_noche <- dt[es_sabado_noche(Fecha, Turno), uniqueN(Id_viaje_GOL)]
  dt <- dt[!es_sabado_noche(Fecha, Turno)]

  if (verbose) {
    message(sprintf("  Excluidos por sábado nocturno (no hay turno): %d viajes", n_sab_noche))
    message(sprintf("Universo: %s filas, %s viajes, %s circuitos, %s a %s",
                    format(nrow(dt), big.mark = ".", decimal.mark = ","),
                    format(uniqueN(dt$Id_viaje_GOL), big.mark = ".", decimal.mark = ","),
                    uniqueN(dt$Circuito_corto),
                    min(dt$Fecha), max(dt$Fecha)))
    message(sprintf("  Excluidas por contenedor inactivo: %s filas",
                    format(n_inactivos, big.mark = ".", decimal.mark = ",")))
    message(sprintf("  Visitadas solo por hora de pasaje (Levantado NA): %s filas",
                    dt[is.na(Levantado) & !is.na(Fecha_hora_pasaje), .N]))
  }

  dt[, .(Fecha, Turno, Id_viaje_GOL, grupo, Municipio, Circuito, Circuito_corto,
         Posicion, gid, Levantado, Incidencia, visitado, levantado)]
}

# -----------------------------------------------------------------------------
# Tarea 2: una fila por viaje (servicio)
# Solo cuenta filas de los circuitos seleccionados (viajes mixtos incluidos).
# -----------------------------------------------------------------------------
resumir_viajes <- function(universo) {
  # circuitos del viaje sin ninguna visita (listados pero no atendidos por este camión)
  por_circ <- universo[, .(sin_visita = !any(visitado)), by = .(Id_viaje_GOL, Circuito_corto)]
  sin_vis <- por_circ[, .(circuitos_sin_visita = sum(sin_visita)), by = Id_viaje_GOL]

  v <- universo[, .(
    grupos            = paste(sort(unique(grupo)), collapse = ", "),
    circuitos         = paste(sort(unique(Circuito_corto)), collapse = ", "),
    n_circuitos       = uniqueN(Circuito_corto),
    total_contenedores = .N,
    visitados         = sum(visitado),
    levantados        = sum(levantado),
    no_levantados     = sum(visitado & !levantado)
  ), by = .(Id_viaje_GOL, Fecha, Turno)]

  v <- sin_vis[v, on = "Id_viaje_GOL"]
  v[, pct_completo  := visitados / total_contenedores]
  v[, pct_levantado := levantados / total_contenedores]

  setcolorder(v, c("Id_viaje_GOL", "Fecha", "Turno", "grupos", "circuitos", "n_circuitos",
                   "circuitos_sin_visita", "total_contenedores", "visitados", "levantados",
                   "no_levantados", "pct_completo", "pct_levantado"))
  setorder(v, Fecha, Turno, Id_viaje_GOL)
  v[]
}

# -----------------------------------------------------------------------------
# Tarea 3: una fila por circuito-día-turno, uniendo todos los viajes que lo
# atendieron. Cada gid cuenta una vez; está visitado si algún viaje lo visitó.
# -----------------------------------------------------------------------------
resumir_circuitos <- function(universo) {
  por_gid <- universo[, .(
    visitado  = any(visitado),
    levantado = any(levantado)
  ), by = .(Fecha, Turno, grupo, Municipio, Circuito_corto, gid)]

  viajes <- universo[, .(
    n_viajes = uniqueN(Id_viaje_GOL),
    viajes   = paste(sort(unique(Id_viaje_GOL)), collapse = ", ")
  ), by = .(Fecha, Turno, Circuito_corto)]

  c <- por_gid[, .(
    total_contenedores = .N,
    visitados          = sum(visitado),
    levantados         = sum(levantado)
  ), by = .(Fecha, Turno, grupo, Municipio, Circuito_corto)]

  c <- viajes[c, on = .(Fecha, Turno, Circuito_corto)]
  c[, pct_completo  := visitados / total_contenedores]
  c[, pct_levantado := levantados / total_contenedores]

  setcolorder(c, c("Fecha", "Turno", "grupo", "Municipio", "Circuito_corto", "n_viajes", "viajes",
                   "total_contenedores", "visitados", "levantados", "pct_completo", "pct_levantado"))
  setorder(c, Fecha, Turno, Circuito_corto)
  c[]
}

# -----------------------------------------------------------------------------
# Tarea 4: resumen por Fecha x Turno, total y por grupo.
# En el TOTAL, un viaje que toca varios grupos cuenta una sola vez.
# Los indicadores de circuito salen de la tabla circuito-día-turno.
# -----------------------------------------------------------------------------
resumir_dia_turno <- function(universo, circuitos) {
  resumir <- function(u, c, por) {
    pv <- u[, .(tot = .N, vis = sum(visitado), lev = sum(levantado)),
            by = c(por, "Id_viaje_GOL")]
    r <- pv[, .(
      servicios                   = .N,
      total_contenedores          = sum(tot),
      visitados                   = sum(vis),
      levantados                  = sum(lev),
      prom_contenedores_por_viaje = mean(tot),
      prom_levantados_por_viaje   = mean(lev),
      pct_completo                = sum(vis) / sum(tot),
      pct_completo_prom_viajes    = mean(vis / tot)
    ), by = por]
    rc <- c[, .(
      circuitos_atendidos     = .N,
      pct_circuitos_completos = mean(pct_completo >= 0.95),
      circuitos_sin_visita    = sum(visitados == 0)
    ), by = por]
    rc[r, on = por]
  }

  total  <- resumir(universo, circuitos, c("Fecha", "Turno"))[, grupo := "TOTAL"]
  grupos <- resumir(universo, circuitos, c("Fecha", "Turno", "grupo"))
  r <- rbind(total, grupos, use.names = TRUE)

  setcolorder(r, c("Fecha", "Turno", "grupo", "servicios", "total_contenedores", "visitados",
                   "levantados", "prom_contenedores_por_viaje", "prom_levantados_por_viaje",
                   "pct_completo", "pct_completo_prom_viajes", "circuitos_atendidos",
                   "pct_circuitos_completos", "circuitos_sin_visita"))
  r[, orden := match(grupo, c("TOTAL", "B_10x", "CH", "C"))]
  setorder(r, Fecha, Turno, orden)
  r[, orden := NULL][]
}

# -----------------------------------------------------------------------------
# Tarea 5: tamaño del circuito según historico_ubicaciones (posiciones) del
# mismo día, sin contenedores en Mantenimiento / Sin instalar.
# -----------------------------------------------------------------------------
cruzar_posiciones <- function(circuitos, ubicaciones, verbose = TRUE) {
  ub <- as.data.table(ubicaciones)[Circuito_corto %in% unique(circuitos$Circuito_corto) &
                                     Fecha >= min(circuitos$Fecha) & Fecha <= max(circuitos$Fecha)]
  tam <- ub[is.na(Estado) | !Estado %in% c("Mantenimiento", "Sin instalar"),
            .(contenedores_segun_posiciones = uniqueN(gid)), by = .(Fecha, Circuito_corto)]

  c <- tam[circuitos, on = .(Fecha, Circuito_corto)]
  c[, dif_vs_gol := total_contenedores - contenedores_segun_posiciones]
  c[, pct_completo_sobre_posiciones := visitados / contenedores_segun_posiciones]

  if (verbose) {
    message(sprintf("Cruce con posiciones: %.1f%% de circuito-día-turno sin dato de posiciones",
                    100 * mean(is.na(c$contenedores_segun_posiciones))))
    message(sprintf("  |dif GOL - posiciones|: mediana %s, p90 %s",
                    median(abs(c$dif_vs_gol), na.rm = TRUE),
                    quantile(abs(c$dif_vs_gol), 0.9, na.rm = TRUE, names = FALSE)))
  }
  setcolorder(c, c(setdiff(names(circuitos), c("pct_completo", "pct_levantado")),
                   "pct_completo", "pct_levantado", "contenedores_segun_posiciones",
                   "dif_vs_gol", "pct_completo_sobre_posiciones"))
  setorder(c, Fecha, Turno, Circuito_corto)
  c[]
}

# -----------------------------------------------------------------------------
# Calidad del servicio del período por grupo x turno (+ TOTAL por turno).
# Tabla "Calidad del servicio actual" del documento para decisores.
# Medias sobre los turnos en que hubo servicio. Circuito parcial = el viaje trajo
# más de UMBRAL_PARCIAL contenedores menos que el circuito según posiciones.
# Requiere circuitos con el cruce de posiciones (cruzar_posiciones).
# -----------------------------------------------------------------------------
UMBRAL_PARCIAL <- 20

resumir_calidad <- function(dia_turno, circuitos) {
  d <- dia_turno[, .(
    turnos_con_servicio     = .N,
    prom_camiones_por_turno = mean(servicios),
    prom_levantados_por_turno = mean(levantados),
    prom_contenedores_por_camion = sum(total_contenedores) / sum(servicios),
    prom_levantados_por_camion   = sum(levantados) / sum(servicios),
    pct_visitados           = sum(visitados) / sum(total_contenedores)
  ), by = .(grupo, Turno)]

  ind_circ <- function(x) x[, .(
    pct_circuitos_completos = mean(pct_completo >= 0.95),
    pct_circuitos_parciales = mean(dif_vs_gol < -UMBRAL_PARCIAL, na.rm = TRUE)
  ), by = .(grupo, Turno)]
  cg <- rbind(ind_circ(circuitos), ind_circ(copy(circuitos)[, grupo := "TOTAL"]))

  r <- cg[d, on = .(grupo, Turno)]
  r[, orden_g := match(grupo, c("CH", "C", "B_10x", "TOTAL"))]
  r[, orden_t := match(Turno, c("Nocturno", "Matutino", "Vespertino"))]
  setorder(r, orden_g, orden_t)
  r[, c("orden_g", "orden_t") := NULL]
  setcolorder(r, c("grupo", "Turno"))
  r[]
}

# -----------------------------------------------------------------------------
# Validación de la regla de grúa: % de contenedores con motivo de grúa en la
# visita previa, en viajes marcados vs el resto (todo el sistema y universo).
# -----------------------------------------------------------------------------
resumir_validacion_grua <- function(grua, ids_universo) {
  v <- function(x, ambito) x[, .(
    viajes = .N,
    pct_motivo_grua_previo = mean(pct_motivo_grua_previo)
  ), by = .(es_grua)][, ambito := ambito]
  r <- rbind(v(grua, "Todo el sistema"), v(grua[Id_viaje_GOL %in% ids_universo], "Circuitos analizados"))
  r[, tipo_viaje := fifelse(es_grua, "Grúa probable (excluido)", "Resto")]
  setcolorder(r, c("ambito", "tipo_viaje", "viajes", "pct_motivo_grua_previo"))
  setorder(r, ambito, -es_grua)
  r[, es_grua := NULL][]
}

# -----------------------------------------------------------------------------
# Resumen del período por circuito (para revisar qué circuitos no van)
# -----------------------------------------------------------------------------
resumir_por_circuito <- function(universo, circuitos) {
  v <- universo[, .(viajes = uniqueN(Id_viaje_GOL)), by = .(grupo, Circuito_corto)]
  c <- circuitos[, .(
    dias_turno_con_servicio = .N,
    dias_turno_con_visitas  = sum(visitados > 0),
    prom_contenedores       = mean(total_contenedores),
    prom_visitados          = mean(visitados),
    prom_levantados         = mean(levantados),
    pct_completo            = sum(visitados) / sum(total_contenedores),
    pct_veces_completo_95   = mean(pct_completo >= 0.95),
    pct_veces_sin_visita    = mean(visitados == 0),
    turnos                  = paste(sort(unique(Turno)), collapse = ", ")
  ), by = .(grupo, Circuito_corto)]
  r <- v[c, on = .(grupo, Circuito_corto)]
  setcolorder(r, c("grupo", "Circuito_corto", "viajes"))
  setorder(r, grupo, Circuito_corto)
  r[]
}

# -----------------------------------------------------------------------------
# Tarea 6: Excel
# -----------------------------------------------------------------------------
DEFINICIONES <- data.table(
  Concepto = c("Período", "Circuitos", "Servicio", "Fecha / Turno", "Sábado nocturno", "Contenedor del viaje",
               "Visitado (se fue)", "Levantado", "% completo (viaje)",
               "% completo (circuito-día-turno)", "Circuito completo", "Viajes mixtos",
               "Contenedores según posiciones", "dif_vs_gol", "Promedio levantados por día-turno",
               "Viajes de grúa (excluidos)"),
  Definicion = c(
    "Últimos 12 meses hasta la última fecha disponible en GOL.",
    "B_101, B_102, B_103 (grupo B_10x), todos los CH y C_101 a C_109: 35 circuitos. C_110 a C_116 se excluyen (decisión del usuario, 2026-10-15).",
    "Un Id_viaje_GOL distinto.",
    "Fecha y Turno_levantado tal cual vienen de GOL (el Nocturno NO se pasa al día siguiente).",
    "No hay turno nocturno los sábados: los pocos registros con esa combinación se excluyen de todas las cuentas.",
    "Fila listada en el viaje con contenedor_activo = S (inactivos excluidos).",
    "Levantado = S o N, o tiene Fecha_hora_pasaje. Incluye no levantados con incidencia.",
    "Levantado = S.",
    "Visitados / contenedores listados en ese viaje.",
    "Une todos los viajes del circuito ese día y turno: gids únicos visitados / gids únicos listados. No penaliza circuitos repartidos entre camiones.",
    "% completo del circuito-día-turno >= 95%.",
    "Si un viaje toca circuitos fuera del alcance, solo se cuentan las filas de los circuitos seleccionados. En el TOTAL cada viaje cuenta una vez; en los grupos, un viaje que toca dos grupos cuenta en ambos.",
    "Contenedores del circuito ese día en historico_ubicaciones, sin Mantenimiento ni Sin instalar.",
    "Contenedores listados en GOL - contenedores según posiciones. Muy negativo = el viaje solo traía una parte del circuito (frecuente en C y B_10x); en ese caso pct_completo_sobre_posiciones muestra cobertura del circuito entero.",
    "Media de levantados por viaje entre los viajes de ese día y turno (prom_levantados_por_viaje).",
    "Levantes puntuales con grúa, detectados sin matrícula por la forma del viaje (todos sus circuitos): A) <= 40 contenedores con posiciones dispersas (contenedores / rango de posiciones <= 0,5); B) <= 40 contenedores en >= 3 circuitos con <= 2 por circuito. Se excluyen de todas las hojas y se listan en Viajes_grua_excluidos. pct_motivo_grua_previo es solo validación: % de contenedores cuya visita previa (<= 7 días) tuvo motivo de grúa (en viajes normales ronda 2%)."
  )
)

exportar_excel <- function(ruta, hojas) {
  wb <- openxlsx::createWorkbook()
  est_pct   <- openxlsx::createStyle(numFmt = "0.0%")
  est_dec   <- openxlsx::createStyle(numFmt = "0.0")
  est_fecha <- openxlsx::createStyle(numFmt = "dd/mm/yyyy")
  est_head  <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#DCE6F1",
                                     border = "bottom", wrapText = TRUE)

  for (nom in names(hojas)) {
    df <- hojas[[nom]]
    openxlsx::addWorksheet(wb, nom)
    openxlsx::writeData(wb, nom, df, withFilter = nom != "Definiciones", headerStyle = est_head)
    openxlsx::freezePane(wb, nom, firstRow = TRUE)
    filas <- 2:(nrow(df) + 1)
    for (j in seq_along(df)) {
      col <- names(df)[j]
      est <- if (startsWith(col, "pct_")) est_pct
             else if (startsWith(col, "prom_")) est_dec
             else if (inherits(df[[col]], "Date")) est_fecha
             else if (is.double(df[[col]]) && !startsWith(col, "Id_") &&
                      any(df[[col]] %% 1 != 0, na.rm = TRUE)) est_dec
             else NULL
      if (!is.null(est)) openxlsx::addStyle(wb, nom, est, rows = filas, cols = j, gridExpand = TRUE)
    }
    if (nom == "Definiciones") openxlsx::setColWidths(wb, nom, 1:2, c(32, 120))
    else openxlsx::setColWidths(wb, nom, seq_along(df), 14)
  }
  openxlsx::saveWorkbook(wb, ruta, overwrite = TRUE)
  invisible(ruta)
}
