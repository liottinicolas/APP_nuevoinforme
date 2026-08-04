# Informe: peores contenedores por Condicion ("Basura Afuera" y/o "Requiere Limpieza")
# ajustada por frecuencia de recolección efectiva.
# Ver documentacion_analisis_peores_condicion.md para contexto de negocio,
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
# A diferencia del análisis de saturación, acá NO se filtra por !is.na(Condicion):
# Condicion es un campo de excepción (igual que Incidencia) que solo se completa
# cuando la cuadrilla encuentra algo — NA significa "sin novedad", no dato faltante.
recolecciones <- sub %>%
  filter(Levantado == "S") %>%
  mutate(
    flag_basura_afuera = !is.na(Condicion) & grepl("Basura Afuera", Condicion, fixed = TRUE),
    flag_requiere_limpieza = !is.na(Condicion) & grepl("Requiere Limpieza", Condicion, fixed = TRUE),
    flag_alguna_condicion = flag_basura_afuera | flag_requiere_limpieza
  )

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
    n_basura_afuera = sum(flag_basura_afuera),
    n_requiere_limpieza = sum(flag_requiere_limpieza),
    n_alguna_condicion = sum(flag_alguna_condicion),
    tasa_condicion = n_alguna_condicion / n_recolecciones,
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

# --- Cuadrante tasa de condición x frecuencia (umbral = mediana de cada eje) ---
mediana_condicion <- median(resumen_confiable$tasa_condicion)
mediana_frecuencia <- median(resumen_confiable$frecuencia_dias)

resultado <- resumen_confiable %>%
  mutate(
    condicion_alta = tasa_condicion >= mediana_condicion,
    frecuencia_alta = frecuencia_dias <= mediana_frecuencia,  # recolectado seguido = intervalo corto
    cuadrante = case_when(
      condicion_alta & frecuencia_alta ~ "Persiste pese a recolección frecuente (posible falta de capacidad o causa externa)",
      condicion_alta & !frecuencia_alta ~ "Aumentar frecuencia podría ayudar",
      TRUE ~ "OK / bajo riesgo"
    )
  ) %>%
  left_join(ref_ubicacion, by = "gid") %>%
  # el ranking de "peores" se ordena por severidad real (tasa de condición);
  # el cuadrante queda como columna de contexto/acción, no como criterio de orden
  arrange(desc(tasa_condicion), frecuencia_dias) %>%
  select(
    gid, Direccion, Circuito_corto,
    n_recolecciones, n_basura_afuera, n_requiere_limpieza, n_alguna_condicion, tasa_condicion,
    frecuencia_dias, cuadrante
  )

peores_contenedores <- resultado %>% filter(cuadrante != "OK / bajo riesgo")

resumen_cuadrantes <- resultado %>%
  group_by(cuadrante) %>%
  summarise(
    contenedores = n(),
    tasa_condicion_promedio = mean(tasa_condicion),
    frecuencia_promedio_dias = mean(frecuencia_dias),
    .groups = "drop"
  )

cat("Ventana analizada:", as.character(fecha_min), "a", as.character(fecha_max), "\n")
cat("Municipio:", municipio_filtro, "\n")
cat("Contenedores evaluados (>=", minimo_recolecciones, "recolecciones efectivas):", nrow(resultado), "\n")
cat("Contenedores en riesgo (tasa de condición alta):", nrow(peores_contenedores), "\n")

# --- Exportar informe a Excel ---
dir.create("informes/Condicion_peorescasos/salidas", showWarnings = FALSE)
write_xlsx(
  list(
    "Peores contenedores" = peores_contenedores,
    "Todos los contenedores" = resultado,
    "Resumen por cuadrante" = resumen_cuadrantes
  ),
  path = "informes/Condicion_peorescasos/salidas/peores_condicion_MunicipioB.xlsx"
)
