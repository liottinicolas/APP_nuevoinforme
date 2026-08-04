# Genera un informe HTML standalone (mapa + tabla) de peores contenedores
# a partir del mismo cálculo de PorcentajeLlenado.R.
# Ver documentacion_analisis_peores_contenedores.md para el detalle metodológico.

library(dplyr)
library(sf)
library(jsonlite)

ruta_historico <- file.path("db", "GOL_reportes", "historico_llenadoGol.rds")
df <- readRDS(ruta_historico)

municipio_filtro <- "B"
ventana_dias <- 30

fecha_max <- max(df$Fecha, na.rm = TRUE)
fecha_min <- fecha_max - (ventana_dias - 1)

sub <- df %>%
  filter(Municipio == municipio_filtro, Fecha >= fecha_min, Fecha <= fecha_max)

recolecciones <- sub %>%
  filter(Levantado == "S", !is.na(Porcentaje_llenado))

# Ubicación (dirección, circuito, geometría) más reciente por contenedor
ref_ubicacion <- sub %>%
  arrange(gid, desc(Fecha)) %>%
  distinct(gid, .keep_all = TRUE) %>%
  select(gid, Direccion, Circuito_corto, the_geom)

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
    frecuencia_dias = ifelse(n_recolecciones > 1, dias_cubiertos / (n_recolecciones - 1), NA_real_)
  )

minimo_recolecciones <- 3
resumen_confiable <- resumen %>%
  filter(n_recolecciones >= minimo_recolecciones, !is.na(frecuencia_dias))

mediana_saturacion <- median(resumen_confiable$tasa_saturacion)
mediana_frecuencia <- median(resumen_confiable$frecuencia_dias)

resultado <- resumen_confiable %>%
  mutate(
    saturacion_alta = tasa_saturacion >= mediana_saturacion,
    frecuencia_alta = frecuencia_dias <= mediana_frecuencia,
    en_riesgo = saturacion_alta  # mismo criterio que "cuadrante != OK" en PorcentajeLlenado.R
  ) %>%
  left_join(ref_ubicacion, by = "gid")

# --- Transformar geometrías WKT (EPSG:32721) a lat/lon (EPSG:4326) ---
# mismo criterio que vistas/App_informe_llenado/App.R::preprocesar_datos()
geo_sf <- st_as_sf(resultado, wkt = "the_geom", crs = 32721) %>% st_transform(4326)
coords <- st_coordinates(geo_sf)
resultado$lon <- coords[, 1]
resultado$lat <- coords[, 2]

cat("Contenedores evaluados:", nrow(resultado), "\n")
cat("Contenedores en riesgo (para la tabla):", sum(resultado$en_riesgo), "\n")

# --- Datos para el mapa: TODOS los contenedores evaluados ---
mapa_data <- resultado %>%
  transmute(
    gid, lat, lon,
    direccion = Direccion,
    circuito = Circuito_corto,
    n_recolecciones,
    n_saturaciones,
    tasa_saturacion = round(tasa_saturacion, 4),
    llenado_promedio = round(llenado_promedio, 1),
    frecuencia_dias = round(frecuencia_dias, 2)
  ) %>%
  filter(!is.na(lat), !is.na(lon))

# --- Datos para la tabla: solo los contenedores en riesgo, sin la columna cuadrante ---
tabla_data <- resultado %>%
  filter(en_riesgo) %>%
  arrange(desc(tasa_saturacion), frecuencia_dias) %>%
  transmute(
    gid,
    direccion = Direccion,
    circuito = Circuito_corto,
    n_recolecciones,
    n_saturaciones,
    tasa_saturacion = round(tasa_saturacion, 4),
    llenado_promedio = round(llenado_promedio, 1),
    frecuencia_dias = round(frecuencia_dias, 2)
  )

json_mapa <- toJSON(mapa_data, dataframe = "rows", na = "null")
json_tabla <- toJSON(tabla_data, dataframe = "rows", na = "null")

cat("Contenedores con coordenadas validas para el mapa:", nrow(mapa_data), "\n")
cat("Filas en la tabla:", nrow(tabla_data), "\n")

# Guarda los objetos intermedios para poder generar el HTML en un paso aparte
saveRDS(list(json_mapa = json_mapa, json_tabla = json_tabla,
             fecha_min = fecha_min, fecha_max = fecha_max,
             municipio = municipio_filtro,
             n_evaluados = nrow(resultado), n_riesgo = sum(resultado$en_riesgo),
             mediana_saturacion = mediana_saturacion, mediana_frecuencia = mediana_frecuencia),
        "informes/Porcentaje_llenado_peorescasos/datos_informe_html.rds")
