source("global.R")
source("cargaDeDatos.R")

source("informes/informe_diario.R")
source("informes/informecamiones.R")

source("funciones_utiles.R")

# Actualizar DFR
source("db/DFR/conexionDFR.R")
actualizar_capas_wfs(base_dir = "db/DFR")

# lista_sf <- cargar_capas_local(base_dir = "db/DFR", formato = "RDS")
# posiciones_dfr_viejos <- lista_sf[["dfr_C_DF_POSICIONES_RECORRIDO:HISTORICO"]]

source("db/POSTGRES/conexionPOSTGRES.R")


# dia sobre informe, debe ser el mismo día que se solicita (como al finalizar turno nocturno.)
# inf_deldia <- generar_reporte_dia("2026-02-17",historico_ubicaciones, historico_llenado)



# generar_reporte_pdf_informediario(fecha = "2026-02-17", instalar_librerias = FALSE)
# generar_reporte_pdf_informediario(fecha = NULL, instalar_librerias = FALSE)
# 
# 
# a <- ver$resumen_pordia_IM
# b <- ver$resumen_pordiaymunicipio_IM
# c <- ver$resumen_pordia_municipio_turno_completoconceros_IM
# 
# a <- inf_deldia$im
# b <- inf_deldia$fideicomiso

## pruebo hacer el pdf
generar_reporte_pdf_camionesylevantesIMFID(fecha = "2026-02-17", instalar_librerias = FALSE)
generar_reporte_pdf_camionesylevantesIMFID(fecha = NULL, instalar_librerias = TRUE)

# Ruta al Python del entorno virtual de reticulate (detecta automáticamente en cualquier PC)
python_venv <- reticulate::virtualenv_python("r-reticulate")

# Ejecutar el script de Python para generar el PDF
system2(python_venv, args = "vistas/informe_operativa/informeOP_generar_pdf.py")

# Ejecutar los scripts de Python para el informe diario
system2(python_venv, args = "vistas/informediario/reportes/actualizar_ayer.py")
## Antes de ejecutar para mapas, tiene que actualizar archivo.
system2(python_venv, args = "vistas/informediario/reportes/generar_mapas.py")

