# ==============================================================================
# funciones_utiles.R
# Funciones de automatización del flujo de trabajo del proyecto.
# Se sourcean en nuevoinforme.R vía global.R.
#
# Contiene:
#   - generar_reporte_pdf_camionesylevantesIMFID() → PDF de camiones IM/FID
#   - generar_reporte_pdf_informediario()          → PDF informe diario
#   - correr_dashboard_camiones()                  → lanza Streamlit en navegador
#   - actualizar_github_datos()                    → sube datos vía git push
#   - exportar_resumen_contenedores()              → exporta resumen de contenedores a Excel
# ==============================================================================


# ── PDF Camiones y Levantes IM/FID ────────────────────────────────────────────

# Genera el informe PDF de camiones y levantes para IM y FID usando un script
# Python (reportlab). Gestiona automáticamente el entorno virtual de Python
# y pasa la fecha seleccionada como variable de entorno para que Python la lea.
#
# Parámetros:
#   fecha              - fecha del reporte en formato "YYYY-MM-DD". Si es NULL
#                        el script Python usa la fecha de hoy por defecto.
#   instalar_librerias - si TRUE, instala/verifica todas las librerías Python
#                        necesarias antes de correr (solo hacerlo la primera vez
#                        o cuando se actualicen dependencias).
#
# Uso:
#   generar_reporte_pdf_camionesylevantesIMFID()                        # hoy
#   generar_reporte_pdf_camionesylevantesIMFID("2026-02-17")            # fecha específica
#   generar_reporte_pdf_camionesylevantesIMFID(instalar_librerias=TRUE) # primera vez
generar_reporte_pdf_camionesylevantesIMFID <- function(fecha = NULL, instalar_librerias = FALSE) {
    library(reticulate)

    # 1. Verificar que el entorno virtual de Python existe; crearlo si no.
    #    virtualenv_root() detecta automáticamente la carpeta según la PC.
    venv_path <- file.path(virtualenv_root(), "r-reticulate")

    if (!virtualenv_exists(venv_path)) {
        message("El entorno virtual no existe en: ", venv_path, ". Intentando crearlo...")
        tryCatch(
            {
                virtualenv_create("r-reticulate")
            },
            error = function(e) {
                # Si no hay Python instalado, reticulate lo instala automáticamente
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
        librerias <- c("pandas", "numpy", "matplotlib", "reportlab", "fpdf2", "openpyxl", "odfpy", "xlwings", "pyreadr", "streamlit", "plotly")
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
            message("✅ Todas las librerías de Python ya están instaladas.")
        }
    }

    # 3. Pasar la fecha a Python como variable de entorno FECHA_REPORTE.
    #    Se setea tanto en el proceso Python (via os.environ) como en el sistema
    #    (via Sys.setenv) para garantizar que sea accesible desde cualquier lado.
    if (!is.null(fecha)) {
        py_run_string(paste0("import os; os.environ['FECHA_REPORTE'] = '", as.character(fecha), "'"))
        Sys.setenv(FECHA_REPORTE = as.character(fecha))
    } else {
        # Si no se especifica fecha, limpiar la variable para que Python use "hoy"
        py_run_string("import os; os.environ.pop('FECHA_REPORTE', None)")
        Sys.unsetenv("FECHA_REPORTE")
    }

    # 4. Ejecutar el script Python que genera los PDFs con reportlab
    message("Generando PDFs...")
    py_run_file("vistas/informe_levantes_camiones_porturno_IM_FID/generar_pdfs_reportlab.py")
    message("Generación de PDFs completada.")

    # 5. Limpiar la variable de entorno para no afectar ejecuciones futuras
    Sys.unsetenv("FECHA_REPORTE")
}

# Uso de referencia con fecha específica:
# generar_reporte_pdf_camionesylevantesIMFID(fecha = "2026-02-17", instalar_librerias = FALSE)


# ── PDF Informe Diario ────────────────────────────────────────────────────────

# Genera el PDF del informe diario ejecutando el script Python correspondiente.
# Sigue la misma lógica de entorno virtual y paso de fecha que la función anterior.
#
# Parámetros:
#   fecha              - fecha del reporte "YYYY-MM-DD". NULL = hoy.
#   instalar_librerias - instala dependencias Python si TRUE.
#
# Uso:
#   generar_reporte_pdf_informediario()                  # hoy
#   generar_reporte_pdf_informediario("2026-02-17")      # fecha específica
generar_reporte_pdf_informediario <- function(fecha = NULL, instalar_librerias = FALSE) {
    library(reticulate)

    if (!virtualenv_exists("r-reticulate")) {
        message("El entorno virtual no existe. Intentando crearlo...")
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

    if (instalar_librerias) {
        message("Verificando librerías de Python instaladas...")
        librerias <- c("pandas", "numpy", "matplotlib", "reportlab", "fpdf2", "openpyxl", "odfpy", "xlwings", "pyreadr", "streamlit", "plotly")
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
            message("✅ Todas las librerías de Python ya están instaladas.")
        }
    }

    if (!is.null(fecha)) {
        py_run_string(paste0("import os; os.environ['FECHA_REPORTE'] = '", as.character(fecha), "'"))
        Sys.setenv(FECHA_REPORTE = as.character(fecha))
    } else {
        py_run_string("import os; os.environ.pop('FECHA_REPORTE', None)")
        Sys.unsetenv("FECHA_REPORTE")
    }

    message("Generando PDF Informe Diario...")
    py_run_file("vistas/informediario/informe_diario_pdf.py")
    message("Generación de PDF Informe Diario completada.")
    Sys.unsetenv("FECHA_REPORTE")
}

# Uso de referencia con fecha específica:
# generar_reporte_pdf_informediario(fecha = "2026-02-17", instalar_librerias = FALSE)


# ── Dashboard Streamlit (navegador) ───────────────────────────────────────────

# Lanza el dashboard de Streamlit en el navegador usando processx para correrlo
# como proceso externo no bloqueante. El dashboard queda corriendo hasta que
# se cierre la sesión o se detenga el proceso manualmente.
#
# Nota: la ruta al ejecutable de streamlit.exe es fija según el perfil de usuario
# de la PC. Si se cambia de máquina puede necesitar ajuste.
#
# Parámetros:
#   instalar_paquetes - si TRUE, verifica e instala processx si no está disponible.
#
# Uso:
#   px <- correr_dashboard_camiones()
#   # px es el objeto de proceso; se puede detener con px$kill()
correr_dashboard_camiones <- function(instalar_paquetes = FALSE) {
    if (instalar_paquetes) {
        message("Instalando/verificando paquete processx...")
        if (!requireNamespace("processx", quietly = TRUE)) {
            install.packages("processx")
        }
    }

    library(processx)

    message("Iniciando dashboard en Streamlit...")

    # Determinar dinámicamente la ruta del ejecutable de streamlit en el virtualenv
    venv_root <- Sys.getenv("WORKON_HOME")
    if (venv_root == "") {
        venv_root <- file.path(Sys.getenv("USERPROFILE"), ".virtualenvs")
    }
    streamlit_path <- file.path(venv_root, "r-reticulate", if (.Platform$OS.type == "windows") "Scripts/streamlit.exe" else "bin/streamlit")
    # Reemplazar barras invertidas por normales para evitar problemas
    streamlit_path <- gsub("\\\\", "/", streamlit_path)

    # run() de processx lanza el proceso en background y devuelve un objeto controlable
    px <- run(streamlit_path,
        args = c("run", "vistas/Informe_diario.py"),
        echo = TRUE
    )

    message("Dashboard en ejecución.")
    return(px)
}

# Uso:
# px <- correr_dashboard_camiones(instalar_paquetes = FALSE)
# px$kill()  # para detenerlo


# ── Actualizar datos en GitHub (push) ─────────────────────────────────────────

# Hace git add + commit + push de una carpeta de datos para sincronizar con GitHub.
# Si el push falla por credenciales expiradas, guía al usuario paso a paso para
# renovar el Personal Access Token (PAT) y reintenta automáticamente.
#
# Parámetros:
#   data_dir - carpeta a agregar con git add (por defecto "vistas/").
#              Git sube todos los archivos modificados dentro de esa carpeta.
#
# Nota: esta función usa system() directamente (git en PATH). Para la app Shiny
#       se usa limpieza_datos.R con gert, que es más robusto.
#
# Uso:
#   actualizar_github_datos()                    # sube todo vistas/
#   actualizar_github_datos("vistas/App_informe_llenado/data/")
actualizar_github_datos <- function(data_dir = "vistas/") {
    message("Iniciando actualización en GitHub...")

    # 1. git add + commit. Se suprimen warnings por si no hay cambios nuevos.
    suppressWarnings({
        # git add agrega todos los archivos modificados dentro de data_dir
        system(paste0("git add ", data_dir), ignore.stdout = TRUE, ignore.stderr = TRUE)
        system('git commit -m "Actualización automática datos levantes camiones IM"', ignore.stdout = TRUE, ignore.stderr = TRUE)
    })

    # 2. git push con manejo de error por credenciales expiradas
    tryCatch(
        {
            message("Haciendo push a GitHub...")
            # system() devuelve 0 si el comando exitó correctamente, otro valor si falló
            status <- system("git push origin main", intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)

            if (status != 0) {
                stop("El comando git push devolvió error (posiblemente falta de credenciales o token expirado).")
            }

            message("¡Proceso completado! Los datos ya están en GitHub.")
        },
        error = function(e) {
            message("Hubo un error al hacer push:\n", e$message)
            message("Esto suele deberse a que el token de GitHub expiró o no tenés credenciales guardadas.")

            # Instalar usethis y gitcreds si no están disponibles (herramientas de gestión de credenciales)
            if (!requireNamespace("usethis", quietly = TRUE)) install.packages("usethis")
            if (!requireNamespace("gitcreds", quietly = TRUE)) install.packages("gitcreds")

            message("\n--> PASO 1: Se abrirá tu navegador para crear/renovar un Personal Access Token.")
            message("Asegurate de incluir al menos el permiso 'repo' y copiar el token generado.")
            readline(prompt = "Presioná ENTER en la consola para abrir GitHub y generar el token...")
            usethis::create_github_token()

            message("\n--> PASO 2: Pegá el token que copiaste.")
            gitcreds::gitcreds_set()

            # Reintentar el push con las nuevas credenciales
            message("\nReintentando push con las nuevas credenciales...")
            status_retry <- system("git push origin main", intern = FALSE)

            if (status_retry == 0) {
                message("¡Push completado con éxito tras renovar credenciales!")
            } else {
                message("Volvió a fallar el push. Por favor revisá manualmente los permisos del token.")
            }
        }
    )
}

# Uso:
# actualizar_github_datos(data_dir = "vistas/")


# ── Exportar Resumen de Contenedores ──────────────────────────────────────────

# Exporta un archivo de Excel con la cantidad diaria de contenedores
# según rango de fechas, oficina y estado (activos o todos).
#
# Parámetros:
#   fecha_inicio - fecha inicial del filtro en formato "YYYY-MM-DD"
#   fecha_fin    - fecha final del filtro en formato "YYYY-MM-DD"
#   Solo_activos - si TRUE, filtra solo contenedores activos (Estado es NA/vacío)
#   Oficina      - puede ser "IM", "Fideicomiso" o "Total" (sin filtro de oficina)
#   df           - data.frame opcional con los datos de ubicaciones. Si es NULL,
#                  se busca en el entorno global o se lee el archivo RDS.
#
# Uso:
#   exportar_resumen_contenedores("2026-02-10", "2026-02-17", Solo_activos = TRUE, Oficina = "IM")
exportar_resumen_contenedores <- function(fecha_inicio, fecha_fin, Solo_activos = TRUE, Oficina = "Total", df = NULL) {
    library(dplyr)
    library(openxlsx)

    # 1. Cargar historico_ubicaciones si df es NULL
    if (is.null(df)) {
        if (exists("historico_ubicaciones", envir = .GlobalEnv)) {
            df <- get("historico_ubicaciones", envir = .GlobalEnv)
        } else {
            ruta_rds <- "db/10393_ubicaciones/historico_ubicaciones.rds"
            if (file.exists(ruta_rds)) {
                df <- readRDS(ruta_rds)
            } else {
                stop("No se encontró la variable 'historico_ubicaciones' ni el archivo RDS correspondiente en db/10393_ubicaciones/historico_ubicaciones.rds.")
            }
        }
    }

    # 2. Guardar valores de parámetros en variables locales para evitar conflictos de ámbito con dplyr
    f_inicio <- as.Date(fecha_inicio)
    f_fin <- as.Date(fecha_fin)
    ofi_val <- trimws(Oficina)

    # 3. Filtrar por rango de fechas
    df_filtrado <- df %>%
        filter(as.Date(Fecha) >= f_inicio & as.Date(Fecha) <= f_fin)

    # 4. Filtrar por Estado (Solo_activos)
    if (Solo_activos) {
        df_filtrado <- df_filtrado %>%
            filter(is.na(Estado) | trimws(Estado) == "")
    }

    # 5. Filtrar por Oficina (IM, Fideicomiso o Total)
    if (tolower(ofi_val) == "im") {
        df_filtrado <- df_filtrado %>%
            filter(toupper(trimws(Oficina)) == "IM")
    } else if (tolower(ofi_val) == "fideicomiso") {
        df_filtrado <- df_filtrado %>%
            filter(toupper(trimws(Oficina)) == "FIDEICOMISO")
    } else if (tolower(ofi_val) != "total") {
        df_filtrado <- df_filtrado %>%
            filter(toupper(trimws(Oficina)) == toupper(ofi_val))
    }

    # 6. Agrupar por día y contar contenedores (cantidad de filas)
    df_resumen <- df_filtrado %>%
        group_by(Fecha) %>%
        summarise(
            Contenedores = n(),
            .groups = "drop"
        ) %>%
        arrange(Fecha)

    # 7. Crear la carpeta Salidas si no existe
    if (!dir.exists("Salidas")) {
        dir.create("Salidas", recursive = TRUE)
    }

    # 8. Generar nombre de archivo y ruta de exportación
    estado_str <- if (Solo_activos) "activos" else "todos"
    nombre_archivo <- paste0("contenedores_", fecha_inicio, "_", fecha_fin, "_", ofi_val, "_", estado_str, ".xlsx")
    ruta_salida <- file.path("Salidas", nombre_archivo)

    # 9. Exportar a Excel
    write.xlsx(
        df_resumen,
        file = ruta_salida,
        asTable = TRUE,
        tableStyle = "TableStyleMedium2"
    )

    message("✅ Resumen exportado con éxito en: ", ruta_salida)
    return(df_resumen)
}

# Ejemplos de uso de la función:
#
# Caso 1: Obtener contenedores activos para la oficina "IM"
# exportar_resumen_contenedores(fecha_inicio = "2025-07-01", fecha_fin = "2026-07-16", Solo_activos = TRUE, Oficina = "IM")
#
# Caso 2: Obtener el total de contenedores (activos e inactivos) de toda la base (Oficina = "Total")
# exportar_resumen_contenedores(fecha_inicio = "2025-07-01", fecha_fin = "2026-07-16", Solo_activos = TRUE, Oficina = "Total")
#
# Caso 3: Obtener contenedores activos para la oficina "Fideicomiso"
# exportar_resumen_contenedores(fecha_inicio = "2026-02-10", fecha_fin = "2026-02-17", Solo_activos = TRUE, Oficina = "Fideicomiso")
#
# Caso 4: Pasándole un dataframe ya cargado en memoria directamente
# exportar_resumen_contenedores(fecha_inicio = "2026-02-10", fecha_fin = "2026-02-17", Solo_activos = TRUE, Oficina = "IM", df = historico_ubicaciones)
