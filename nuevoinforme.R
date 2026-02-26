source("global.R")
source("cargaDeDatos.R")

source("informes/informe_diario.R")
source("informes/informecamiones.R")

# dia sobre informe, debe ser el mismo día que se solicita (como al finalizar turno nocturno.)
# inf_deldia <- generar_reporte_dia("2026-02-17",historico_ubicaciones, historico_llenado)


### Cargar funciones útiles
source("funciones_utiles.R")

# Para actualizar los datos a GitHub, ejecutá:
# actualizar_github_datos(data_dir = "vistas/")


## pruebo hacer el pdf
generar_reporte_pdf_camionesylevantesIMFID(instalar_librerias = TRUE)

a <- ver$resumen_pordia_IM
b <- ver$resumen_pordiaymunicipio_IM
c <- ver$resumen_pordia_municipio_turno_completoconceros_IM

a <- inf_deldia$im
b <- inf_deldia$fideicomiso


file.exists("vistas/generar_pdfs.py")
