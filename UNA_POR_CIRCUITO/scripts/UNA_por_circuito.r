# =============================================================================
# UNA POR CIRCUITO - pipeline completo
# -----------------------------------------------------------------------------
# Construye el historico de ubicaciones enriquecido con PERIODO, ultimo
# levante y las columnas de UNA.
#
# Cada paso corre en un PROCESO DE R APARTE (callr::r) para aislar la memoria:
# los datasets son de millones de filas y no entran los cuatro pasos juntos
# en una sola sesion. Cada paso lee/escribe su .rds en UNA_POR_CIRCUITO/rds/;
# los insumos externos quedan en db/.
#
# Pasos (ver cada funciones_*.R para el detalle):
#   1. funciones_periodo.R          -> historico_ubicaciones_con_periodo.rds
#   2. funciones_ultimo_levante.R   -> historico_ubicaciones_con_levante.rds
#   3. funciones_filtrar_cerrados.R -> historico_ubicaciones_depurado.rds
#   4. funciones_una.R              -> historico_ubicaciones_depurado.rds (sobrescribe)
#
# ACTUALIZAR_TODO controla si cada paso reprocesa todo el historico desde
# cero (TRUE) o solo verifica que Fecha esta cargada y procesa/anexa lo que
# falta (FALSE). En FALSE cada paso lee igual su insumo completo (un .rds no
# se puede leer parcialmente) pero el JOIN/CALCULO pesado y el guardado se
# hacen solo sobre las filas nuevas -> mucho mas rapido y liviano de memoria.
# Usar TRUE cuando algun insumo (zona, llenado, cierres de contenedores) se
# corrigio retroactivamente para fechas viejas, porque el modo incremental
# no vuelve a tocar filas ya procesadas.
#
# Este script se llama automaticamente desde nuevoinforme.R en cada corrida
# diaria, por eso el default es FALSE (incremental). Si a algun paso le
# falta el archivo/checkpoint de una corrida anterior, igual procesa todo
# esa vez puntual, sin necesidad de tocar este flag.
# =============================================================================

ACTUALIZAR_TODO <- FALSE

setwd("c:/Users/im4445285/OneDrive/Trabajo IM/APP_nuevoinforme")

raiz  <- getwd()
pasos <- list(
  c("funciones_periodo.R",
    sprintf("actualizar_periodo(actualizar_todo = %s)", ACTUALIZAR_TODO)),
  c("funciones_ultimo_levante.R",
    sprintf("actualizar_ultimo_levante(actualizar_todo = %s)", ACTUALIZAR_TODO)),
  c("funciones_filtrar_cerrados.R",
    sprintf("actualizar_filtrar_cerrados(actualizar_todo = %s)", ACTUALIZAR_TODO)),
  c("funciones_una.R",
    sprintf("actualizar_una(actualizar_todo = %s)", ACTUALIZAR_TODO))
)

for (i in seq_along(pasos)) {
  archivo <- pasos[[i]][1]
  llamada <- pasos[[i]][2]
  cat(sprintf("\n===== Paso %d/%d : %s =====\n", i, length(pasos), llamada))

  callr::r(
    function(archivo, llamada) {
      source(file.path("UNA_POR_CIRCUITO", "scripts", archivo))
      eval(parse(text = llamada))
      invisible(NULL)   # no devolver el frame: callr lo serializaria a disco
    },
    args = list(archivo = archivo, llamada = llamada),
    wd = raiz, show = TRUE
  )
}

cat("\n===== Pipeline completo =====\n")
cat("Salida final: UNA_POR_CIRCUITO/rds/historico_ubicaciones_depurado.rds\n")
