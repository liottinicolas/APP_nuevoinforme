# ==============================================================================
# actualizar_datos_app.R
# Versión mínima de nuevoinforme.R: corre SOLO los pasos que necesita la app
# "Informe de llenado" (vistas/App_informe_llenado/) y la vuelve a publicar.
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
#   Paso 4. Sube los datos a GitHub (repo APP_nuevoinforme-data).
#   Paso 5. Vuelve a publicar la app en shinyapps.io (rsconnect::deployApp).
#           La app publicada no toma sola los datos nuevos: al publicarla se
#           reinicia y lee los datos que se acaban de subir en el paso 4.
#
# Qué NO hace (no hace falta para la app):
#   - No genera los informes PDF ni Excel del resto del proyecto.
#   - No recalcula UNA_POR_CIRCUITO: la app usa el último
#     UNA_POR_CIRCUITO/rds/circuitos_periodo.rds que haya (cambia muy poco).
# ==============================================================================

if (!file.exists("APP_nuevoinforme.Rproj")) {
  stop(
    "Este script se corre desde la raíz del proyecto APP_nuevoinforme. ",
    "Abrí APP_nuevoinforme.Rproj en RStudio y volvé a correrlo."
  )
}

DIR_APP <- "vistas/App_informe_llenado"

paso <- function(n, texto) message("\n========== PASO ", n, " de 5: ", texto, " ==========")

# Antes de descargar nada: si la cuenta de shinyapps.io no está configurada en
# esta PC, se avisa ahora y no al final, después de varios minutos.
if (!"datoseindicadores" %in% rsconnect::accounts()$name) {
  stop(
    "Esta PC no tiene configurada la cuenta 'datoseindicadores' de shinyapps.io. ",
    "Seguí el paso 1.1 de ", DIR_APP, "/INSTRUCTIVO.md y volvé a correr el script."
  )
}

source("global.R")

paso(1, "descargar los reportes de levantes (GOL) que faltan")
source("funciones_descarga_reportesGOL.R")

paso(2, "sumar los reportes nuevos al histórico de llenado")
source("cargaDeDatos.R")

paso(3, "descargar las capas del DFR (contenedores activos e inactivos)")
source("db/DFR/conexionDFR.R")
actualizar_capas_wfs(base_dir = "db/DFR")

paso(4, "subir los datos a GitHub")
source(file.path(DIR_APP, "limpieza_datos.R"))

paso(5, "publicar la app en shinyapps.io")
# Una carpeta data/ dentro de la app se subiría con el deploy y dejaría la app
# con datos congelados (ver .rscignore). Si existe, se corta antes de publicar.
archivos_deploy <- rsconnect::listDeploymentFiles(DIR_APP)
if (any(startsWith(archivos_deploy, "data/"))) {
  stop(
    "Hay una carpeta data/ dentro de ", DIR_APP, ". Borrala o movela a otro ",
    "lugar y publicá a mano (paso 4 de INSTRUCTIVO.md)."
  )
}
message("Archivos que se publican: ", paste(archivos_deploy, collapse = ", "))

rsconnect::deployApp(
  appDir         = DIR_APP,
  appName        = "App_informe_llenado",
  account        = "datoseindicadores",
  forceUpdate    = TRUE,
  launch.browser = TRUE
)

message(
  "\n✅ Listo. Datos subidos y app publicada: ",
  "https://datoseindicadores.shinyapps.io/App_informe_llenado/\n",
  "   Revisá que arriba a la derecha diga 'Datos al' con la fecha de ayer."
)
