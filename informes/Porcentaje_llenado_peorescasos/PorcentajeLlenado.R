# Informe: peores contenedores por saturación (Porcentaje_llenado == 100)
# ajustada por frecuencia de recolección efectiva.
# Ver informes/documentacion_analisis_peores_contenedores.md para contexto de negocio,
# diccionario de datos y decisiones metodológicas.

library(dplyr)
library(writexl)

ruta_historico <- file.path("db", "GOL_reportes", "historico_llenadoGol.rds")
df <- readRDS(ruta_historico)

# --- Parámetros del informe ---
municipio_filtro <- "B"
ventana_dias <- 30

fecha_max <- max(df$Fecha, na.rm = TRUE)          # ancla: última fecha disponible en la data
fecha_min <- fecha_max - (ventana_dias - 1)

# --- Filtro base: Municipio + ventana de tiempo ---
sub <- df %>%
  filter(Municipio == municipio_filtro, Fecha >= fecha_min, Fecha <= fecha_max)

# --- Recolección efectiva: solo Levantado == "S" (criterio acordado) ---
recolecciones <- sub %>%
  filter(Levantado == "S", !is.na(Porcentaje_llenado))

# Dirección/circuito más reciente por contenedor (gid), para identificar filas en el informe
ref_ubicacion <- sub %>%
  arrange(gid, desc(Fecha)) %>%
  distinct(gid, .keep_all = TRUE) %>%
  select(gid, Direccion, Circuito_corto)

# --- Métricas por contenedor (gid) ---
resumen <- recolecciones %>%
  group_by(gid) %>%
  summarise(
    n_recolecciones = n(),
    n_saturaciones = sum(Porcentaje_llenado == 100),
    tasa_saturacion = n_saturaciones / n_recolecciones,
    llenado_promedio = mean(Porcentaje_llenado),
    primera_fecha = min(Fecha),
    ultima_fecha = max(Fecha),
    .groups = "drop"
  ) %>%
  mutate(
    dias_cubiertos = as.numeric(ultima_fecha - primera_fecha),
    # promedio de días entre recolecciones efectivas (frecuencia real, no la planificada)
    frecuencia_dias = ifelse(n_recolecciones > 1, dias_cubiertos / (n_recolecciones - 1), NA_real_)
  )

# Filtro de confiabilidad: exigimos al menos 3 recolecciones efectivas en la ventana
# para poder calcular una frecuencia representativa (evita ranquear con 1-2 datos sueltos)
minimo_recolecciones <- 3
resumen_confiable <- resumen %>%
  filter(n_recolecciones >= minimo_recolecciones, !is.na(frecuencia_dias))

# --- Cuadrante saturación x frecuencia (umbral = mediana de cada eje) ---
mediana_saturacion <- median(resumen_confiable$tasa_saturacion)
mediana_frecuencia <- median(resumen_confiable$frecuencia_dias)

resultado <- resumen_confiable %>%
  mutate(
    saturacion_alta = tasa_saturacion >= mediana_saturacion,
    frecuencia_alta = frecuencia_dias <= mediana_frecuencia,  # recolectado seguido = intervalo corto
    cuadrante = case_when(
      saturacion_alta & frecuencia_alta ~ "Subdimensionado (satura pese a recolección frecuente)",
      saturacion_alta & !frecuencia_alta ~ "Aumentar frecuencia resolvería",
      TRUE ~ "OK / bajo riesgo"
    )
  ) %>%
  left_join(ref_ubicacion, by = "gid") %>%
  # el ranking de "peores" se ordena por severidad real (tasa de saturación);
  # el cuadrante queda como columna de contexto/acción, no como criterio de orden
  arrange(desc(tasa_saturacion), frecuencia_dias) %>%
  select(
    gid, Direccion, Circuito_corto,
    n_recolecciones, n_saturaciones, tasa_saturacion, llenado_promedio,
    frecuencia_dias, cuadrante
  )

peores_contenedores <- resultado %>% filter(cuadrante != "OK / bajo riesgo")

resumen_cuadrantes <- resultado %>%
  group_by(cuadrante) %>%
  summarise(
    contenedores = n(),
    tasa_saturacion_promedio = mean(tasa_saturacion),
    frecuencia_promedio_dias = mean(frecuencia_dias),
    .groups = "drop"
  )

cat("Ventana analizada:", as.character(fecha_min), "a", as.character(fecha_max), "\n")
cat("Municipio:", municipio_filtro, "\n")
cat("Contenedores evaluados (>=", minimo_recolecciones, "recolecciones efectivas):", nrow(resultado), "\n")
cat("Contenedores en riesgo (saturación alta):", nrow(peores_contenedores), "\n")

# --- Exportar informe a Excel ---
dir.create("informes/salidas", showWarnings = FALSE)
write_xlsx(
  list(
    "Peores contenedores" = peores_contenedores,
    "Todos los contenedores" = resultado,
    "Resumen por cuadrante" = resumen_cuadrantes
  ),
  path = "informes/salidas/peores_contenedores_MunicipioB.xlsx"
)
