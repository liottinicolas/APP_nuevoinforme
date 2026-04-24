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

    # 2. Instalar librerías Python si se solicitó (solo necesario la primera vez)
    if (instalar_librerias) {
        message("Instalando/verificando librerías de Python...")
        py_install(c("pandas", "numpy", "matplotlib", "reportlab", "fpdf2", "openpyxl", "odfpy", "xlwings", "pyreadr", "streamlit", "plotly"))
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
        message("Instalando/verificando librerías de Python...")
        py_install(c("pandas", "numpy", "matplotlib", "reportlab", "fpdf2", "openpyxl", "odfpy", "xlwings", "pyreadr", "streamlit", "plotly"))
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

    # Ruta hardcodeada al ejecutable de streamlit dentro del virtualenv de esta PC.
    # ⚠️ Si cambiás de usuario/máquina, verificar que la ruta siga siendo correcta.
    streamlit_path <- file.path(Sys.getenv("USERPROFILE"), "OneDrive", "Documentos y papeles importantes", ".virtualenvs", "r-reticulate", "Scripts", "streamlit.exe")

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
