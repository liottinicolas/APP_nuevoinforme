library(readxl)
library(dplyr)
library(lubridate)

xlsx_path <- "c:/Users/im4445285/OneDrive/Trabajo IM/APP_nuevoinforme/informes/planificados/planificacion.xlsx"

# Load base template
base_template <- read_excel(xlsx_path, sheet = "PLANIFICACION", range = cell_cols("A:L"))
colnames(base_template) <- trimws(colnames(base_template))

base_template <- base_template %>%
  select(DIA, NOMBREDIA, Frecuencia, Periodo, ID_TURNO, MUNICIPIO, CIRCUITO, GRUPO) %>%
  filter(!is.na(DIA)) %>%
  mutate(
    DIA = as.Date(DIA),
    CIRCUITO = as.character(CIRCUITO),
    ID_TURNO = as.numeric(ID_TURNO)
  )

base_date <- as.Date("2024-10-28")

generar_planificados_vectorizado <- function(fecha_inicio, fecha_fin) {
  # 1. Crear un dataframe con la secuencia de fechas
  df_fechas <- data.frame(
    Fecha_Real = seq(as.Date(fecha_inicio), as.Date(fecha_fin), by = "days")
  )
  
  # 2. Calcular la fecha correspondiente en la plantilla de 6 semanas (42 días)
  df_fechas <- df_fechas %>%
    mutate(
      diff_days = as.numeric(Fecha_Real - base_date),
      offset_template = diff_days %% 42,
      Fecha_Plantilla = base_date + offset_template
    )
  
  # 3. Hacer left_join con la plantilla y reestructurar
  df_plan_completo <- df_fechas %>%
    left_join(base_template, by = c("Fecha_Plantilla" = "DIA")) %>%
    mutate(
      DIA = Fecha_Real,
      NOMBREDIA = format(Fecha_Real, "%A")
    ) %>%
    select(DIA, NOMBREDIA, Frecuencia, Periodo, ID_TURNO, MUNICIPIO, CIRCUITO, GRUPO)
  
  return(df_plan_completo)
}

# Test vectorised version
cat("Testing vectorized version for 2025-01-20 to 2025-01-22:\n")
df_generated <- generar_planificados_vectorizado("2025-01-20", "2025-01-22")
print(head(df_generated, 15))
cat("\nTotal rows generated:", nrow(df_generated), "\n")

