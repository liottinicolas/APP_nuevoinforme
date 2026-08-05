# Informe: peores contenedores por saturación (Porcentaje_llenado == 100)
# ajustada por frecuencia de recolección efectiva.
# Ver informes/documentacion_analisis_peores_contenedores.md para contexto de negocio,
# diccionario de datos y decisiones metodológicas.

library(dplyr)
library(writexl)

# ── Peores contenedores por saturación ────────────────────────────────────────
#
# Calcula, para el subconjunto de datos que resulte de combinar los filtros
# pedidos (municipio, circuito, contenedores puntuales y/o período de fechas),
# la tasa de saturación y frecuencia efectiva de recolección por contenedor
# (gid), clasifica cada uno en un cuadrante (subdimensionado / aumentar
# frecuencia / OK) y exporta el resultado a Excel. Mantiene la metodología
# documentada en documentacion_analisis_peores_contenedores.md (recolección
# efectiva = Levantado == "S", saturación = Porcentaje_llenado == 100,
# cuadrante por mediana de la muestra analizada).
#
# El Excel exportado trae primero, si corresponde, una hoja "cruda" (todas las
# columnas del histórico, sin agregar) por cada filtro de recorte que se haya
# pedido (municipio, circuito, gids) por separado — para poder revisar cada
# criterio de forma independiente antes de ver el análisis combinado — y luego
# las hojas de siempre (Peores contenedores / Todos los contenedores / Resumen
# por cuadrante), calculadas sobre el cruce de TODOS los filtros pedidos.
#
# Parámetros:
#   municipio             - vector opcional de municipios a incluir (columna
#                            Municipio), ej. "B" o c("B", "C"). NULL = todos.
#   circuito              - vector opcional de circuitos a incluir (columna
#                            Circuito_corto), ej. "B_01". NULL = todos.
#   gids                  - vector opcional de gid puntuales a analizar.
#                            NULL = todos los gid del subconjunto filtrado.
#   fecha_inicio          - fecha "YYYY-MM-DD" del período a analizar.
#   fecha_fin             - fecha "YYYY-MM-DD" del período a analizar.
#                            Si se pasa solo una de las dos, la otra punta se
#                            completa con ventana_dias (ej. fecha_inicio sin
#                            fecha_fin = esa fecha + ventana_dias). Si no se
#                            pasa ninguna, por defecto trae los últimos
#                            ventana_dias (30 por defecto) desde la última
#                            fecha disponible en la data.
#   ventana_dias          - tamaño de la ventana en días cuando no se pasan
#                            fecha_inicio y fecha_fin completas. Default 30.
#   minimo_recolecciones  - mínimo de recolecciones efectivas en el período
#                            para incluir un contenedor en el ranking/cuadrante
#                            (evita ranquear con 1-2 datos sueltos).
#   df                    - data.frame opcional ya cargado. Si es NULL, se lee
#                            db/GOL_reportes/historico_llenadoGol.rds.
#   ruta_salida           - ruta .xlsx opcional. Si es NULL, se genera
#                            automáticamente a partir de los filtros usados,
#                            dentro de informes/salidas/.
#   exportar_html         - si TRUE, además del Excel genera el informe HTML
#                            standalone (mapa Leaflet + tabla de riesgo), igual
#                            al que arman generar_informe_html.R + armar_html.R,
#                            pero respetando los filtros de esta llamada.
#                            Default FALSE (no se genera a menos que se pida).
#
# Devuelve (invisible) una lista con $resultado, $peores_contenedores,
# $resumen_cuadrantes, $crudo_municipio/$crudo_circuito/$crudo_gids (NULL si
# ese filtro no se pidió), $datos_filtrados (crudo con todos los filtros
# combinados, sin agregar) y $descripcion_filtros. Esta lista es el input de
# generar_pdf_contenedores() (ver generar_pdf_contenedores.R).
#
# Uso:
#   analizar_peores_contenedores(municipio = "B")                       # ventana default de 30 días
#   analizar_peores_contenedores(municipio = "C")
#   analizar_peores_contenedores(circuito = "B_01")
#   analizar_peores_contenedores(gids = c("181516", "123456", "789012"))
#   analizar_peores_contenedores(municipio = "B", fecha_inicio = "2026-07-01", fecha_fin = "2026-07-15")
#   analizar_peores_contenedores(municipio = "B", exportar_html = TRUE)  # también genera el HTML
analizar_peores_contenedores <- function(
    municipio = NULL,
    circuito = NULL,
    gids = NULL,
    fecha_inicio = NULL,
    fecha_fin = NULL,
    ventana_dias = 30,
    minimo_recolecciones = 3,
    df = NULL,
    ruta_salida = NULL,
    exportar_html = FALSE) {
  # 1. Cargar datos si no se pasó un df ya cargado
  if (is.null(df)) {
    df <- readRDS(file.path("db", "GOL_reportes", "historico_llenadoGol.rds"))
  }

  # 2. Determinar ventana de fechas. Por defecto siempre queda una ventana de
  #    ventana_dias (30 por defecto), sin importar cuántas puntas de fecha se
  #    hayan pasado explícitamente:
  #    - Ninguna fecha pasada: últimos ventana_dias desde la última fecha del dataset.
  #    - Solo fecha_inicio: ventana_dias a partir de esa fecha.
  #    - Solo fecha_fin: ventana_dias terminando en esa fecha.
  #    - Ambas: rango explícito (ventana_dias se ignora).
  if (!is.null(fecha_inicio) && !is.null(fecha_fin)) {
    fecha_min <- as.Date(fecha_inicio)
    fecha_max <- as.Date(fecha_fin)
  } else if (!is.null(fecha_inicio)) {
    fecha_min <- as.Date(fecha_inicio)
    fecha_max <- fecha_min + (ventana_dias - 1)
  } else if (!is.null(fecha_fin)) {
    fecha_max <- as.Date(fecha_fin)
    fecha_min <- fecha_max - (ventana_dias - 1)
  } else {
    fecha_max <- max(df$Fecha, na.rm = TRUE) # ancla: última fecha disponible en la data
    fecha_min <- fecha_max - (ventana_dias - 1)
  }

  # --- Filtro base de ventana de fechas, usado también para las tablas crudas ---
  en_ventana <- df %>% filter(Fecha >= fecha_min, Fecha <= fecha_max)

  # --- Tablas crudas: una por cada filtro de recorte pedido, cada una
  #     independiente de los demás filtros (todas las columnas del histórico,
  #     sin agregar), acotadas a la ventana de fechas ---
  crudo_municipio <- if (!is.null(municipio)) en_ventana %>% filter(Municipio %in% municipio) else NULL
  crudo_circuito <- if (!is.null(circuito)) en_ventana %>% filter(Circuito_corto %in% circuito) else NULL
  crudo_gids <- if (!is.null(gids)) en_ventana %>% filter(gid %in% gids) else NULL

  # --- Filtro combinado: fechas + municipio/circuito/gids opcionales (AND entre los que se pasen) ---
  sub <- en_ventana
  if (!is.null(municipio)) sub <- sub %>% filter(Municipio %in% municipio)
  if (!is.null(circuito)) sub <- sub %>% filter(Circuito_corto %in% circuito)
  if (!is.null(gids)) sub <- sub %>% filter(gid %in% gids)

  # --- Recolección efectiva: solo Levantado == "S" (criterio acordado) ---
  recolecciones <- sub %>%
    filter(Levantado == "S", !is.na(Porcentaje_llenado))

  # Dirección/circuito/geometría más reciente por contenedor (gid), para
  # identificar filas en el informe (the_geom se usa solo si exportar_html = TRUE)
  ref_ubicacion <- sub %>%
    arrange(gid, desc(Fecha)) %>%
    distinct(gid, .keep_all = TRUE) %>%
    select(gid, Direccion, Circuito_corto, the_geom)

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

  # Filtro de confiabilidad: exigimos un mínimo de recolecciones efectivas en la ventana
  # para poder calcular una frecuencia representativa (evita ranquear con 1-2 datos sueltos)
  resumen_confiable <- resumen %>%
    filter(n_recolecciones >= minimo_recolecciones, !is.na(frecuencia_dias))

  # --- Cuadrante saturación x frecuencia (umbral = mediana de cada eje) ---
  mediana_saturacion <- median(resumen_confiable$tasa_saturacion)
  mediana_frecuencia <- median(resumen_confiable$frecuencia_dias)

  # resultado_completo conserva the_geom y saturacion_alta (necesarios solo
  # para el HTML); resultado (más abajo) es la versión recortada para Excel.
  resultado_completo <- resumen_confiable %>%
    mutate(
      saturacion_alta = tasa_saturacion >= mediana_saturacion,
      frecuencia_alta = frecuencia_dias <= mediana_frecuencia, # recolectado seguido = intervalo corto
      cuadrante = case_when(
        saturacion_alta & frecuencia_alta ~ "Subdimensionado (satura pese a recolección frecuente)",
        saturacion_alta & !frecuencia_alta ~ "Aumentar frecuencia resolvería",
        TRUE ~ "OK / bajo riesgo"
      )
    ) %>%
    left_join(ref_ubicacion, by = "gid") %>%
    # el ranking de "peores" se ordena por severidad real (tasa de saturación);
    # el cuadrante queda como columna de contexto/acción, no como criterio de orden
    arrange(desc(tasa_saturacion), frecuencia_dias)

  resultado <- resultado_completo %>%
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

  # --- Armar descripción de los filtros aplicados, para mensajes y nombre de archivo ---
  partes_nombre <- c()
  if (!is.null(municipio)) partes_nombre <- c(partes_nombre, paste0("Municipio-", paste(municipio, collapse = "-")))
  if (!is.null(circuito)) partes_nombre <- c(partes_nombre, paste0("Circuito-", paste(circuito, collapse = "-")))
  if (!is.null(gids)) partes_nombre <- c(partes_nombre, paste0("Gids-", length(gids)))
  if (!is.null(fecha_inicio) || !is.null(fecha_fin)) {
    partes_nombre <- c(partes_nombre, paste0(fecha_min, "_a_", fecha_max))
  }
  if (length(partes_nombre) == 0) partes_nombre <- "Todos"
  descripcion_filtros <- paste(partes_nombre, collapse = "_")

  cat("Ventana analizada:", as.character(fecha_min), "a", as.character(fecha_max), "\n")
  cat("Filtros:", descripcion_filtros, "\n")
  cat("Contenedores evaluados (>=", minimo_recolecciones, "recolecciones efectivas):", nrow(resultado), "\n")
  cat("Contenedores en riesgo (saturación alta):", nrow(peores_contenedores), "\n")

  # --- Exportar informe a Excel: primero las hojas crudas por filtro (si hay), luego el análisis ---
  if (is.null(ruta_salida)) {
    dir.create("informes/salidas", showWarnings = FALSE)
    ruta_salida <- file.path("informes/salidas", paste0("peores_contenedores_", descripcion_filtros, ".xlsx"))
  }

  hojas <- list()
  if (!is.null(crudo_municipio)) hojas[["Crudo - Municipio"]] <- crudo_municipio
  if (!is.null(crudo_circuito)) hojas[["Crudo - Circuito"]] <- crudo_circuito
  if (!is.null(crudo_gids)) hojas[["Crudo - Gids"]] <- crudo_gids
  hojas[["Peores contenedores"]] <- peores_contenedores
  hojas[["Todos los contenedores"]] <- resultado
  hojas[["Resumen por cuadrante"]] <- resumen_cuadrantes

  write_xlsx(hojas, path = ruta_salida)
  cat("Exportado a:", ruta_salida, "\n")

  # --- Exportar informe HTML (mapa + tabla), solo si se pidió explícitamente ---
  if (exportar_html) {
    library(sf)
    library(jsonlite)

    geo_sf <- st_as_sf(resultado_completo, wkt = "the_geom", crs = 32721) %>% st_transform(4326)
    coords <- st_coordinates(geo_sf)
    resultado_completo$lon <- coords[, 1]
    resultado_completo$lat <- coords[, 2]

    mapa_data <- resultado_completo %>%
      transmute(
        gid, lat, lon,
        direccion = Direccion,
        circuito = Circuito_corto,
        n_recolecciones, n_saturaciones,
        tasa_saturacion = round(tasa_saturacion, 4),
        llenado_promedio = round(llenado_promedio, 1),
        frecuencia_dias = round(frecuencia_dias, 2)
      ) %>%
      filter(!is.na(lat), !is.na(lon))

    tabla_data <- resultado_completo %>%
      filter(cuadrante != "OK / bajo riesgo") %>%
      arrange(desc(tasa_saturacion), frecuencia_dias) %>%
      transmute(
        gid,
        direccion = Direccion,
        circuito = Circuito_corto,
        n_recolecciones, n_saturaciones,
        tasa_saturacion = round(tasa_saturacion, 4),
        llenado_promedio = round(llenado_promedio, 1),
        frecuencia_dias = round(frecuencia_dias, 2)
      )

    json_mapa <- jsonlite::toJSON(mapa_data, dataframe = "rows", na = "null")
    json_tabla <- jsonlite::toJSON(tabla_data, dataframe = "rows", na = "null")

    tpl <- readLines("informes/Porcentaje_llenado_peorescasos/informe_template.html", warn = FALSE)
    tpl <- paste(tpl, collapse = "\n")

    # Leaflet embebido localmente (informes/_vendor/leaflet/) en vez de CDN,
    # porque el CDN queda bloqueado por políticas de red/CSP del usuario.
    leaflet_css <- paste(readLines("informes/_vendor/leaflet/leaflet.css", warn = FALSE), collapse = "\n")
    leaflet_js <- paste(readLines("informes/_vendor/leaflet/leaflet.js", warn = FALSE), collapse = "\n")

    reemplazos <- list(
      "__FILTROS__" = descripcion_filtros,
      "__FECHA_MIN__" = as.character(fecha_min),
      "__FECHA_MAX__" = as.character(fecha_max),
      "__N_EVALUADOS__" = as.character(nrow(resultado)),
      "__MIN_RECOLECCIONES__" = as.character(minimo_recolecciones),
      "__SLUG__" = descripcion_filtros,
      "__LEAFLET_CSS__" = leaflet_css,
      "__LEAFLET_JS__" = leaflet_js,
      "__JSON_MAPA__" = json_mapa,
      "__JSON_TABLA__" = json_tabla
    )

    for (marcador in names(reemplazos)) {
      tpl <- gsub(marcador, reemplazos[[marcador]], tpl, fixed = TRUE)
    }

    ruta_html <- file.path("informes/Porcentaje_llenado_peorescasos", paste0("informe_", descripcion_filtros, ".html"))
    writeLines(tpl, ruta_html, useBytes = TRUE)
    cat("HTML exportado a:", ruta_html, "\n")
  }

  invisible(list(
    resultado = resultado,
    peores_contenedores = peores_contenedores,
    resumen_cuadrantes = resumen_cuadrantes,
    crudo_municipio = crudo_municipio,
    crudo_circuito = crudo_circuito,
    crudo_gids = crudo_gids,
    datos_filtrados = sub, # subconjunto crudo con TODOS los filtros combinados (input de generar_pdf_contenedores())
    descripcion_filtros = descripcion_filtros
  ))
}

# --- Ejecución: comportamiento original (Municipio B, ventana default de 30 días) ---
# analizar_peores_contenedores(municipio = "B")

# Otros ejemplos de uso:
# analizar_peores_contenedores(municipio = "C")
# analizar_peores_contenedores(circuito = "B_01")
# analizar_peores_contenedores(gids = c("181516", "123456", "789012"))
# analizar_peores_contenedores(municipio = "B", fecha_inicio = "2026-07-01", fecha_fin = "2026-07-15")
# analizar_peores_contenedores(municipio = "B", exportar_html = TRUE)


ver <- analizar_peores_contenedores(gids = c("184421", "184471", "107365"), exportar_html = TRUE)