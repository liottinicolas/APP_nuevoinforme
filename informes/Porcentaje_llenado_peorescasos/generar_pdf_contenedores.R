# Genera un PDF con el detalle por gid del resultado de analizar_peores_contenedores()
# (ver PorcentajeLlenado.R): identificación, historial crudo filtrado a ese gid,
# y sus métricas agregadas. Un PDF único con una sección por gid.
# Sigue el mismo patrón de entorno virtual de Python que funciones_utiles.R.

# ── PDF por contenedor ─────────────────────────────────────────────────────────
#
# Parámetros:
#   resultado_analisis - lista devuelta por analizar_peores_contenedores()
#                         (debe traer $resultado y $datos_filtrados).
#   nombre_salida       - nombre del archivo .pdf de salida (se guarda en
#                          informes/salidas/). Si es NULL, se arma a partir de
#                          $descripcion_filtros del resultado_analisis.
#   instalar_librerias  - si TRUE, instala/verifica pandas, pyreadr y reportlab
#                          en el entorno virtual antes de correr (solo hace
#                          falta la primera vez o al actualizar dependencias).
#
# Uso:
#   ver <- analizar_peores_contenedores(gids = c("184421", "184471", "107365"))
#   generar_pdf_contenedores(ver)
generar_pdf_contenedores <- function(resultado_analisis, nombre_salida = NULL, instalar_librerias = FALSE) {
  library(reticulate)

  if (is.null(resultado_analisis$resultado) || is.null(resultado_analisis$datos_filtrados)) {
    stop("resultado_analisis debe ser la lista devuelta por analizar_peores_contenedores() (con $resultado y $datos_filtrados).")
  }

  # 1. Verificar que el entorno virtual de Python existe; crearlo si no (mismo patrón que funciones_utiles.R)
  venv_path <- file.path(virtualenv_root(), "r-reticulate")
  if (!virtualenv_exists(venv_path)) {
    message("El entorno virtual no existe en: ", venv_path, ". Intentando crearlo...")
    tryCatch(
      {
        virtualenv_create("r-reticulate")
      },
      error = function(e) {
        message("No se encontró Python instalarlo automáticamente...")
        install_python()
        virtualenv_create("r-reticulate")
      }
    )
  }
  use_virtualenv("r-reticulate", required = TRUE)

  # 2. Instalar librerías Python si se solicitó (solo instala las que falten)
  if (instalar_librerias) {
    message("Verificando librerías de Python instaladas...")
    librerias <- c("pandas", "pyreadr", "reportlab")
    faltantes <- c()
    for (lib in librerias) {
      if (!py_module_available(lib)) {
        faltantes <- c(faltantes, lib)
      }
    }
    if (length(faltantes) > 0) {
      message("Instalando librerías de Python faltantes: ", paste(faltantes, collapse = ", "))
      py_install(faltantes)
    } else {
      message("Todas las librerías de Python ya están instaladas.")
    }
  }

  # 3. Guardar los datos para que Python los lea con pyreadr (un .rds por data.frame,
  #    igual que el resto de los generadores de PDF del proyecto)
  dir_datos <- "informes/Porcentaje_llenado_peorescasos/data"
  dir.create(dir_datos, showWarnings = FALSE, recursive = TRUE)
  saveRDS(resultado_analisis$resultado, file.path(dir_datos, "pdf_resultado.rds"))
  saveRDS(resultado_analisis$datos_filtrados, file.path(dir_datos, "pdf_crudo.rds"))

  # 4. Nombre de salida: el que se pase, o uno armado a partir de los filtros del análisis
  if (is.null(nombre_salida)) {
    descripcion <- if (!is.null(resultado_analisis$descripcion_filtros)) resultado_analisis$descripcion_filtros else "contenedores"
    nombre_salida <- paste0("informe_contenedores_", descripcion, ".pdf")
  }

  # 5. Pasar el nombre de salida a Python como variable de entorno y correr el script
  Sys.setenv(PDF_CONTENEDORES_SALIDA = nombre_salida)
  message("Generando PDF...")
  py_run_file("informes/Porcentaje_llenado_peorescasos/generar_pdf_contenedores.py")
  Sys.unsetenv("PDF_CONTENEDORES_SALIDA")
  message("Generación de PDF completada.")
}

# Uso de referencia:
# ver <- analizar_peores_contenedores(gids = c("184421", "184471", "107365"))
# generar_pdf_contenedores(ver)
