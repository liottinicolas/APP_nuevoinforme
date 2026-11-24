# =============================================================================
# Verificación del análisis de servicios con casos reales conocidos.
# Ejecutar desde la raíz del proyecto:
#   Rscript scripts/analisis_servicios/verificar_analisis.R
# =============================================================================

source("scripts/analisis_servicios/analisis_servicios_funciones.R")

llenado <- readRDS("db/GOL_reportes/historico_llenadoGol.rds")
u <- preparar_universo(llenado)  # sin límite de fechas: los casos son de 2025

# --- Tarea 1: universo -------------------------------------------------------
esperados <- c(CIRCUITOS_B, sprintf("CH_%d", 101:123), sprintf("C_%d", 101:109))
stopifnot(setequal(unique(u$Circuito_corto), esperados))
stopifnot(all(u$grupo %in% c("B_10x", "CH", "C")))
stopifnot(u[Circuito_corto %in% CIRCUITOS_B, all(grupo == "B_10x")])

# filas activas de B_101 = conteo independiente sobre el crudo
crudo_b101 <- sum(llenado$Circuito_corto == "B_101" & llenado$contenedor_activo %in% "S" &
                  !es_sabado_noche(llenado$Fecha, as.character(llenado$Turno_levantado)))
stopifnot(u[Circuito_corto == "B_101", .N] == crudo_b101)

# un viaje = una fecha y un turno
stopifnot(u[, .(nf = uniqueN(Fecha), nt = uniqueN(Turno)), by = Id_viaje_GOL][, all(nf == 1 & nt == 1)])
message("OK Tarea 1")

# --- Tarea 2: por viaje --------------------------------------------------------
v <- resumir_viajes(u)
stopifnot(!anyDuplicated(v$Id_viaje_GOL))
stopifnot(sum(v$total_contenedores) == nrow(u))
stopifnot(sum(v$levantados) == sum(u$levantado))

v1 <- v[Id_viaje_GOL == 44882]
v2 <- v[Id_viaje_GOL == 44914]
print(v[Id_viaje_GOL %in% c(44882, 44914)])
# 44882 lista CH_115 pos 1-50 (28 visitados) + CH_114 entero (41, sin visitar)
stopifnot(v1$n_circuitos == 2, v1$circuitos_sin_visita == 1)
stopifnot(v1$total_contenedores == 91, v1$visitados == 28, abs(v1$pct_completo - 28 / 91) < 1e-9)
stopifnot(u[Id_viaje_GOL == 44882 & Circuito_corto == "CH_115", .N] == 50)
stopifnot(v2$total_contenedores == 22, v2$visitados == 22, v2$pct_completo == 1)
message("OK Tarea 2")

# --- Tarea 3: por circuito-día-turno ------------------------------------------
c <- resumir_circuitos(u)
caso <- c[Circuito_corto == "CH_115" & grepl("44882", viajes) & grepl("44914", viajes)]
print(caso)
stopifnot(nrow(caso) == 1, caso$n_viajes == 2, caso$total_contenedores == 50,
          caso$visitados == 50, caso$pct_completo == 1)
stopifnot(all(c$pct_completo >= 0 & c$pct_completo <= 1))
# un gid nunca cuenta más de una vez por circuito-día-turno
stopifnot(sum(c$total_contenedores) == nrow(unique(u[, .(Fecha, Turno, Circuito_corto, gid)])))
message("OK Tarea 3")

# --- Tarea 4: resumen día-turno ----------------------------------------------
dt <- resumir_dia_turno(u, c)
tot <- dt[grupo == "TOTAL"]
stopifnot(sum(tot$servicios) == nrow(v))
stopifnot(sum(tot$levantados) == sum(v$levantados))
stopifnot(sum(tot$total_contenedores) == sum(v$total_contenedores))
# por grupo: los contenedores suman igual; los servicios pueden repetirse (viajes entre grupos)
stopifnot(sum(dt[grupo != "TOTAL", total_contenedores]) == sum(tot$total_contenedores))
stopifnot(sum(dt[grupo != "TOTAL", servicios]) >= sum(tot$servicios))
caso4 <- dt[Fecha == as.Date("2026-02-10") & Turno == "Nocturno" & grupo == "TOTAL"]
stopifnot(caso4$servicios == v[Fecha == as.Date("2026-02-10") & Turno == "Nocturno", .N])
message("OK Tarea 4")

# --- Tarea 5: cruce con posiciones -------------------------------------------
ub <- readRDS("db/10393_ubicaciones/historico_ubicaciones.rds")
c_oct <- c[Fecha >= as.Date("2026-10-01")]
cp <- cruzar_posiciones(c_oct, ub)
b101 <- cp[Circuito_corto == "B_101" & Fecha == as.Date("2026-10-13")]
print(b101[, .(Turno, total_contenedores, contenedores_segun_posiciones, dif_vs_gol)])
# 111 posiciones ese día, 2 en Mantenimiento
stopifnot(nrow(b101) >= 1, all(b101$contenedores_segun_posiciones == 109))
stopifnot(nrow(cp) == nrow(c_oct))
message("OK Tarea 5")

# --- Viajes de grúa ----------------------------------------------------------
g <- marcar_viajes_grua(llenado, as.Date("2025-10-14"), as.Date("2026-10-13"))
print(g[Id_viaje_GOL %in% c(31637, 58569, 44882, 44914)])
stopifnot(!anyDuplicated(g$Id_viaje_GOL))
stopifnot(g[Id_viaje_GOL == 31637, es_grua & startsWith(regla_grua, "A")])  # 18 cont. en 13 circuitos, dispersos
stopifnot(g[Id_viaje_GOL == 58569, es_grua & startsWith(regla_grua, "B")])  # 10 cont. en 9 circuitos
stopifnot(g[Id_viaje_GOL %in% c(44882, 44914), !any(es_grua)])             # viajes normales
# validación: los marcados tienen mucho más motivo de grúa previo que el resto
val <- g[, .(prev = mean(pct_motivo_grua_previo)), by = es_grua]
print(val)
stopifnot(val[es_grua == TRUE, prev] > 10 * val[es_grua == FALSE, prev])
message("OK Grúa")


# --- Capacidad -----------------------------------------------------------------
source("scripts/analisis_servicios/capacidad_funciones.R")
desde <- as.Date("2025-10-14"); hasta <- as.Date("2026-10-13")
ids_g <- g[es_grua == TRUE, Id_viaje_GOL]
vb <- viajes_por_bloque(llenado, desde, hasta, ids_g)
serie <- camiones_dia_turno(vb, desde, hasta)
perfil <- perfil_semanal(serie)
stopifnot(!anyDuplicated(vb$Id_viaje_GOL))
# serie completa: días x 3 turnos x 2 bloques, sin sábado-nocturno
n_dias <- as.numeric(hasta - desde + 1); n_sab <- sum(format(seq(desde, hasta, by = "day"), "%u") == "6")
stopifnot(nrow(serie) == (n_dias * 3 - n_sab) * 2)
stopifnot(serie[es_sabado_noche(Fecha, Turno), .N] == 0, vb[es_sabado_noche(Fecha, Turno), .N] == 0)
# camiones de la serie = viajes crudos de cada bloque
stopifnot(serie[bloque == "Demanda", sum(camiones)] == vb[bloque == "Demanda", .N])
stopifnot(serie[bloque == "Oferta", sum(camiones)] == vb[bloque == "Oferta", .N])
# suma de medias por día de semana = viajes por semana (cada día de semana aparece ~52 veces)
sem_perfil <- perfil[bloque == "Demanda", sum(camiones_media)]
sem_crudo  <- vb[bloque == "Demanda", .N] / (as.numeric(hasta - desde + 1) / 7)
message(sprintf("Demanda semanal: perfil %.1f vs crudo %.1f", sem_perfil, sem_crudo))
stopifnot(abs(sem_perfil - sem_crudo) / sem_crudo < 0.01)
# sábado nocturno ~0 en todo el sistema (también en datos crudos sin filtros)
sab <- as.data.table(llenado)[Fecha >= desde & format(Fecha, "%u") == "6" & Turno_levantado == "Nocturno", uniqueN(Id_viaje_GOL)]
message(sprintf("Viajes nocturnos en sábado excluidos (crudo, todo el sistema, 12 meses): %d", sab))
# meta frecuencia: con objetivo 0 no hay extra; con objetivo 7 nunca negativo
uni <- preparar_universo(llenado, desde, hasta, verbose = FALSE)[!Id_viaje_GOL %in% ids_g]
stopifnot(uni[es_sabado_noche(Fecha, Turno), .N] == 0)
fr <- meta_frecuencia(uni, c(0, 6))
stopifnot(all(fr$camiones_extra_semana_f0 == 0), all(fr$camiones_extra_semana_f6 >= 0))
stopifnot(all(fr$frecuencia_actual_semanal <= 7))
# camiones-equivalentes repartidos = viajes del universo
stopifnot(abs(sum(fr$camiones_por_servicio * fr$dias_con_servicio) - uniqueN(uni$Id_viaje_GOL)) < 1e-6)
message("OK Capacidad")

# --- Tablas del documento ------------------------------------------------------
cal <- resumir_calidad(dt, cruzar_posiciones(c, ub, verbose = FALSE))
tot_n <- cal[grupo == "TOTAL" & Turno == "Nocturno"]
stopifnot(abs(tot_n$prom_camiones_por_turno * tot_n$turnos_con_servicio - v[Turno == "Nocturno", .N]) < 1e-6)
stopifnot(abs(tot_n$pct_visitados - v[Turno == "Nocturno", sum(visitados) / sum(total_contenedores)]) < 1e-9)
stopifnot(all(cal$pct_circuitos_completos >= 0 & cal$pct_circuitos_completos <= 1))
bal <- balance_capacidad(perfil, meta_completar_listado(dt[grupo == "TOTAL"], min(dt$Fecha), max(dt$Fecha)), fr)
op <- tabla_opciones(bal, meta_frecuencia(uni, c(5, 6, 7)))
stopifnot(nrow(op) == 6, op[opcion == "1. Mantener el nivel actual", extra_total == 0])
stopifnot(!any(grepl("(?i)s[aá]bado", op$opcion, perl = TRUE)))
stopifnot(abs(op[opcion == "2 + 3b", extra_total] - sum(op[opcion %in% c("2. Completar lo asignado", "3b. Frecuencia 6 por semana"), extra_total])) < 1e-9)
stopifnot(all((op$saldo_nocturno >= 0) == (op$alcanza_con_oferta_nocturna == "Sí")))
message("OK Tablas del documento")

# --- Flota y frecuencia ----------------------------------------------------------
source("scripts/analisis_servicios/flota_funciones.R")
uso <- uso_flota_actual(vb, desde, hasta)
fac <- productividad_por_turno(uni, llenado)
fr6 <- meta_frecuencia(uni, c(5, 6))
# camiones disponibles = media de camiones al inicio por turno (planilla de operaciones)
planilla <- leer_disponibilidad()
FLOTA <- disponibilidad_por_turno(planilla, hasta, 3)
stopifnot(nrow(FLOTA) == 21, FLOTA[Turno == "Nocturno" & dia_semana == "Sab", disponibles == 0],
          FLOTA[Turno == "Nocturno" & dia_semana != "Sab", all(disponibles > 15 & disponibles < 40)])
# la planilla valida a GOL: camiones usados ≈ camiones-turno de GOL, día por día
val <- validar_con_planilla(planilla, vb, desde, hasta)
stopifnot(all(abs(val$diferencia_media) < 1.5), val[tipo_dia == "Día hábil", all(correlacion_diaria > 0.4)])
x_val <- vb[bloque != "Otro", .(gol = .N), by = .(Fecha, Turno)][planilla[Fecha >= desde & Fecha <= hasta & usados > 0], on = .(Fecha, Turno)]
stopifnot(cor(x_val$usados, fcoalesce(x_val$gol, 0L)) > 0.9)
# un número fijo y la planilla dan la misma estructura de lugar libre
stopifnot(identical(names(lugar_libre(uso, 27, 0.1, 2, "actual")), names(lugar_libre(uso, FLOTA, 0, 2, "actual"))))
# el uso IM nocturno histórico nunca superó 30 (la flota anterior; hoy hay menos camiones)
stopifnot(all(uso[Turno == "Nocturno", IM_max] <= 30))
# quedan = analizados (B_101-103, CH, C_101-109) + C_110-C_116; los analizados no incluyen C_110-C_116
stopifnot(all(abs(uso$quedan_media - uso$analizados_media - uso$C110_116_media) < 1e-9),
          abs(sum(uso$analizados_media) - vb[bloque == "Demanda", .N] / (as.numeric(hasta - desde + 1) / 7)) < 0.5)
# de día rinden menos que de noche (congestión)
stopifnot(all(fac[Turno != "Nocturno", factor_visitados] < 1))
for (sit in c("actual", "escenario")) for (tpc in 1:2) {
  lb <- lugar_libre(uso, FLOTA, 0, tpc, sit)
  stopifnot(all(lb$libre >= 0), lb[Turno == "Nocturno" & dia_semana == "Sab", .N] == 0)
  e <- escenario_frecuencia(fr6, lb, fac, 6)
  fm <- fac[Turno == "Matutino", factor_visitados]; fv <- fac[Turno == "Vespertino", factor_visitados]
  # conservación: lo asignado (en equivalentes nocturnos) + lo no cubierto = necesidad
  stopifnot(abs(e$camiones_nocturno + e$camiones_matutino * fm + e$camiones_vespertino * fv +
                e$sin_cubrir_eq_nocturno - e$necesidad_eq_nocturno) < 1e-9)
  stopifnot(e$camiones_matutino <= lb[Turno == "Matutino", sum(libre)] + 1e-9)
}
# flota enorme: todo entra de noche; flota 0: nada entra
e_big <- escenario_frecuencia(fr6, lugar_libre(uso, 1000, 0, 2, "actual"), fac, 6)
stopifnot(e_big$pct_cubierto == 1, e_big$camiones_matutino == 0)
e_0 <- escenario_frecuencia(fr6, lugar_libre(uso, 0, 0, 2, "actual"), fac, 6)
stopifnot(e_0$pct_cubierto == 0)
message("OK Flota")

# --- Opciones dentro de la flota --------------------------------------------------
dtt <- resumir_dia_turno(uni, resumir_circuitos(uni))[grupo == "TOTAL"]
comp <- meta_completar_listado(dtt, desde, hasta)
opf <- tabla_opciones_flota(uso, fr6, comp, fac, FLOTA, 0, 2)
stopifnot(nrow(opf) == 12, all(opf$pct_cubierto >= 0 & opf$pct_cubierto <= 1 + 1e-9))
stopifnot(opf[opcion == "1. Mantener el nivel actual", all(camiones_total == 0)])
# sin A/D/E/F/G hay al menos tanto lugar libre como hoy en cada turno
lh <- lugar_libre(uso, FLOTA, 0, 2, "actual"); le <- lugar_libre(uso, FLOTA, 0, 2, "escenario")
stopifnot(all(le$libre >= lh$libre))
# conservación con partes diurnas fijas
a <- asignar_en_flota(10, lh, fac, 3, 2)
fm <- fac[Turno == "Matutino", factor_visitados]; fv <- fac[Turno == "Vespertino", factor_visitados]
stopifnot(abs(a$camiones_nocturno + a$camiones_matutino * fm + a$camiones_vespertino * fv +
              a$sin_cubrir_eq_nocturno - a$necesidad_eq_nocturno) < 1e-9)
# ningún turno usa más camiones que el lugar libre semanal
for (sit in unique(opf$situacion)) {
  lb <- if (startsWith(sit, "Hoy")) lh else le
  x <- opf[situacion == sit]
  stopifnot(all(x$camiones_nocturno <= lb[Turno == "Nocturno", sum(libre)] + 1e-9),
            all(x$camiones_matutino <= lb[Turno == "Matutino", sum(libre)] + 1e-9),
            all(x$camiones_vespertino <= lb[Turno == "Vespertino", sum(libre)] + 1e-9))
}
rf <- resumen_flota_turno(uso, FLOTA, 0)
stopifnot(all(rf$libre_hoy >= 0), all(rf$libre_sin_AG >= rf$libre_hoy))
message("OK Opciones en flota")
message("Verificación completa: todos los asserts pasaron")
