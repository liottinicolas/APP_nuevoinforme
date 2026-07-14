# ==============================================================================
# funciones_descarga_reportesGOL.R
# Descarga automática de reportes de levantes pendientes usando Playwright.
# ==============================================================================

message("⏳ Verificando descargas pendientes de reportes de levante (GOL_reportes)...")
ruta_base_datos <- "archivos/GOL_reportes"
archivos_csv <- list.files(path = ruta_base_datos, pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.csv$", recursive = TRUE, full.names = TRUE)

if (length(archivos_csv) > 0) {
  fechas_descargadas <- as.Date(sub("\\.csv$", "", basename(archivos_csv)))
  ultima_fecha <- max(fechas_descargadas, na.rm = TRUE)
  message("📅 Última fecha de levantes detectada: ", ultima_fecha)
} else {
  # Si no hay archivos, empezamos por defecto desde 10 días atrás
  ultima_fecha <- Sys.Date() - 10
  message("⚠️ No se encontraron archivos de levantes. Iniciando fallback desde: ", ultima_fecha)
}

fecha_inicio <- ultima_fecha + 1
fecha_fin <- Sys.Date() - 1 # Descargar hasta el día de ayer

if (fecha_inicio <= fecha_fin) {
  fechas_a_descargar <- seq(fecha_inicio, fecha_fin, by = "day")
  message("📅 Fechas pendientes de descargar: ", paste(fechas_a_descargar, collapse = ", "))
  
  usuario <- Sys.getenv("APEX_USUARIO")
  contrasena <- Sys.getenv("APEX_CONTRASENA")
  
  if (usuario == "" || contrasena == "") {
    if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
      message("🔑 Credenciales no detectadas en variables de entorno. Solicitando ingreso interactivo...")
      if (usuario == "") {
        usuario <- rstudioapi::showPrompt(
          "Acceso IMM (APEX / Intranet)", "Usuario IMM (ej: im4445285)",
          default = "im4445285"
        )
      }
      if (contrasena == "") {
        contrasena <- rstudioapi::askForPassword("Contraseña de la IMM")
      }
    }
  }
  
  if (is.null(usuario) || is.null(contrasena) || usuario == "" || contrasena == "") {
    stop("❌ Error: Se requieren credenciales de usuario y contraseña para continuar con la descarga.")
  }
  
  python_venv <- reticulate::virtualenv_python("r-reticulate")
  
  for (f in as.character(fechas_a_descargar)) {
    message("📥 Ejecutando descarga de Playwright para levantes del día: ", f)
    # Pasar como argumentos: script, fecha, usuario, contraseña
    args <- c("archivos/descargar_datos_reportesGOL.py", f, usuario, contrasena)
    status <- system2(python_venv, args = args)
    if (status != 0) {
      stop("❌ Error crítico: Falló la descarga de reportes de levante para la fecha: ", f)
    }
  }
} else {
  message("✅ Todos los reportes de levantes están al día. No hay descargas pendientes.")
}
