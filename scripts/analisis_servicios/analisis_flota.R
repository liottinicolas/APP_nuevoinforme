# =============================================================================
# Flota y frecuencia: con los camiones disponibles en cada turno (planilla de
# operaciones), ¿cuánta frecuencia extra entra en B_101-103, CH y C_101-109, de
# noche y en turnos diurnos (con la productividad diurna medida, que refleja la
# congestión)?
# Ejecutar desde la raíz del proyecto:
#   Rscript scripts/analisis_servicios/analisis_flota.R
# Salida: salidas/flota_frecuencia_<desde>_<hasta>.xlsx
# =============================================================================

source("scripts/analisis_servicios/analisis_servicios_funciones.R")
source("scripts/analisis_servicios/capacidad_funciones.R")
source("scripts/analisis_servicios/flota_funciones.R")

MESES_ATRAS          <- 12
MESES_DISPONIBILIDAD <- 3             # camiones al inicio: media de los últimos meses (hay menos camiones que antes)
DESCARGAR_PLANILLA   <- TRUE          # baja la hoja Disponibilidad; si falla usa la copia local
RESERVAS             <- c(0, 0.10)    # reserva extra (sensibilidad); la planilla ya excluye los rotos
RESERVA_BASE         <- 0             # tablas del documento
TURNOS_BASE          <- 2             # turnos por camión observados hoy (~58 camiones-turno/día con 21-27 al inicio de cada turno)
PERSONAS_POR_CAMION  <- 2             # chofer + peón
TURNOS_POR_CAMION    <- c(1, 2)       # turnos que puede hacer un camión por día
FRECUENCIAS_OBJETIVO <- c(5, 6)       # servicios por semana por circuito

llenado <- readRDS("db/GOL_reportes/historico_llenadoGol.rds")
hasta <- max(llenado$Fecha, na.rm = TRUE)
desde <- seq(hasta, by = sprintf("-%d months", MESES_ATRAS), length.out = 2)[2] + 1

grua <- marcar_viajes_grua(llenado, desde, hasta)
ids_grua <- grua[es_grua == TRUE, Id_viaje_GOL]

universo <- preparar_universo(llenado, desde, hasta)
universo <- universo[!Id_viaje_GOL %in% ids_grua]

if (DESCARGAR_PLANILLA) descargar_disponibilidad()
planilla <- leer_disponibilidad()
FLOTA    <- disponibilidad_por_turno(planilla, hasta, MESES_DISPONIBILIDAD)
message("Camiones disponibles (media al inicio, ", paste(attr(FLOTA, "periodo"), collapse = " a "), "):")
print(dcast(FLOTA, Turno ~ dia_semana, value.var = "disponibles")[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])

factores   <- productividad_por_turno(universo, llenado)
vb         <- viajes_por_bloque(llenado, desde, hasta, ids_grua)
uso        <- uso_flota_actual(vb, desde, hasta)
frecuencia <- meta_frecuencia(universo, FRECUENCIAS_OBJETIVO)
dia_turno_total <- resumir_dia_turno(universo, resumir_circuitos(universo))[grupo == "TOTAL"]
completar  <- meta_completar_listado(dia_turno_total, desde, hasta)
opciones   <- tabla_opciones_flota(uso, frecuencia, completar, factores, FLOTA, RESERVA_BASE,
                                   TURNOS_BASE, PERSONAS_POR_CAMION)
flota_turno <- resumen_flota_turno(uso, FLOTA, RESERVA_BASE)
escenarios <- tabla_escenarios_flota(uso, frecuencia, factores, FLOTA, RESERVAS,
                                     TURNOS_POR_CAMION, FRECUENCIAS_OBJETIVO)
validacion <- validar_con_planilla(planilla, vb, desde, hasta)
message("Validación planilla vs GOL:"); print(validacion[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 2) else x)])

# Circuitos a subir, con los servicios semanales que les faltan
a_subir <- copy(frecuencia)
for (fo in FRECUENCIAS_OBJETIVO) {
  set(a_subir, j = sprintf("servicios_faltan_f%d", fo), value = pmax(0, fo - a_subir$frecuencia_actual_semanal))
}
a_subir <- a_subir[frecuencia_actual_semanal < max(FRECUENCIAS_OBJETIVO)]
setorder(a_subir, frecuencia_actual_semanal)

# Lugar libre semanal por turno en cada situación (reserva 0, 2 turnos)
libre <- rbind(
  lugar_libre(uso, FLOTA, 0, 2, "actual")[, situacion := "Actual (todos los municipios)"],
  lugar_libre(uso, FLOTA, 0, 2, "escenario")[, situacion := "A/D/E/F/G dejan el sistema"]
)
setcolorder(libre, "situacion")

message("Productividad por turno:"); print(factores)
message("Flota por turno (día hábil típico):")
print(flota_turno[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])
message("Opciones dentro de la flota:")
print(opciones[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])
message("Escenarios:")
print(escenarios[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 2) else x)], nrows = 100)

ruta <- file.path("salidas", sprintf("flota_frecuencia_%s_%s.xlsx", desde, hasta))
exportar_excel(ruta, list(
  Flota_por_turno    = flota_turno,
  Opciones           = opciones,
  Escenarios         = escenarios,
  Productividad      = factores,
  Disponibles        = FLOTA,
  Validacion_planilla = validacion,
  Uso_flota_actual   = uso,
  Lugar_libre        = libre,
  Circuitos_a_subir  = a_subir,
  Definiciones       = DEFINICIONES_FLOTA
))
message("Excel generado: ", ruta)
