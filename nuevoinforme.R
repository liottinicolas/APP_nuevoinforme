# ==============================================================================
# nuevoinforme.R
# Script principal. Ejecutar manualmente para actualizar datos y generar todos
# los informes del sistema (DFR, GOL/Postgres, informes R, informes Python
# y sincronización de la app Shiny).
# ==============================================================================


# ── 1. SETUP: funciones y definiciones ────────────────────────────────────────
# Cargar primero las funciones para que estén disponibles en los pasos siguientes.

source("global.R")
source("funciones_utiles.R")          # Funciones auxiliares compartidas
source("cargaDeDatos.R")              # Carga de datos base del proyecto

source("informes/informe_diario.R")   # Define generar_reporte_dia() y afines
source("informes/informecamiones.R")  # Define generar_reporte_pdf_camiones...()


# ── 2. ACTUALIZAR DATOS EXTERNOS ──────────────────────────────────────────────

# Capas geoespaciales del DFR descargadas desde el WFS y guardadas como RDS local
source("db/DFR/conexionDFR.R")
actualizar_capas_wfs(base_dir = "db/DFR")

# Uso de referencia (carga local de capas ya descargadas):
# lista_sf <- cargar_capas_local(base_dir = "db/DFR", formato = "RDS")
# posiciones_dfr_viejos <- lista_sf[["dfr_C_DF_POSICIONES_RECORRIDO:HISTORICO"]]

# Datos operativos desde PostgreSQL (llenado GOL, ubicaciones, etc.)
# source("db/POSTGRES/conexionPOSTGRES.R")


# ── 3. GENERAR INFORMES EN R ──────────────────────────────────────────────────

# Informe diario de llenado (fecha = NULL usa el día de hoy)
# inf_deldia <- generar_reporte_dia("2026-02-17", historico_ubicaciones, historico_llenado)  # uso con fecha específica
# inf_deldia <- generar_reporte_dia(NULL, historico_ubicaciones, historico_llenado)

# Informe PDF diario IM
# generar_reporte_pdf_informediario(fecha = "2026-02-17", instalar_librerias = FALSE)  # uso con fecha específica
# generar_reporte_pdf_informediario(fecha = NULL, instalar_librerias = FALSE)

# Informe PDF camiones y levantes IMF/FID (fecha = NULL usa el día de hoy)
generar_reporte_pdf_camionesylevantesIMFID(fecha = "2026-02-17", instalar_librerias = FALSE)  # uso con fecha específica
generar_reporte_pdf_camionesylevantesIMFID(fecha = NULL, instalar_librerias = TRUE)


# ── 4. GENERAR INFORMES EN PYTHON ─────────────────────────────────────────────
# Usa el Python del entorno virtual de reticulate (se detecta automáticamente en cualquier PC)

python_venv <- reticulate::virtualenv_python("r-reticulate")

# Informe operativa (genera el PDF de la vista operativa)
system2(python_venv, args = "vistas/informe_operativa/informeOP_generar_pdf.py")

# Informe diario: primero actualiza los datos de ayer, luego genera los mapas
system2(python_venv, args = "vistas/informediario/reportes/actualizar_ayer.py")
system2(python_venv, args = "vistas/informediario/reportes/generar_mapas.py")  # requiere actualizar_ayer primero


# ── 5. ACTUALIZAR APP SHINY ───────────────────────────────────────────────────

# Sube los pines de datos frescos a GitHub para que la app los lea sin necesidad de redeploy
source("vistas/App_informe_llenado/limpieza_datos.R")

# Solo ejecutar si hubo cambios en el código de la app (no en los datos):
# rsconnect::deployApp("vistas/App_informe_llenado/")
