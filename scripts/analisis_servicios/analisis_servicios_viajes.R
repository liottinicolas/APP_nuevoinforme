# =============================================================================
# Análisis de servicios (viajes GOL) por día y turno — B_101/102/103, CH y C_101-109
# Ejecutar desde la raíz del proyecto:
#   Rscript scripts/analisis_servicios/analisis_servicios_viajes.R
# Salida: salidas/analisis_servicios_viajes_<desde>_<hasta>.xlsx
# Plan y definiciones: tasks/plan.md
# =============================================================================

source("scripts/analisis_servicios/analisis_servicios_funciones.R")

MESES_ATRAS  <- 12
EXCLUIR_GRUA <- TRUE   # excluir levantes puntuales con grúa (ver marcar_viajes_grua)

llenado     <- readRDS("db/GOL_reportes/historico_llenadoGol.rds")
ubicaciones <- readRDS("db/10393_ubicaciones/historico_ubicaciones.rds")

hasta <- max(llenado$Fecha, na.rm = TRUE)
desde <- seq(hasta, by = sprintf("-%d months", MESES_ATRAS), length.out = 2)[2] + 1

universo   <- preparar_universo(llenado, desde, hasta)

grua <- marcar_viajes_grua(llenado, desde, hasta)
grua_sel <- grua[es_grua == TRUE & Id_viaje_GOL %in% universo$Id_viaje_GOL]
info_sel <- universo[Id_viaje_GOL %in% grua_sel$Id_viaje_GOL, .(
  Fecha = Fecha[1], Turno = Turno[1],
  circuitos_seleccionados = paste(sort(unique(Circuito_corto)), collapse = ", ")
), by = Id_viaje_GOL]
grua_sel <- info_sel[grua_sel, on = "Id_viaje_GOL"]
setorder(grua_sel, Fecha, Turno, Id_viaje_GOL)
message(sprintf("Viajes de grúa probables en el universo: %d (%s filas)",
                nrow(grua_sel), universo[Id_viaje_GOL %in% grua_sel$Id_viaje_GOL, .N]))
if (EXCLUIR_GRUA) universo <- universo[!Id_viaje_GOL %in% grua_sel$Id_viaje_GOL]

viajes    <- resumir_viajes(universo)
circuitos  <- resumir_circuitos(universo)
dia_turno  <- resumir_dia_turno(universo, circuitos)
circuitos  <- cruzar_posiciones(circuitos, ubicaciones)
x_circuito <- resumir_por_circuito(universo, circuitos)
calidad    <- resumir_calidad(dia_turno, circuitos)
val_grua   <- resumir_validacion_grua(grua, unique(c(universo$Id_viaje_GOL, grua_sel$Id_viaje_GOL)))

message(sprintf("Universo final: %s registros, %s viajes",
                format(nrow(universo), big.mark = ".", decimal.mark = ","),
                format(uniqueN(universo$Id_viaje_GOL), big.mark = ".", decimal.mark = ",")))
message("Calidad del servicio:")
print(calidad[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 3) else x)])
message("Validación grúa:")
print(val_grua)

ruta <- file.path("salidas", sprintf("analisis_servicios_viajes_%s_%s.xlsx", desde, hasta))
exportar_excel(ruta, list(
  Calidad_servicio     = calidad,
  Resumen_dia_turno    = dia_turno,
  Viajes               = viajes,
  Circuito_dia_turno   = circuitos,
  Resumen_por_circuito = x_circuito,
  Viajes_grua_excluidos = grua_sel,
  Validacion_grua      = val_grua,
  Definiciones        = DEFINICIONES
))
message("Excel generado: ", ruta)
