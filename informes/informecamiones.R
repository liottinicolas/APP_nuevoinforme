# Cargar librerías necesarias
library(dplyr)
library(lubridate)
library(writexl)

# Ajustá esta ruta de ser necesario según dónde esté guardado el archivo en tu máquina.
ruta_historico <- file.path("db", "GOL_reportes", "historico_llenadoGol.rds")
gol_visitayprogramado_completo <- readRDS(ruta_historico)


# me cuenta los viajes y los agrupa por
# total
# solo IM
# solo por FID
funcion_contar_viajes_por_diayturno <- function(df_llenado) {
  
  # 1. Filtros comunes para todos los reportes
  df_base <- df_llenado %>% 
    filter(Fecha > "2026-01-01") %>% 
    filter(Levantado == "S")
  
  # --- 2. Reporte Solo IM ---
  df_im <- df_base %>% 
    filter(Oficina == "IM") %>% 
    group_by(Fecha, Turno_levantado) %>% 
    summarise(Camiones = n_distinct(Id_viaje_GOL), .groups = "drop")
  
  # --- 3. Reporte Solo Fideicomiso ---
  # Asegúrate de que "FIDEICOMISO" sea el nombre exacto en tu columna Oficina
  df_fideicomiso <- df_base %>% 
    filter(Oficina == "Fideicomiso") %>% 
    group_by(Fecha, Turno_levantado) %>% 
    summarise(Camiones = n_distinct(Id_viaje_GOL), .groups = "drop")
  
  # --- 4. Reporte General (Todas las oficinas) ---
  df_todas <- df_base %>% 
    group_by(Fecha, Turno_levantado) %>% 
    summarise(Camiones = n_distinct(Id_viaje_GOL), .groups = "drop")
  
  # Retornar los tres en la lista
  return(list(
    solo_im = df_im,
    solo_fideicomiso = df_fideicomiso,
    todas_oficinas = df_todas
  ))
}

total_viajes <- funcion_contar_viajes_por_diayturno(gol_visitayprogramado_completo)

viajes_porcamion_soloim <- total_viajes$solo_im
viajes_porcamion_solofideicomiso <- total_viajes$solo_fideicomiso
viajes_porcamion_imyfideicomiso <- total_viajes$todas_oficinas

# Función para aplicar el Criterio de Adrián y guardar el RDS
# El criterio es, Turno nocturno, pasa al día siguiente.
# df_input <- viajes_porcamion_soloim
# nombre_archivo_salida <- "im"
aplicar_criterio_adrian_y_guardar <- function(df_input, nombre_archivo_salida) {
  df_procesado <- df_input %>%
    mutate(
      # 1. Aseguramos que Fecha sea formato Date
      Fecha = as.Date(Fecha),
      
      # 2. Si el turno es Nocturno, sumamos 1 día
      Fecha = if_else(Turno_levantado == "Nocturno", Fecha + days(1), Fecha),
      
      # 3. Actualizamos la columna Dia basándonos en la nueva Fecha
      # label = TRUE devuelve el nombre (lunes, martes...), abbr = FALSE el nombre completo
      Dia = wday(Fecha, label = TRUE, abbr = FALSE)
    ) %>%
    # Opcional: convertir Dia a caracteres simples si no lo quieres como factor ordenado
    mutate(Dia = as.character(Dia))
  
  ruta_destino <- file.path("vistas", "informe_levantes_camiones_porturno_IM_FID","data", nombre_archivo_salida)
  if (!dir.exists(dirname(ruta_destino))) dir.create(dirname(ruta_destino), recursive = TRUE)
  saveRDS(df_procesado, ruta_destino)
  
  return(df_procesado)
}

### APLICAR FUNCIÓN A LOS TRES CASOS ###
total_viajesporcamionsoloim_criterioadrian <- aplicar_criterio_adrian_y_guardar(
  df_input = viajes_porcamion_soloim, 
  nombre_archivo_salida = "total_viajesporcamionsoloim_criterioadrian.rds"
)

total_viajesporcamionsolofid_criterioadrian <- aplicar_criterio_adrian_y_guardar(
  df_input = viajes_porcamion_solofideicomiso, 
  nombre_archivo_salida = "total_viajesporcamionsolofid_criterioadrian.rds"
)

total_viajesporcamionimyfideicomiso_criterioadrian <- aplicar_criterio_adrian_y_guardar(
  df_input = viajes_porcamion_imyfideicomiso, 
  nombre_archivo_salida = "total_viajesporcamionIM_fid_criterioadrian.rds"
)

####

# Ruta carpeta donde están las tablas del nuevo informe diario
ruta_carpeta <- "vistas/informediario/data"

resumen_IM_pordiaymunicipioyturno <- readRDS(file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds"))
resumen_FID_pordiayturno <- readRDS(file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds"))

## IM
informediarionuevo_total_soloim <- resumen_IM_pordiaymunicipioyturno %>% 
  filter(Fecha > "2026-01-01")

# Función para aplicar el Criterio de Adrián a los visitados y guardar
aplicar_criterio_adrian_visitados_y_guardar <- function(df_input, nombre_archivo_salida) {
  # Detectar dinámicamente si la columna es Turno o Turno_levantado
  col_turno <- if ("Turno_levantado" %in% names(df_input)) "Turno_levantado" else "Turno"
  
  df_procesado <- df_input %>%
    mutate(
      # 1. Aseguramos que Fecha sea formato Date
      Fecha = as.Date(Fecha),
      
      # 2. Si el turno es Nocturno, sumamos 1 día
      Fecha = if_else(.data[[col_turno]] == "Nocturno", Fecha + days(1), Fecha),
      
      # 3. Actualizamos la columna Dia basándonos en la nueva Fecha
      # label = TRUE devuelve el nombre (lunes, martes...), abbr = FALSE el nombre completo
      Dia = wday(Fecha, label = TRUE, abbr = FALSE)
    ) %>%
    # Opcional: convertir Dia a caracteres simples si no lo quieres como factor ordenado
    mutate(Dia = as.character(Dia))
  
  ruta_destino <- file.path("vistas", "informe_levantes_camiones_porturno_IM_FID", "data", nombre_archivo_salida)
  if (!dir.exists(dirname(ruta_destino))) dir.create(dirname(ruta_destino), recursive = TRUE)
  saveRDS(df_procesado, ruta_destino)
  
  return(df_procesado)
}

informediarionuevo_total_soloim_criterioadrian <- aplicar_criterio_adrian_visitados_y_guardar(
  df_input = informediarionuevo_total_soloim,
  nombre_archivo_salida = "informediarionuevo_total_soloim_criterioadrian.rds"
)

informediarionuevo_total_imyfideicomiso_2026 <- bind_rows(
  resumen_IM_pordiaymunicipioyturno,
  resumen_FID_pordiayturno
) %>%
  filter(Fecha > "2026-01-01")

informediarionuevo_total_imyfideicomiso_criterioadrian <- aplicar_criterio_adrian_visitados_y_guardar(
  df_input = informediarionuevo_total_imyfideicomiso_2026,
  nombre_archivo_salida = "informediarionuevo_total_imyfideicomiso_criterioadrian.rds"
)


# 2. Cargar la librería
library(writexl)

# 3. Exportar el data frame
# "df" es el nombre de tu objeto en R y "mi_reporte.xlsx" el nombre del archivo
# write.xlsx(prueba_adrian, file = "datos_vaciados_camiones.xlsx", sheetName = "vaciados")




# Creamos una lista con los data frames y los nombres de las hojas
hojas_a_guardar <- list(
  "vaciados_im" = informediarionuevo_total_soloim_criterioadrian,
  "vaciados_imyfideicomiso" = informediarionuevo_total_imyfideicomiso_criterioadrian,
  "resumen_circuitos_im" = total_viajesporcamionsoloim_criterioadrian,
  "resumen_im_y_fideicomiso" = total_viajesporcamionimyfideicomiso_criterioadrian
)


# ruta_destino <- file.path("scripts", "visitados", "viajespordiayturno_imyfideicomiso.rds_criterioadrian.rds")
# saveRDS(total_viajesporcamionimyfideicomiso_criterioadrian, ruta_destino)
# Esto crea un solo Excel con dos pestañas
ruta_destino <- file.path("scripts", "visitados", "datos_vaciados_camiones.xlsx")
if (!dir.exists(dirname(ruta_destino))) dir.create(dirname(ruta_destino), recursive = TRUE)
write.xlsx(hojas_a_guardar, file = ruta_destino)


