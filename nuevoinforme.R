source("global.R")
source("cargaDeDatos.R")

source("informes/informe_diario.R")
source("informes/informecamiones.R")

# dia sobre informe, debe ser el mismo día que se solicita (como al finalizar turno nocturno.)
# inf_deldia <- generar_reporte_dia("2026-02-17",historico_ubicaciones, historico_llenado)

# historico_llenadoGol <- readRDS("C:/Users/nico9/Downloads/APP_nuevoinforme/db/GOL_reportes/historico_llenadoGol.rds")
### Cargar funciones útiles
source("funciones_utiles.R")

# Para actualizar los datos a GitHub, ejecutá:
# actualizar_github_datos(data_dir = "vistas/")


## pruebo hacer el pdf
generar_reporte_pdf_camionesylevantesIMFID(fecha = "2026-02-17", instalar_librerias = FALSE)
generar_reporte_pdf_camionesylevantesIMFID(fecha = NULL, instalar_librerias = FALSE)

generar_reporte_pdf_informediario(fecha = "2026-02-17", instalar_librerias = FALSE)
generar_reporte_pdf_informediario(fecha = NULL, instalar_librerias = FALSE)


a <- ver$resumen_pordia_IM
b <- ver$resumen_pordiaymunicipio_IM
c <- ver$resumen_pordia_municipio_turno_completoconceros_IM

a <- inf_deldia$im
b <- inf_deldia$fideicomiso


# Ejecutar el script de Python para generar el PDF
system2("python", args = "vistas/informe_operativa/informeOP_generar_pdf.py")
