# ==============================================================================
# actualizar_y_publicar.R
# Actualiza los datos de la app "Informe de llenado" y la publica en
# shinyapps.io. Todo pasa dentro de esta carpeta: no usa OneDrive ni GitHub.
#
# Cómo usarlo (ver LEEME.md):
#   1. Abrir App_informe_llenado_paquete.Rproj con doble clic (abre RStudio).
#   2. En la consola:  source("actualizar_y_publicar.R")
#   3. Escribir usuario y contraseña de la IMM cuando lo pida.
#
# Pasos:
#   1. Descarga de la intranet los levantes (CSV) que faltan, hasta ayer.
#   2. Los suma a datos/historico_llenado.rds.
#   3. Descarga del GeoServer los contenedores activos e inactivos.
#   4. Prepara los datos para la app (carpeta app/data/).
#   5. Publica la app con los datos adentro (rsconnect::deployApp).
# ==============================================================================

# --- Opciones (dejar en TRUE salvo que el LEEME diga otra cosa) ---------------
DESCARGAR_LEVANTES <- TRUE   # pasos 1 y 2
DESCARGAR_CONTENEDORES <- TRUE  # paso 3
PUBLICAR <- TRUE             # paso 5
# -----------------------------------------------------------------------------

if (!file.exists("actualizar_y_publicar.R") || !dir.exists("app")) {
  stop("Abrí App_informe_llenado_paquete.Rproj con doble clic y volvé a correr el script.")
}

paso <- function(n, texto) message("\n========== PASO ", n, " de 5: ", texto, " ==========")
source("funciones/funciones_paquete.R", encoding = "UTF-8")

# Si la cuenta de shinyapps.io no está configurada, se avisa antes de descargar.
if (PUBLICAR && !"datoseindicadores" %in% rsconnect::accounts()$name) {
  stop("Falta configurar la cuenta 'datoseindicadores' de shinyapps.io (LEEME.md, paso 1.3).")
}

cred <- if (DESCARGAR_LEVANTES || DESCARGAR_CONTENEDORES) pedir_credenciales() else NULL

paso(1, "descargar los levantes (CSV) que faltan")
if (DESCARGAR_LEVANTES) {
  descargar_csv_gol(readRDS("datos/historico_llenado.rds"), cred)
} else message("(salteado)")

paso(2, "sumar los levantes nuevos al histórico")
if (DESCARGAR_LEVANTES) actualizar_historico() else message("(salteado)")

paso(3, "descargar contenedores activos e inactivos")
if (DESCARGAR_CONTENEDORES) descargar_capas_dfr(cred) else message("(salteado)")
rm(cred)

paso(4, "preparar los datos para la app")
escribir_datos_app()

paso(5, "publicar la app en shinyapps.io")
if (PUBLICAR) {
  message("Archivos que se publican: ",
          paste(rsconnect::listDeploymentFiles("app"), collapse = ", "))
  rsconnect::deployApp(
    appDir         = "app",
    appName        = "App_informe_llenado",
    account        = "datoseindicadores",
    forceUpdate    = TRUE,
    launch.browser = TRUE
  )
  message("\n✅ Listo: https://datoseindicadores.shinyapps.io/App_informe_llenado/\n",
          "   Revisá que arriba a la derecha diga 'Datos al' con la fecha de ayer.")
} else {
  message("(salteado) Para probar la app en esta PC: shiny::runApp(\"app\")")
}
