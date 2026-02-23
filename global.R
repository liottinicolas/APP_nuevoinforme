### Función para cargar archivos con manejo de errores ----
cargar_archivo <- function(ruta_archivo) {
  tryCatch({
    source(ruta_archivo)
    escribir_log("INFO", paste("Archivo cargado con éxito:", ruta_archivo))
  }, error = function(e) {
    manejar_error(e, paste("al cargar", ruta_archivo))
  })
}

preparar_entorno <- function(paquetes = NULL, tz = "America/Montevideo") {
  
  # 1. Configuración de opciones globales y Zona Horaria
  Sys.setenv(TZ = tz)
  options(
    stringsAsFactors = FALSE,
    encoding = "UTF-8",
    scipen = 999 # Tip extra: evita la notación científica en tus reportes
  )
  
  # 2. Lista de paquetes por defecto (si no se pasan otros)
  if (is.null(paquetes)) {
    paquetes <- c(
      "shiny", "shinydashboard", "shinyWidgets", "DT", "htmlwidgets",
      "dplyr", "tidyr", "purrr", "readr", "stringr", "stringi", "lubridate",
      "ggplot2", "plotly", "leaflet", "sf",
      "knitr", "rmarkdown", "openxlsx", "writexl", "readxl",
      "rsconnect", "here", "R6", "tools", "magrittr", "httr","fs"
    )
  }
  
  # 3. Identificar e instalar paquetes faltantes
  faltantes <- paquetes[!(paquetes %in% installed.packages()[, "Package"])]
  
  if (length(faltantes) > 0) {
    message("Instalando paquetes faltantes: ", paste(faltantes, collapse = ", "))
    install.packages(faltantes, dependencies = TRUE)
  }
  
  # 4. Cargar todos los paquetes
  invisible(lapply(paquetes, library, character.only = TRUE))
  
  message("✅ Entorno configurado para ", tz, " y paquetes cargados.")
}

cargar_configuracion_modulo <- function(modulo, 
                                        nombre_archivo_funcion = NULL, 
                                        nombre_archivo_historico = NULL) {
  
  # 1. Mapeo de nombres específicos (si no vienen en los argumentos)
  # Esto reemplaza todos los if-else anidados
  mapeo_nombres <- list(
    "10393_ubicaciones" = list(fanc = "ubicaciones", hist = "ubicaciones"),
    "GOL_reportes"      = list(fanc = "golReportesDiarios", hist = "llenadoGol")
  )
  
  # 2. Asignar nombres por defecto si no se proporcionaron
  if (is.null(nombre_archivo_funcion)) {
    nombre_archivo_funcion <- if (modulo %in% names(mapeo_nombres)) {
      mapeo_nombres[[modulo]]$fanc
    } else {
      modulo
    }
  }
  
  if (is.null(nombre_archivo_historico)) {
    nombre_archivo_historico <- if (modulo %in% names(mapeo_nombres)) {
      mapeo_nombres[[modulo]]$hist
    } else {
      modulo
    }
  }
  
  # 3. Construcción de rutas usando here() para evitar depender de 'ruta_proyecto' global
  # 'here()' ya sabe dónde empieza tu proyecto
  ruta_base    <- file.path("db", modulo)
  ruta_archivo <- file.path("archivos", modulo)
  
  return(list(
    ruta_funciones      = here(ruta_base, paste0("funciones_db_", nombre_archivo_funcion, ".R")),
    ruta_carpeta_archivos = here(ruta_archivo),
    ruta_RDS_datos      = here(ruta_base, paste0("historico_", nombre_archivo_historico, ".rds")),
    ruta_RDS_archivos_procesados  = here(ruta_base, paste0("archivos_aplicados_historico_", nombre_archivo_historico, ".rds"))
  ))
}