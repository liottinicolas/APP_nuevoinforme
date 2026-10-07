# ==============================================================================
# ejecutor_evaluacion.R - Función R para ejecutar el Preinforme de Cumplimiento
# ==============================================================================

ejecutar_evaluacion <- function(
  capa_zonas,
  capa_gps = NULL,
  descargar_gps = FALSE,
  ods_matriculas = NULL,
  gps_descargado_gpkg = NULL,
  fecha_desde = "auto",
  fecha_hasta = "auto",
  servicio = "Mezclado",
  html_salida = NULL,
  abrir_reporte = TRUE
) {
  # Definir ruta de los scripts internos
  script_dir <- "C:/Users/im4445285/OneDrive/Trabajo IM/APP_nuevoinforme/scripts/qgis/ejecutar_evaluacion"
  cli_py <- file.path(script_dir, "ejecutar_evaluacion_cli.py")
  qgis_python <- "C:/Program Files/QGIS 3.30.0/bin/python-qgis.bat"
  
  if (!file.exists(cli_py)) {
    stop("❌ Error: No se encontró el script ejecutor en: ", cli_py)
  }
  if (!file.exists(qgis_python)) {
    stop("❌ Error: No se encontró el entorno Python de QGIS en: ", qgis_python)
  }
  
  # Si no se especifica salida HTML, guardar en la carpeta informes del paquete
  if (is.null(html_salida)) {
    html_salida <- file.path(script_dir, "informes", paste0("Informe_Cumplimiento_", format(Sys.Date(), "%Y%m%d"), ".html"))
  }
  
  # Preparar argumentos de la línea de comandos
  args <- c(
    shQuote(cli_py),
    "--zonas", shQuote(normalizePath(capa_zonas, winslash = "/", mustWork = TRUE)),
    "--servicio", shQuote(servicio),
    "--fecha-desde", shQuote(fecha_desde),
    "--fecha-hasta", shQuote(fecha_hasta),
    "--html-salida", shQuote(normalizePath(html_salida, winslash = "/", mustWork = FALSE))
  )
  
  if (isTRUE(descargar_gps)) {
    if (is.null(ods_matriculas) || is.null(gps_descargado_gpkg)) {
      stop("❌ Error: Si 'descargar_gps = TRUE', debe especificar 'ods_matriculas' y 'gps_descargado_gpkg'.")
    }
    args <- c(args, "--descargar-gps",
              "--ods", shQuote(normalizePath(ods_matriculas, winslash = "/", mustWork = TRUE)),
              "--gps-descargado-gpkg", shQuote(normalizePath(gps_descargado_gpkg, winslash = "/", mustWork = FALSE)))
  } else if (!is.null(capa_gps)) {
    args <- c(args, "--gps", shQuote(normalizePath(capa_gps, winslash = "/", mustWork = TRUE)))
  } else {
    stop("❌ Error: Debe especificar la ruta 'capa_gps' o activar 'descargar_gps = TRUE'.")
  }
  
  message("🚀 Ejecutando evaluación de cumplimiento desde R (PyQGIS Standalone)...")
  message("📍 Zonas: ", capa_zonas)
  message("📄 Salida HTML: ", html_salida)
  
  # Ejecutar en segundo plano mediante system2
  cmd_args <- paste(args, collapse = " ")
  status <- system2(qgis_python, args = cmd_args, stdout = TRUE, stderr = TRUE)
  
  cat(status, sep = "\n")
  
  if (file.exists(html_salida)) {
    message("======================================================================")
    message("✅ EVALUACIÓN FINALIZADA CON ÉXITO DESDE R.")
    message("📄 Reporte generado en: ", html_salida)
    message("======================================================================")
    if (abrir_reporte) {
      utils::browseURL(html_salida)
    }
    return(invisible(html_salida))
  } else {
    stop("❌ Ocurrió un error en el cálculo de la evaluación. Verifique los mensajes superiores.")
  }
}
