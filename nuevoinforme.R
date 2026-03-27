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
generar_reporte_pdf_camionesylevantesIMFID(fecha = NULL, instalar_librerias = TRUE)

generar_reporte_pdf_informediario(fecha = "2026-02-17", instalar_librerias = FALSE)
generar_reporte_pdf_informediario(fecha = NULL, instalar_librerias = FALSE)


a <- ver$resumen_pordia_IM
b <- ver$resumen_pordiaymunicipio_IM
c <- ver$resumen_pordia_municipio_turno_completoconceros_IM

a <- inf_deldia$im
b <- inf_deldia$fideicomiso


# Ruta al Python del entorno virtual de reticulate
python_venv <- file.path(Sys.getenv("USERPROFILE"), "OneDrive", "Documentos y papeles importantes",
                         ".virtualenvs", "r-reticulate", "Scripts", "python.exe")

# Ejecutar el script de Python para generar el PDF
system2(python_venv, args = "vistas/informe_operativa/informeOP_generar_pdf.py")

# Ejecutar los scripts de Python para el informe diario
system2(python_venv, args = "vistas/informediario/reportes/actualizar_ayer.py")
## Antes de ejecutar para mapas, tiene que actualizar archivo.
system2(python_venv, args = "vistas/informediario/reportes/generar_mapas.py")






ver <- historico_llenado %>% 
  filter(Fecha >= "2026-01-15") %>%
  filter(Fecha <= "2026-02-28") %>%
  filter(Municipio == "B") %>% 
  filter(Condicion %in% c("Basura Afuera", "Escombro", "Poda"))


df_conteo <- ver %>%
  group_by(gid) %>%
  summarise(
    Denuncias = n(),
    Circuito_corto = first(Circuito_corto),
    Posicion = first(Posicion),
    Direccion = first(Direccion),
    the_geom = first(the_geom)
  ) %>%
  arrange(desc(Denuncias)) %>% 
  rename(Circuito = Circuito_corto)

## imprimir excel

df_conteo_imprimir <- df_conteo %>% 
  select(Direccion, Circuito, Posicion, Denuncias, gid) %>%
  head(50)

library(openxlsx)

# 1. Creamos un nuevo libro de Excel
wb <- createWorkbook()

# 2. Añadimos una hoja
addWorksheet(wb, "Reporte_Limpieza")

# 3. Escribimos los datos como una TABLA de Excel
# tableStyle puede ser "TableStyleLight9", "TableStyleMedium2", etc.
writeDataTable(wb, sheet = "Reporte_Limpieza", x = df_conteo_imprimir, 
               startCol = 1, startRow = 1, 
               tableStyle = "TableStyleMedium2",
               withFilter = TRUE)

# 4. Ajustamos el ancho de las columnas automáticamente para que se lea bien
setColWidths(wb, sheet = "Reporte_Limpieza", cols = 1:ncol(df_conteo_imprimir), widths = "auto")

# 5. Guardamos el archivo
saveWorkbook(wb, "Reporte_Puntos_Criticos_IM.xlsx", overwrite = TRUE)

## Cerrar

library(sf)
library(dplyr)

# 1. Tomamos los peores 50 (asegúrate de que df_conteo tenga estas columnas)
peores_50 <- df_conteo %>%
  head(50)

# 2. Convertimos a objeto espacial (Sistema IM)
df_sf <- st_as_sf(peores_50, wkt = "the_geom", crs = 32721) 

# 3. Transformamos a WGS84 y personalizamos los campos KML
df_kml <- st_transform(df_sf, crs = 4326) %>%
  mutate(
    # Name será la combinación de Circuito y Posición
    Name = paste(Circuito, Posicion, sep = " - "),
    
    # Description será la Dirección
    Description = as.character(Direccion),
    
    # Mantenemos el gid original como un atributo de texto para que no se pierda
    gid_attr = as.character(gid) 
  ) %>%
  # Seleccionamos Name, Description y el resto de los atributos
  # Incluimos 'gid_attr' para que aparezca en la tabla de datos del globo
  select(Name, Description, gid = gid_attr, Circuito, Posicion, Denuncias)

# 4. Exportamos a KML
st_write(df_kml, "puntos_criticos_circuito_posicion.kml", driver = "KML", delete_dsn = TRUE)