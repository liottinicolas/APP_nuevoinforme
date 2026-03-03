### ---------------------------------------------------------------------------
### FUNCIONES ÚTILES Y DE AUTOMATIZACIÓN
### (Generación de PDFs, Dashboards, Actualización en GitHub, etc.)
### ---------------------------------------------------------------------------

### Camiones
generar_reporte_pdf_camionesylevantesIMFID <- function(fecha = NULL, instalar_librerias = FALSE) {
    library(reticulate)

    # 1. Le decimos a R que use el entorno donde instalamos todo
    # Si el entorno no existe, lo creamos primero para evitar errores
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
    # Ejecutar esto para tener el kit completo de análisis y reporte solo si es necesario
    if (instalar_librerias) {
        message("Instalando/verificando librerías de Python...")
        py_install(c("pandas", "numpy", "matplotlib", "reportlab", "fpdf2", "openpyxl", "pyreadr", "streamlit", "plotly"))
    }

    # 2. Configurar la fecha enviada desde R hacia Python usando reticulate directamente
    if (!is.null(fecha)) {
        py_run_string(paste0("import os; os.environ['FECHA_REPORTE'] = '", as.character(fecha), "'"))
        Sys.setenv(FECHA_REPORTE = as.character(fecha)) # Por si acaso también a nivel sistema
    } else {
        py_run_string("import os; os.environ.pop('FECHA_REPORTE', None)")
        Sys.unsetenv("FECHA_REPORTE")
    }

    # 3. Ahora sí, corremos el script de los levantes de camiones
    message("Generando PDFs...")
    py_run_file("vistas/informe_levantes_camiones_porturno_IM_FID/generar_pdfs_reportlab.py")
    message("Generación de PDFs completada.")
    Sys.unsetenv("FECHA_REPORTE") # Limpieza tras ejecutar
}

# Para ejecutar la generación de PDFs, descomentá la siguiente línea:
# generar_reporte_pdf_camionesylevantesIMFID(instalar_librerias = FALSE)

### Informe Diario
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
        message("Instalando/verificando librerías de Python...")
        py_install(c("pandas", "numpy", "matplotlib", "reportlab", "fpdf2", "openpyxl", "pyreadr", "streamlit", "plotly"))
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

# Para ejecutar la generación del PDF de informe diario, descomentá la siguiente línea:
# generar_reporte_pdf_informediario(fecha = NULL, instalar_librerias = FALSE)

## Ejecutar en el navegador.
correr_dashboard_camiones <- function(instalar_paquetes = FALSE) {
    if (instalar_paquetes) {
        message("Instalando/verificando paquete processx...")
        if (!requireNamespace("processx", quietly = TRUE)) {
            install.packages("processx")
        }
    }

    library(processx)

    message("Iniciando dashboard en Streamlit...")
    px <- run("C:/Users/im4445285/Documents/.virtualenvs/r-reticulate/Scripts/streamlit.exe",
        args = c("run", "vistas/Informe_diario.py"), # Actualizado al nuevo nombre
        echo = TRUE
    )

    message("Dashboard en ejecución.")
    return(px)
}

# Para ejecutar el dashboard, descomentá la siguiente línea:
# px <- correr_dashboard_camiones(instalar_paquetes = FALSE)
## FIN Ejecutar en el navegador.


## Actualizar datos en GitHub
actualizar_github_datos <- function(data_dir = "vistas/") {
    message("Iniciando actualización en GitHub...")

    # 1. Añadir y commitear. Se suprimen warnings por si no hay cambios para subir.
    suppressWarnings({
        # Nota: si los rds están dentro de subcarpetas, git add vistas/ los agregará automáticamente.
        system(paste0("git add ", data_dir), ignore.stdout = TRUE, ignore.stderr = TRUE)
        system('git commit -m "Actualización automática datos levantes camiones IM"', ignore.stdout = TRUE, ignore.stderr = TRUE)
    })

    # 2. Intentamos hacer el push y capturamos errores
    tryCatch(
        {
            message("Haciendo push a GitHub...")
            # intern = FALSE hace que R devuelva el código de salida de git (0 es éxito, distinto de 0 es error)
            status <- system("git push origin main", intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)

            if (status != 0) {
                stop("El comando git push devolvió error (posiblemente falta de credenciales o token expirado).")
            }

            message("¡Proceso completado! Los datos ya están viajando a Streamlit Cloud.")
        },
        error = function(e) {
            message("Hubo un error al hacer push:\n", e$message)
            message("Esto suele deberse a que el token de GitHub expiró o no tenés credenciales guardadas.")

            if (!requireNamespace("usethis", quietly = TRUE)) install.packages("usethis")
            if (!requireNamespace("gitcreds", quietly = TRUE)) install.packages("gitcreds")

            message("\n--> PASO 1: Se abrirá tu navegador para crear/renovar un Personal Access Token.")
            message("Asegurate de incluir al menos el permiso 'repo' y copiar el token generado.")
            readline(prompt = "Presioná ENTER en la consola para abrir GitHub y generar el token...")
            usethis::create_github_token()

            message("\n--> PASO 2: Pegá el token que copiaste.")
            gitcreds::gitcreds_set()

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

# Para actualizar los datos a GitHub, ejecutá:
# actualizar_github_datos(data_dir = "vistas/")
## FIN Actualizar datos en GitHub
