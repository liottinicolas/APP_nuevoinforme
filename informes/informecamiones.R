# Cargar librerías necesarias
library(dplyr)
library(lubridate)
library(writexl)

# Ajustá esta ruta de ser necesario según dónde esté guardado el archivo en tu máquina.
ruta_historico <- file.path("informediario", "data", "historico_llenadoGol.rds")
gol_visitayprogramado_completo <- readRDS(ruta_historico)

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

### ACA EL CRITERIO ES QUE SE TOMA 1er turno dia anterior, matutino y vespertino del día siguiente.
total_viajesporcamionsoloim_criterioadrian <- viajes_porcamion_soloim %>%
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

ruta_destino <- file.path("scripts", "visitados", "total_viajesporcamionsoloim_criterioadrian.rds")
saveRDS(total_viajesporcamionsoloim_criterioadrian, ruta_destino)


### ACA EL CRITERIO ES QUE SE TOMA 1er turno dia anterior, matutino y vespertino del día siguiente.
total_viajesporcamionimyfideicomiso_criterioadrian <- viajes_porcamion_imyfideicomiso %>%
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

ruta_destino <- file.path("scripts", "visitados", "viajespordiayturno_imyfideicomiso.rds_criterioadrian.rds")
saveRDS(total_viajesporcamionimyfideicomiso_criterioadrian, ruta_destino)

####

informediarionuevo_total <- funcion_df_nuevoinformediario_porturnos(gol_visitayprogramado_completo)
informediarionuevo_total_soloim <- informediarionuevo_total$solo_im
informediarionuevo_total_solofideicomiso <- informediarionuevo_total$solo_fideicomiso
informediarionuevo_total_imyfideicomiso <- informediarionuevo_total$todas_oficinas

# filtro a partir de enero 2026
informediarionuevo_total_soloim_2026 <- informediarionuevo_total_soloim %>% 
  filter(Fecha > "2026-01-01")
informediarionuevo_total_imyfideicomiso_2026 <- informediarionuevo_total_imyfideicomiso %>% 
  filter(Fecha > "2026-01-01")

informediarionuevo_total_soloim_criterioadrian <- informediarionuevo_total_soloim_2026 %>%
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

 ruta_destino <- file.path("scripts", "visitados", "informediarionuevo_total_soloim_criterioadrian.rds")
 saveRDS(informediarionuevo_total_soloim_criterioadrian, ruta_destino)

informediarionuevo_total_imyfideicomiso_criterioadrian <- informediarionuevo_total_imyfideicomiso_2026 %>%
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

ruta_destino <- file.path("scripts", "visitados", "informediarionuevo_total_imyfideicomiso_criterioadrian.rds")
saveRDS(informediarionuevo_total_imyfideicomiso_criterioadrian, ruta_destino)


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
write.xlsx(hojas_a_guardar, file = ruta_destino)




######

promedios_mensuales_concap <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
# 1. Contamos cuántas filas (incidencias) hay en cada día
count(Fecha, name = "total_del_dia") %>%
  # 2. Agrupamos esos totales por mes
  group_by(Mes = floor_date(Fecha, "month")) %>%
  # 3. Calculamos el promedio de esos totales diarios
  summarise(promedio_diario_mensual = mean(total_del_dia, na.rm = TRUE))

promedios_mensuales_concap_porturnos <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
  # PASO 1: Contamos cuántas filas hay en cada combinación de día y turno
  # Esto genera una columna 'n' con el total de ese día/turno
  count(Fecha, Turno_levantado) %>%
  
  # PASO 2: Ahora sí, agrupamos por Mes y Turno al mismo tiempo
  # floor_date convierte "2026-01-15" en "2026-01-01"
  group_by(Mes = floor_date(Fecha, "month"), Turno_levantado) %>%
  
  # PASO 3: Calculamos el promedio de esos conteos diarios
  summarise(
    promedio_diario_mensual = mean(n, na.rm = TRUE),
    total_filas_mes = sum(n), # Opcional: total de filas en todo el mes
    .groups = "drop"
  )

promedios_mensuales_sincap <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
  filter(Oficina == "IM") %>% 
  # 1. Contamos cuántas filas (incidencias) hay en cada día
  count(Fecha, name = "total_del_dia") %>%
  # 2. Agrupamos esos totales por mes
  group_by(Mes = floor_date(Fecha, "month")) %>%
  # 3. Calculamos el promedio de esos totales diarios
  summarise(promedio_diario_mensual = mean(total_del_dia, na.rm = TRUE))

promedios_mensuales_sincap_porturnos <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
  filter(Oficina == "IM") %>% 
  # PASO 1: Contamos cuántas filas hay en cada combinación de día y turno
  # Esto genera una columna 'n' con el total de ese día/turno
  count(Fecha, Turno_levantado) %>%
  
  # PASO 2: Ahora sí, agrupamos por Mes y Turno al mismo tiempo
  # floor_date convierte "2026-01-15" en "2026-01-01"
  group_by(Mes = floor_date(Fecha, "month"), Turno_levantado) %>%
  
  # PASO 3: Calculamos el promedio de esos conteos diarios
  summarise(
    promedio_diario_mensual = mean(n, na.rm = TRUE),
    total_filas_mes = sum(n), # Opcional: total de filas en todo el mes
    .groups = "drop"
  )


### Ahora agrupar por viaje por turno

ver <- gol_visitayprogramado_completo %>% 
  filter(Levantado == "S") %>% 
  filter(Oficina == "IM") %>% 
  group_by(Fecha,Turno_levantado,Id_viaje_GOL) %>% 
  summarise(total = n()) %>% 
  filter(Fecha > "2026-01-01")




ubicaciones <- historico_ubicaciones %>% 
  filter(Fecha == "2026-02-01")

dfr <- historico_DFR_ubicaciones %>% 
  filter(Fecha == "2026-02-01")








resumen_cambios_reales <- historico_DFR_ubicaciones %>%
  # Seleccionamos las columnas que definen un cambio real
  distinct(gid, Circuito, Posicion, Estado, Direccion_dfr, .keep_all = FALSE) %>%
  group_by(gid) %>%
  summarise(cambios_detectados = n() - 1)
