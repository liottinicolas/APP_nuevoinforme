# ==============================================================================
# Pesadas_Intra.R
# Carga de datos de pesadas e integración con la flota intradomiciliaria
# ==============================================================================

library(dplyr)
library(readr)
library(here)

# 1. Cargar la definición de la flota (df_flota)
#    Sourcing conexionPOSTGRES.R defines df_flota in the global environment
source(here("db/POSTGRES/conexionPOSTGRES.R"))

# Validar que df_flota exista
if (!exists("df_flota")) {
  stop("No se pudo cargar la definición de la flota (df_flota) desde conexionPOSTGRES.R")
}

# 2. Localizar el archivo CSV en la carpeta db/10450_pesadas
dir_pesadas <- here("db", "10450_pesadas")
archivos_csv <- list.files(dir_pesadas, pattern = "\\.csv$", full.names = TRUE)

if (length(archivos_csv) == 0) {
  stop("No se encontró ningún archivo CSV en la carpeta: ", dir_pesadas)
}

# En caso de haber más de un archivo, seleccionamos el más reciente por fecha de modificación
info_archivos <- file.info(archivos_csv)
archivo_pesadas <- archivos_csv[which.max(info_archivos$mtime)]

message("Cargando el archivo de pesadas: ", basename(archivo_pesadas))

# 3. Leer el CSV utilizando tabulación (\t) como delimitador
df_pesadas <- read_delim(
  archivo_pesadas,
  delim = "\t",
  escape_double = FALSE,
  trim_ws = TRUE,
  locale = locale(encoding = "UTF-8"),
  show_col_types = FALSE
)

# 4. Filtrar por matrícula y agregar el servicio
#    - Limpiamos espacios adicionales que puedan venir en la matrícula de ambos DF.
#    - Conservamos únicamente las matrículas que están presentes en df_flota.
#    - Agregamos la columna 'Servicio' correspondiente a cada matrícula.

# Preparar df_flota con selección limpia de matrícula y servicio
df_flota_clean <- df_flota %>%
  select(Matricula, Servicio) %>%
  mutate(Matricula = trimws(Matricula)) %>%
  distinct()

# Circuitos permitidos
circuitos_permitidos <- c(
  "A_DU_M_ST_CERRO_01",
  "A_DU_M_ST_LA_TEJA_01",
  "A_DU_M_ST_LA_TEJA_02",
  "A_DU_M_ST_LA_TEJA_03",
  "A_DU_M_ST_LOSBULEVARES",
  "A_DU_M_ST_NUEVOLLAMA_Y_ANEXO",
  "A_DU_M_ST_SANTIAGOVAZQUEZ",
  "A_DU_R_ST_LOSBULEVARES",
  "A_DU_R_ST_NUEVOLLAMA_Y_ANEXO",
  "A_DU_R_ST_SANTIAGOVAZQUEZ",
  "C_DU_M_ST_CAPURRO_01",
  "C_DU_M_ST_CAPURRO_02",
  "C_DU_M_ST_CAPURRO_03",
  "C_DU_R_ST_CAPURRO_01",
  "C_DU_R_ST_CAPURRO_02",
  "C_DU_R_ST_CAPURRO_03",
  "E_DU_R_ST_CARRASCO_01",
  "G_DU_M_ST_PRADO_01",
  "G_DU_M_ST_ABAYUBA",
  "G_DU_M_ST_SANBARTOLOYANEXO",
  "G_DU_R_ST_ABAYUBA"
)

# Filtrar y enriquecer pesadas
df_pesadas_filtrado <- df_pesadas %>%
  mutate(
    Matricula = trimws(Matricula),
    Nomenclatura_Circuito = trimws(Nomenclatura_Circuito),
    Fecha = as.Date(Fecha, format = "%d/%m/%Y")
  ) %>%
  filter(
    Matricula %in% df_flota_clean$Matricula,
    Nomenclatura_Circuito %in% circuitos_permitidos
  ) %>%
  left_join(df_flota_clean, by = "Matricula")

# 5. Agrupaciones y resúmenes solicitados

# Resumen 1: Por día y tipo de servicio, sumando el total de Peso_Neto
df_resumen_dia_servicio <- df_pesadas_filtrado %>%
  group_by(Fecha, Servicio) %>%
  summarise(Total_Peso_Neto = sum(Peso_Neto, na.rm = TRUE), .groups = "drop")

# Resumen 2: Por día, tipo de servicio y Nomenclatura_Circuito, sumando el Peso_Neto
df_resumen_dia_servicio_circuito <- df_pesadas_filtrado %>%
  group_by(Fecha, Servicio, Nomenclatura_Circuito) %>%
  summarise(Total_Peso_Neto = sum(Peso_Neto, na.rm = TRUE), .groups = "drop")

# Mostrar un resumen informativo en consola
message("✅ Proceso completado exitosamente.")
message("Filas totales en el CSV original: ", nrow(df_pesadas))
message("Filas filtradas que coinciden con la flota: ", nrow(df_pesadas_filtrado))

message("\n--- Resumen 1: Peso Neto por Día y Servicio ---")
print(df_resumen_dia_servicio)

message("\n--- Resumen 2: Peso Neto por Día, Servicio y Circuito (Top 15) ---")
print(head(df_resumen_dia_servicio_circuito, 15))

# 6. Exportación de resultados

library(readODS)
library(openxlsx)

# Crear directorio de salidas si no existe
dir_salidas <- here("salidas")
dir.create(dir_salidas, recursive = TRUE, showWarnings = FALSE)

# --- Opción A: Exportar a ODS (Limpio y estándar) ---
archivo_ods <- here("salidas", "Resumen_Pesadas.ods")

# Si el archivo ya existe, lo eliminamos para generarlo limpio
if (file.exists(archivo_ods)) {
  file.remove(archivo_ods)
}

write_ods(df_resumen_dia_servicio, path = archivo_ods, sheet = "Resumen_Dia_Servicio")
write_ods(df_resumen_dia_servicio_circuito, path = archivo_ods, sheet = "Resumen_Dia_Servicio_Circuito", append = TRUE)

message("\n💾 Archivo ODS generado en: ", archivo_ods)

# --- Opción B: Exportar a Excel (Con formato profesional de celdas, colores y anchos) ---
archivo_xlsx <- here("salidas", "Resumen_Pesadas.xlsx")
wb <- createWorkbook()

# Estilos profesionales
estilo_header <- createStyle(
  fontName = "Arial",
  fontSize = 11,
  textDecoration = "bold",
  fgFill = "#DCE6F1", # Fondo azul suave/gris de cabecera
  halign = "center",
  border = "TopBottomLeftRight"
)

estilo_datos <- createStyle(
  fontName = "Arial",
  fontSize = 10,
  halign = "center",
  border = "TopBottomLeftRight"
)

estilo_numeros <- createStyle(
  fontName = "Arial",
  fontSize = 10,
  halign = "right",
  numFmt = "#,##0", # Formato numérico de miles
  border = "TopBottomLeftRight"
)

# Función para agregar hojas con formato
exportar_hoja_formateada <- function(workbook, nombre_hoja, datos) {
  addWorksheet(workbook, nombre_hoja)
  writeData(workbook, nombre_hoja, datos)
  
  # Estilo de cabecera
  addStyle(workbook, sheet = nombre_hoja, style = estilo_header, 
           rows = 1, cols = 1:ncol(datos), gridExpand = TRUE)
  
  # Estilo de datos generales
  addStyle(workbook, sheet = nombre_hoja, style = estilo_datos, 
           rows = 2:(nrow(datos) + 1), cols = 1:ncol(datos), gridExpand = TRUE)
  
  # Formato numérico para la columna de Peso Neto
  col_num <- which(names(datos) == "Total_Peso_Neto")
  if (length(col_num) > 0) {
    addStyle(workbook, sheet = nombre_hoja, style = estilo_numeros, 
             rows = 2:(nrow(datos) + 1), cols = col_num, gridExpand = TRUE, stack = TRUE)
  }
  
  # Auto-ajuste de columnas
  setColWidths(workbook, sheet = nombre_hoja, cols = 1:ncol(datos), widths = "auto")
}

# Escribir ambas hojas formateadas
exportar_hoja_formateada(wb, "Resumen_Dia_Servicio", df_resumen_dia_servicio)
exportar_hoja_formateada(wb, "Resumen_Dia_Servicio_Circuito", df_resumen_dia_servicio_circuito)

# Guardar libro
saveWorkbook(wb, archivo_xlsx, overwrite = TRUE)
message("💾 Archivo Excel con formato generado en: ", archivo_xlsx)
