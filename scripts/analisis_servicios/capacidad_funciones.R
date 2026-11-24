# =============================================================================
# Capacidad: camiones-turno (servicios) por día y turno.
#   Demanda = B_101-103, CH y C_101-109 (C_110-116: bloque C_excluido).  Oferta liberable = A, D, E, F, G (Oficina IM).
#   1 viaje GOL = 1 camión-turno (confirmado por el usuario).
# Requiere analisis_servicios_funciones.R (CIRCUITOS_B, MOTIVOS_GRUA, etc.)
# =============================================================================

MUNICIPIOS_OFERTA <- c("A", "D", "E", "F", "G")
TURNOS <- c("Matutino", "Vespertino", "Nocturno")
DIAS_SEMANA <- c("Lun", "Mar", "Mie", "Jue", "Vie", "Sab", "Dom")

dia_semana <- function(fecha) factor(format(fecha, "%u"), 1:7, DIAS_SEMANA)

DEFINICIONES_CAPACIDAD <- data.table(
  Concepto = c("Escenario", "Camión-turno (servicio)", "Demanda", "Oferta liberable", "Exclusiones",
               "Viajes mixtos", "Media / p90", "extra_completar", "Sábado nocturno",
               "Meta frecuencia (f5/f6)", "camiones_por_servicio", "Personas",
               "Limitaciones"),
  Definicion = c(
    "Los municipios A, D, E, F y G dejan este sistema de recolección y su personal/camiones pasan a cubrir o aumentar B_101-103, CH y C_101-109.",
    "1 viaje GOL = 1 camión en un turno (confirmado). Todas las cantidades de camiones son camiones-turno, no camiones físicos distintos: un mismo camión puede hacer Matutino y Vespertino.",
    "Viajes de B_101, B_102, B_103, CH y C_101 a C_109 (Oficina IM). C_110 a C_116 quedan fuera de la demanda (bloque C_excluido), pero sus camiones cuentan en el uso de la flota.",
    "Viajes de A, D, E, F y G (Oficina IM). El Fideicomiso del municipio B no entra.",
    "Contenedores inactivos y viajes de grúa (levantes puntuales) de todo el sistema. Período: últimos 12 meses.",
    "Un viaje que toca demanda y oferta se cuenta en el bloque donde tiene más contenedores (2,4 % de los viajes).",
    "Media = promedio de los días de ese día de semana (incluye días con 0). p90 = valor que cubre 9 de cada 10 días; usar p90 para dotación.",
    "Camiones adicionales para visitar el 100 % de lo listado: contenedores no visitados / visitados por camión promedio del turno.",
    "No hay turno nocturno los sábados: los pocos registros con esa combinación se excluyen y el sábado-nocturno no se cuenta en ninguna cuenta. Por eso de noche hay 6 turnos por semana.",
    "Camiones-turno extra por semana para que cada circuito tenga N días de servicio por semana (5 o 6; 6 es el máximo nocturno sin sábado). Se asignan al Nocturno, que es el turno de estos circuitos.",
    "Camiones-equivalentes que usa un día de servicio del circuito: cada viaje se reparte entre sus circuitos en proporción a sus contenedores.",
    "Normalmente chofer + peón: personas ≈ 2 × camiones-turno (parámetro PERSONAS_POR_CAMION).",
    "Sin matrícula: no se sabe cuántos camiones físicos hay ni si el personal diurno puede pasar a nocturno. La productividad se toma del promedio actual."
  )
)

# -----------------------------------------------------------------------------
# Un registro por viaje con su bloque (Demanda / Oferta / C_excluido / Otro).
# C_excluido = C_110 a C_116: fuera de la demanda, pero usan flota IM.
# Un viaje que mezcla bloques se asigna al bloque con más contenedores.
# -----------------------------------------------------------------------------
viajes_por_bloque <- function(llenado, desde, hasta, viajes_excluir = numeric()) {
  d <- as.data.table(llenado)[Fecha >= desde & Fecha <= hasta & contenedor_activo == "S" &
                                !Id_viaje_GOL %in% viajes_excluir &
                                !es_sabado_noche(Fecha, as.character(Turno_levantado))]
  d[, bloque := fcase(Circuito_corto %in% CIRCUITOS_C_EXCLUIDOS, "C_excluido",
                      Circuito_corto %in% CIRCUITOS_B | Municipio %in% c("CH", "C"), "Demanda",
                      Municipio %in% MUNICIPIOS_OFERTA & Oficina == "IM", "Oferta",
                      default = "Otro")]
  d[, visitado := Levantado %in% c("S", "N") | !is.na(Fecha_hora_pasaje)]

  v <- d[, .(contenedores = .N, visitados = sum(visitado), levantados = sum(Levantado %in% "S")),
         by = .(Id_viaje_GOL, Fecha, Turno = as.character(Turno_levantado), bloque)]
  setorder(v, Id_viaje_GOL, -contenedores)
  bloque_ppal <- v[!duplicated(Id_viaje_GOL), .(Id_viaje_GOL, bloque)]
  v <- v[, .(contenedores = sum(contenedores), visitados = sum(visitados), levantados = sum(levantados),
             bloques_mezclados = .N > 1), by = .(Id_viaje_GOL, Fecha, Turno)]
  v <- bloque_ppal[v, on = "Id_viaje_GOL"]
  v[, dia_semana := dia_semana(Fecha)][]
}

# -----------------------------------------------------------------------------
# Serie diaria: camiones por Fecha x Turno x bloque, con ceros en días sin viajes.
# -----------------------------------------------------------------------------
camiones_dia_turno <- function(vb, desde, hasta) {
  g <- grid_dia_turno(desde, hasta)
  grid <- rbind(copy(g)[, bloque := "Demanda"], copy(g)[, bloque := "Oferta"])
  x <- vb[bloque %in% c("Demanda", "Oferta"),
          .(camiones = .N, contenedores = sum(contenedores), visitados = sum(visitados),
            levantados = sum(levantados)), by = .(Fecha, Turno, bloque)]
  x <- x[grid, on = .(Fecha, Turno, bloque)]
  for (col in c("camiones", "contenedores", "visitados", "levantados")) set(x, which(is.na(x[[col]])), col, 0L)
  x[, dia_semana := dia_semana(Fecha)]
  x[, Turno := factor(Turno, TURNOS)]
  setcolorder(x, c("Fecha", "dia_semana", "Turno", "bloque"))
  setorder(x, Fecha, Turno, bloque)
  x[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Perfil semanal: estadísticos de camiones por bloque x turno x día de semana.
# p90 = dotación que cubre 9 de cada 10 días (dimensionar con la media se queda corto).
# -----------------------------------------------------------------------------
perfil_semanal <- function(serie) {
  p <- serie[, .(
    dias               = .N,
    camiones_media     = mean(camiones),
    camiones_mediana   = as.numeric(median(camiones)),
    camiones_p90       = as.numeric(quantile(camiones, 0.9, names = FALSE)),
    camiones_max       = as.numeric(max(camiones)),
    prom_levantados    = mean(levantados),
    prom_lev_por_camion = fifelse(sum(camiones) > 0, sum(levantados) / sum(camiones), NA_real_)
  ), by = .(bloque, Turno, dia_semana)]
  p[, Turno := factor(Turno, TURNOS)]
  setorder(p, bloque, Turno, dia_semana)
  p[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Meta 1: completar el 100 % de lo listado en los viajes de B_101-103, CH y C_101-109.
# Camiones extra = contenedores no visitados / productividad (visitados por camión
# en ese turno, promedio del período).
# -----------------------------------------------------------------------------
meta_completar_listado <- function(dia_turno_total, desde, hasta) {
  prod <- dia_turno_total[, .(productividad = sum(visitados) / sum(servicios)), by = Turno]
  grid <- grid_dia_turno(desde, hasta)
  x <- dia_turno_total[, .(Fecha, Turno, no_visitados = total_contenedores - visitados)][grid, on = .(Fecha, Turno)]
  x[is.na(no_visitados), no_visitados := 0L]
  x <- prod[x, on = "Turno"]
  x[, camiones_extra := no_visitados / productividad]
  x[, dia_semana := dia_semana(Fecha)]
  r <- x[, .(
    contenedores_no_visitados_media = mean(no_visitados),
    productividad_visitados_por_camion = productividad[1],
    camiones_extra_media = mean(camiones_extra),
    camiones_extra_p90   = as.numeric(quantile(camiones_extra, 0.9, names = FALSE))
  ), by = .(Turno, dia_semana)]
  r[, Turno := factor(Turno, TURNOS)]
  setorder(r, Turno, dia_semana)
  r[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Meta 2: más frecuencia. Por circuito:
#   frecuencia_actual   = días con servicio / semanas del período
#   camiones_por_servicio = camiones-equivalentes que usa un día de servicio del
#     circuito (cada viaje se reparte entre sus circuitos según sus contenedores)
#   extra semanal       = max(0, frecuencia_objetivo - actual) * camiones_por_servicio
# -----------------------------------------------------------------------------
meta_frecuencia <- function(universo, frecuencias_objetivo = c(5, 6)) {
  semanas <- as.numeric(max(universo$Fecha) - min(universo$Fecha) + 1) / 7
  reparto <- universo[, .(filas = .N), by = .(Id_viaje_GOL, Fecha, Circuito_corto, grupo)]
  reparto[, cam_eq := filas / sum(filas), by = Id_viaje_GOL]

  f <- reparto[, .(
    dias_con_servicio      = uniqueN(Fecha),
    camiones_eq_total      = sum(cam_eq)
  ), by = .(grupo, Circuito_corto)]
  f[, frecuencia_actual_semanal := dias_con_servicio / semanas]
  f[, camiones_por_servicio := camiones_eq_total / dias_con_servicio]
  for (fo in frecuencias_objetivo) {
    set(f, j = sprintf("camiones_extra_semana_f%d", fo),
        value = pmax(0, fo - f$frecuencia_actual_semanal) * f$camiones_por_servicio)
  }
  f[, camiones_eq_total := NULL]
  setorder(f, grupo, Circuito_corto)
  f[]
}

# -----------------------------------------------------------------------------
# Balance por turno x día de semana: oferta liberable vs demanda actual + metas.
# Sin fila sábado-nocturno (no hay turno).
# -----------------------------------------------------------------------------
balance_capacidad <- function(perfil, completar, frecuencia) {
  oferta  <- perfil[bloque == "Oferta",  .(Turno, dia_semana, oferta_liberable = camiones_media,
                                           oferta_liberable_p90 = camiones_p90)]
  demanda <- perfil[bloque == "Demanda", .(Turno, dia_semana, demanda_actual = camiones_media,
                                           demanda_actual_p90 = camiones_p90)]
  b <- demanda[oferta, on = .(Turno, dia_semana)]
  b <- completar[, .(Turno, dia_semana, extra_completar = camiones_extra_media)][b, on = .(Turno, dia_semana)]

  b[, demanda_total_meta := demanda_actual + extra_completar]
  b[, saldo_oferta_menos_extra := oferta_liberable - extra_completar]
  b[, Turno := factor(Turno, TURNOS)]
  setorder(b, Turno, dia_semana)
  b[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Opciones para la decisión: camiones-turno extra por semana de cada meta y si
# entran en la oferta nocturna liberable. Tabla "Opciones" del documento.
# La frecuencia máxima nocturna es 6 por semana (no hay turno el sábado).
# -----------------------------------------------------------------------------
tabla_opciones <- function(balance, frecuencia, personas_por_camion = 2) {
  noct <- balance[Turno == "Nocturno"]
  oferta_noct <- sum(noct$oferta_liberable)
  comp <- c(total = sum(balance$extra_completar), noct = sum(noct$extra_completar))
  frec <- function(fo) sum(frecuencia[[sprintf("camiones_extra_semana_f%d", fo)]])  # todo nocturno

  o <- data.table(
    opcion = c("1. Mantener el nivel actual", "2. Completar lo asignado",
               "3a. Frecuencia 5 por semana", "3b. Frecuencia 6 por semana",
               "2 + 3a", "2 + 3b"),
    extra_total    = c(0, comp[["total"]], frec(5), frec(6),
                       comp[["total"]] + frec(5), comp[["total"]] + frec(6)),
    extra_nocturno = c(0, comp[["noct"]], frec(5), frec(6),
                       comp[["noct"]] + frec(5), comp[["noct"]] + frec(6))
  )
  o[, personas_extra := extra_total * personas_por_camion]
  o[, oferta_nocturna_liberable := oferta_noct]
  o[, saldo_nocturno := oferta_noct - extra_nocturno]
  o[, alcanza_con_oferta_nocturna := fifelse(saldo_nocturno >= 0, "Sí", "No")][]
}
