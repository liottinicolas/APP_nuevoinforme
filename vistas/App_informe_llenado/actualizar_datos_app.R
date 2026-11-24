# ==============================================================================
# actualizar_datos_app.R
# Versión mínima de nuevoinforme.R: corre SOLO los pasos que necesita la app
# "Informe de llenado" (vistas/App_informe_llenado/) para tener datos nuevos.
#
# Cómo usarlo (ver INSTRUCTIVO.md en esta misma carpeta):
#   1. Abrir APP_nuevoinforme.Rproj en RStudio (así la carpeta de trabajo es
#      la raíz del proyecto).
#   2. Correr:  source("vistas/App_informe_llenado/actualizar_datos_app.R")
#   3. Cuando lo pida, escribir el usuario y la contraseña de la IMM.
#
# Qué hace:
#   Paso 1. Descarga de la intranet los reportes de levantes (GOL) que faltan,
#           hasta el día de ayer.
#   Paso 2. Suma esos reportes al histórico db/GOL_reportes/historico_llenadoGol.rds.
#   Paso 3. Descarga del GeoServer de la IMM las capas del DFR (contenedores
#           activos e inactivos) y las guarda en db/DFR/RDS/.
#   Paso 4. Publica los datos en GitHub (repo APP_nuevoinforme-data). La app
#           publicada los toma sola en 10 minutos como máximo.
#
# Qué NO hace (no hace falta para la app):
#   - No genera los informes PDF ni Excel del resto del proyecto.
#   - No recalcula UNA_POR_CIRCUITO: la app usa el último
#     UNA_POR_CIRCUITO/rds/circuitos_periodo.rds que haya (cambia muy poco).
#   - No publica el código de la app (eso es rsconnect::deployApp, solo si
#     cambió el código; ver INSTRUCTIVO.md).
# ==============================================================================

if (!file.exists("APP_nuevoinforme.Rproj")) {
  stop(
    "Este script se corre desde la raíz del proyecto APP_nuevoinforme. ",
    "Abrí APP_nuevoinforme.Rproj en RStudio y volvé a correrlo."
  )
}

paso <- function(n, texto) message("\n========== PASO ", n, " de 4: ", texto, " ==========")

source("global.R")

paso(1, "descargar los reportes de levantes (GOL) que faltan")
source("funciones_descarga_reportesGOL.R")

paso(2, "sumar los reportes nuevos al histórico de llenado")
source("cargaDeDatos.R")

paso(3, "descargar las capas del DFR (contenedores activos e inactivos)")
source("db/DFR/conexionDFR.R")
actualizar_capas_wfs(base_dir = "db/DFR")

paso(4, "publicar los datos en GitHub para la app")
source("vistas/App_informe_llenado/limpieza_datos.R")

message(
  "\n✅ Listo. Si el último mensaje dice '¡GitHub actualizado!', la app publicada ",
  "muestra los datos nuevos en 10 minutos como máximo.\n",
  "   Si dice 'Error al sincronizar con GitHub', ver la sección ",
  "'Si algo falla' de vistas/App_informe_llenado/INSTRUCTIVO.md."
)
