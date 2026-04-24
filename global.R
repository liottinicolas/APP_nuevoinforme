# ==============================================================================
# global.R
# Funciones de infraestructura del proyecto. Se sourcean al inicio de
# nuevoinforme.R para que estén disponibles en todos los módulos.
# Contiene: logging, manejo de errores, preparación del entorno y
# resolución de rutas por módulo.
# ==============================================================================


# ── Logging y errores ─────────────────────────────────────────────────────────

# Imprime un mensaje con nivel (ej: "INFO", "WARN") y timestamp.
# Útil para seguir el progreso del script en consola.
escribir_log <- function(nivel, mensaje) {
  cat(paste0("[", nivel, "] ", Sys.time(), ": ", mensaje, "\n"))
}

# Muestra un mensaje de error con contexto legible.
# Se usa dentro de bloques tryCatch para no perder información del fallo.
manejar_error <- function(err, contexto) {
  message(paste("❌ Error", contexto, ":", err$message))
}


# ── Carga segura de archivos ───────────────────────────────────────────────────

# Ejecuta source() con manejo de errores: si el archivo falla, loguea el error
# pero no detiene la ejecución del script principal.
cargar_archivo <- function(ruta_archivo) {
  tryCatch({
    source(ruta_archivo)
    escribir_log("INFO", paste("Archivo cargado con éxito:", ruta_archivo))
  }, error = function(e) {
    manejar_error(e, paste("al cargar", ruta_archivo))
  })
}


# ── Preparación del entorno ───────────────────────────────────────────────────

# Configura opciones globales de R, zona horaria e instala/carga todos los
# paquetes necesarios para el proyecto. Si algún paquete no está instalado,
# lo instala automáticamente antes de cargarlo.
#
# Parámetros:
#   paquetes  - vector de nombres de paquetes. Si es NULL usa la lista por defecto.
#   tz        - zona horaria (por defecto "America/Montevideo")
#
# Uso:
#   preparar_entorno()                      # usa configuración por defecto
#   preparar_entorno(paquetes = c("dplyr")) # solo carga dplyr
preparar_entorno <- function(paquetes = NULL, tz = "America/Montevideo") {
  
  # 1. Configuración de opciones globales y zona horaria
  Sys.setenv(TZ = tz)
  options(
    stringsAsFactors = FALSE,  # evita que los character se conviertan a factor automáticamente
    encoding = "UTF-8",        # encoding consistente para nombres con tildes y ñ
    scipen = 999               # evita notación científica en reportes (ej: 1000000 en vez de 1e+06)
  )
  
  # 2. Lista de paquetes por defecto del proyecto
  if (is.null(paquetes)) {
    paquetes <- c(
      # Shiny y UI
      "shiny", "shinydashboard", "shinyWidgets", "bs4Dash", "DT", "htmlwidgets",

      # Manipulación de datos
      "dplyr", "tidyr", "purrr", "readr", "stringr", "stringi", "lubridate", "jsonlite",

      # Visualización
      "ggplot2", "plotly", "leaflet", "leaflet.extras", "sf",

      # Reportes y Excel
      "knitr", "rmarkdown", "openxlsx", "writexl", "readxl",

      # Infraestructura y sistema
      "rsconnect", "here", "R6", "tools", "magrittr", "fs",
      "httr", "httr2",         # httr: requests clásicos | httr2: API moderna
      "reticulate",            # ejecución de Python desde R
      "processx",              # ejecución de procesos externos del sistema
      "gert",                  # operaciones Git desde R
      "pins",                  # lectura/escritura de datos en GitHub y local

      # Performance y estilos
      "cachem", "bslib", "fastmap", "sass"
    )
  }
  
  # 3. Detectar e instalar paquetes que no estén en la librería local
  faltantes <- paquetes[!(paquetes %in% installed.packages()[, "Package"])]
  
  if (length(faltantes) > 0) {
    message("Instalando paquetes faltantes: ", paste(faltantes, collapse = ", "))
    install.packages(faltantes, dependencies = TRUE)
  }
  
  # 4. Cargar todos los paquetes en el entorno de R
  invisible(lapply(paquetes, library, character.only = TRUE))
  
  message("✅ Entorno configurado para ", tz, " y paquetes cargados.")
}


# ── Resolución de rutas por módulo ────────────────────────────────────────────

# Devuelve las rutas estándar de archivos asociadas a un módulo de base de datos.
# Permite que cada módulo (ej: "GOL_reportes", "10393_ubicaciones") tenga sus
# archivos organizados de forma consistente sin hardcodear rutas en cada script.
#
# Parámetros:
#   modulo                    - nombre del módulo/subcarpeta dentro de db/ y archivos/
#   nombre_archivo_funcion    - nombre base del script de funciones (opcional, se infiere del módulo)
#   nombre_archivo_historico  - nombre base del RDS histórico (opcional, se infiere del módulo)
#
# Retorna una lista con 4 rutas:
#   $ruta_funciones               → db/<modulo>/funciones_db_<X>.R
#   $ruta_carpeta_archivos        → archivos/<modulo>/
#   $ruta_RDS_datos               → db/<modulo>/historico_<X>.rds
#   $ruta_RDS_archivos_procesados → db/<modulo>/archivos_aplicados_historico_<X>.rds
#
# Uso:
#   cfg <- cargar_configuracion_modulo("GOL_reportes")
#   source(cfg$ruta_funciones)
#   datos <- readRDS(cfg$ruta_RDS_datos)
cargar_configuracion_modulo <- function(modulo, 
                                        nombre_archivo_funcion = NULL, 
                                        nombre_archivo_historico = NULL) {
  
  # 1. Mapeo de módulos con nombres de archivo que difieren del nombre del módulo.
  #    Si el módulo no está en esta lista, se usa el nombre del módulo directamente.
  mapeo_nombres <- list(
    "10393_ubicaciones" = list(fanc = "ubicaciones",        hist = "ubicaciones"),
    "GOL_reportes"      = list(fanc = "golReportesDiarios", hist = "llenadoGol")
  )
  
  # 2. Asignar nombres inferidos si no se proporcionaron explícitamente
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
  
  # 3. Construcción de rutas con here() — portables entre usuarios y sistemas operativos.
  #    here() ancla la ruta a la raíz del proyecto (.Rproj) automáticamente.
  ruta_base    <- file.path("db", modulo)
  ruta_archivo <- file.path("archivos", modulo)
  
  return(list(
    ruta_funciones                = here(ruta_base, paste0("funciones_db_", nombre_archivo_funcion, ".R")),
    ruta_carpeta_archivos         = here(ruta_archivo),
    ruta_RDS_datos                = here(ruta_base, paste0("historico_", nombre_archivo_historico, ".rds")),
    ruta_RDS_archivos_procesados  = here(ruta_base, paste0("archivos_aplicados_historico_", nombre_archivo_historico, ".rds"))
  ))
}