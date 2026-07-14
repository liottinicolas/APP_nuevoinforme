# ==============================================================================
# funciones_descarga_consulta10393ubicaciones.R
# Descarga automática de ubicaciones faltantes usando Playwright.
# ==============================================================================

message("⏳ Verificando descargas pendientes de ubicaciones...")
ruta_base_datos <- "archivos/10393_ubicaciones"
archivos_csv <- list.files(path = ruta_base_datos, pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.csv$", recursive = TRUE, full.names = TRUE)

if (length(archivos_csv) > 0) {
  fechas_descargadas <- as.Date(sub("\\.csv$", "", basename(archivos_csv)))
  ultima_fecha <- max(fechas_descargadas, na.rm = TRUE)
  message("📅 Última fecha de ubicaciones detectada: ", ultima_fecha)
} else {
  # Si no hay archivos, empezamos por defecto desde 10 días atrás
  ultima_fecha <- Sys.Date() - 10
  message("⚠️ No se encontraron archivos de ubicaciones. Iniciando fallback desde: ", ultima_fecha)
}

fecha_inicio <- ultima_fecha + 1
fecha_fin <- Sys.Date() - 1 # Descargar hasta el día de ayer

if (fecha_inicio <= fecha_fin) {
  fechas_a_descargar <- seq(fecha_inicio, fecha_fin, by = "day")
  message("📅 Fechas pendientes de descargar: ", paste(fechas_a_descargar, collapse = ", "))
  
  usuario <- Sys.getenv("APEX_USUARIO")
  contrasena <- Sys.getenv("APEX_CONTRASENA")
  
  if (usuario == "" || contrasena == "") {
    warning("⚠️ Las variables de entorno APEX_USUARIO o APEX_CONTRASENA están vacías. Asegúrate de definirlas.")
  }
  
  python_venv <- reticulate::virtualenv_python("r-reticulate")
  
  for (f in as.character(fechas_a_descargar)) {
    message("📥 Ejecutando descarga de Playwright para: ", f)
    # Pasar como argumentos: script, fecha, usuario, contraseña
    args <- c("archivos/descargar_datos_10393_ubicaciones.py", f, usuario, contrasena)
    status <- system2(python_venv, args = args)
    if (status != 0) {
      stop("❌ Error crítico: Falló la descarga de ubicaciones para la fecha: ", f)
    }
  }
} else {
  message("✅ Todas las ubicaciones están al día. No hay descargas pendientes.")
}
