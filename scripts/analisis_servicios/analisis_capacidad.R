# =============================================================================
# Capacidad de servicios por día y turno: demanda B_101-103/CH/C vs oferta
# liberable de A/D/E/F/G (escenario: esos municipios dejan este sistema).
# Ejecutar desde la raíz del proyecto:
#   Rscript scripts/analisis_servicios/analisis_capacidad.R
# Salida: salidas/capacidad_servicios_<desde>_<hasta>.xlsx
# Documentación: scripts/analisis_servicios/documentacion_analisis.md
# =============================================================================

source("scripts/analisis_servicios/analisis_servicios_funciones.R")
source("scripts/analisis_servicios/capacidad_funciones.R")

MESES_ATRAS           <- 12
FRECUENCIAS_OBJETIVO  <- c(5, 6)      # servicios por semana por circuito (máx. 6: no hay turno nocturno el sábado)
PERSONAS_POR_CAMION   <- 2            # chofer + peón (solo informativo)

llenado <- readRDS("db/GOL_reportes/historico_llenadoGol.rds")
hasta <- max(llenado$Fecha, na.rm = TRUE)
desde <- seq(hasta, by = sprintf("-%d months", MESES_ATRAS), length.out = 2)[2] + 1

# Viajes de grúa (todos los municipios) quedan fuera de oferta y demanda
grua <- marcar_viajes_grua(llenado, desde, hasta)
ids_grua <- grua[es_grua == TRUE, Id_viaje_GOL]
message(sprintf("Viajes de grúa excluidos (todo el sistema): %d", length(ids_grua)))

# Oferta y demanda en camiones-turno
vb     <- viajes_por_bloque(llenado, desde, hasta, ids_grua)
serie  <- camiones_dia_turno(vb, desde, hasta)
perfil <- perfil_semanal(serie)

# Metas sobre la demanda (universo B_101-103, CH y C_101-109, mismas definiciones que el análisis de servicios)
universo <- preparar_universo(llenado, desde, hasta)
universo <- universo[!Id_viaje_GOL %in% ids_grua]
dia_turno_total <- resumir_dia_turno(universo, resumir_circuitos(universo))[grupo == "TOTAL"]
completar  <- meta_completar_listado(dia_turno_total, desde, hasta)
frecuencia <- meta_frecuencia(universo, FRECUENCIAS_OBJETIVO)
balance    <- balance_capacidad(perfil, completar, frecuencia)

# Resumen semanal (camiones-turno por semana)
sem <- balance[, .(
  oferta_liberable  = sum(oferta_liberable),
  demanda_actual    = sum(demanda_actual),
  extra_completar   = sum(extra_completar)
), by = Turno]
sem <- rbind(sem, sem[, c(.(Turno = "TOTAL"), lapply(.SD, sum)), .SDcols = -"Turno"])
for (fo in FRECUENCIAS_OBJETIVO) {
  col <- sprintf("camiones_extra_semana_f%d", fo)
  sem[, (sprintf("extra_frecuencia_%d_por_semana", fo)) := fifelse(Turno %in% c("Nocturno", "TOTAL"), sum(frecuencia[[col]]), 0)]
}
sem[, personas_oferta_liberable := oferta_liberable * PERSONAS_POR_CAMION]
opciones <- tabla_opciones(balance, frecuencia, PERSONAS_POR_CAMION)
message("\nResumen semanal (camiones-turno por semana):")
print(sem[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])
message("Opciones:")
print(opciones[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])

ruta <- file.path("salidas", sprintf("capacidad_servicios_%s_%s.xlsx", desde, hasta))
exportar_excel(ruta, list(
  Resumen_semanal     = sem,
  Opciones            = opciones,
  Balance_dia_turno   = balance,
  Perfil_semanal      = perfil,
  Meta_completar      = completar,
  Meta_frecuencia     = frecuencia,
  Serie_diaria        = serie,
  Definiciones        = DEFINICIONES_CAPACIDAD
))
message("Excel generado: ", ruta)
