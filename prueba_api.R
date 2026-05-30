# =============================================================================
# SCRIPT DE PRUEBA Y DIAGNÓSTICO: API VISOR IMM
# =============================================================================
# Este script sirve para probar de forma aislada y ver el detalle de lo que
# responde la API del visor de la IMM para matrículas específicas.

library(httr2)
library(jsonlite)
library(dplyr)
library(sf)
library(purrr)

# Cargar conexión a Postgres y capa local
source("db/POSTGRES/conexionPOSTGRES.R")
capa_intra <- cargar_capa_local_postgres("Hogares_sustentables")


#' Consulta detallada a la API con logs de depuración completos
#'
#' @param matricula   Matrícula del vehículo (ej: "SIM3127")
#' @param fecha_desde Fecha de inicio (ej: "2026-05-23")
#' @param hora_desde  Hora de inicio (ej: "06:00:00")
#' @param fecha_hasta Fecha de fin (ej: "2026-05-23")
#' @param hora_hasta  Hora de fin (ej: "13:59:59")
#' @param grupo       Grupo de flota (por defecto "sisconve")
#' @param solo_paradas Si es TRUE, solicita showStopsOnly = "true" a la API
#' @return Un sf data frame o NULL con mensajes impresos en consola
probar_conexion_api <- function(matricula,
                                fecha_desde, hora_desde = "00:00:00",
                                fecha_hasta, hora_hasta = "23:59:59",
                                grupo = "sisconve",
                                solo_paradas = FALSE) {
  f_desde <- paste0(as.character(as.Date(fecha_desde)), "T", hora_desde)
  f_hasta <- paste0(as.character(as.Date(fecha_hasta)), "T", hora_hasta)

  base_url <- "https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones"

  cat("\n=======================================================\n")
  cat("🔍 INICIANDO DIAGNÓSTICO DE LA API\n")
  cat("=======================================================\n")
  cat("Matrícula:   ", toupper(matricula), "\n")
  cat("Fecha Desde: ", f_desde, "\n")
  cat("Fecha Hasta: ", f_hasta, "\n")
  cat("Grupo:       ", grupo, "\n")
  cat("Solo Paradas:", solo_paradas, "\n\n")

  # 1. Construir la petición
  req <- request(base_url) %>%
    req_url_query(
      matricula     = toupper(matricula),
      fechaDesde    = f_desde,
      fechaHasta    = f_hasta,
      grupo         = grupo,
      showStopsOnly = if (solo_paradas) "true" else "false"
    ) %>%
    req_headers(
      `Accept`     = "application/json, text/plain, */*",
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    )

  # Imprimir URL que se está consultando
  # Nota: req_dry_run() nos muestra los encabezados y la URL final
  dry_info <- req_dry_run(req)
  cat("🔗 URL Consultada:\n")
  print(dry_info)
  cat("\n-------------------------------------------------------\n")

  # 2. Ejecutar la consulta con manejo de errores HTTP
  resp <- tryCatch(
    req_perform(req),
    error = function(e) {
      cat("❌ ERROR EN LA CONEXIÓN O HTTP:\n")
      print(e)
      return(NULL)
    }
  )

  if (is.null(resp)) {
    cat("❌ Respuesta nula debido a un error HTTP o de conexión.\n")
    return(NULL)
  }

  cat("📥 Código de estado HTTP:", resp_status(resp), "\n")
  cat("📥 Tipo de contenido:     ", resp_header(resp, "content-type"), "\n")

  # 3. Parsear el cuerpo de la respuesta
  texto_crudo <- resp_body_string(resp)

  if (nchar(texto_crudo) == 0) {
    cat("⚠️ La API retornó un cuerpo de respuesta completamente vacío.\n")
    return(NULL)
  }

  # Intentar parsear el JSON
  datos_raw <- tryCatch(
    fromJSON(texto_crudo, simplifyVector = TRUE),
    error = function(e) {
      cat("❌ ERROR AL PARSEAR EL JSON RETORNADO:\n")
      print(e)
      cat("\nContenido crudo de la respuesta:\n")
      cat(substr(texto_crudo, 1, 1000), "...\n")
      return(NULL)
    }
  )

  if (is.null(datos_raw)) {
    return(NULL)
  }

  cat("📥 Registros crudos devueltos:", length(datos_raw), "\n")

  if (length(datos_raw) == 0) {
    cat("ℹ️ Sin posiciones o paradas para esta matrícula en el período indicado.\n")
    return(NULL)
  }

  # Mostrar estructura de los primeros registros recibidos
  cat("\n📋 Estructura de las columnas en la respuesta cruda:\n")
  print(names(datos_raw))

  cat("\n📋 Muestra de los primeros 3 registros crudos:\n")
  print(head(datos_raw, 3))

  # 4. Procesamiento espacial: extraer lon/lat del campo anidado y convertir a sf
  cat("\n-------------------------------------------------------\n")
  cat("⚙️ PROCESANDO GEOMETRÍA A FORMATO SPATIAL (SF)...\n")

  df_sf <- tryCatch(
    {
      datos_raw %>%
        mutate(
          longitud = sapply(coordenadas$coordinates, function(x) x[1]),
          latitud  = sapply(coordenadas$coordinates, function(x) x[2]),
          estado   = ifelse(velocidad == 0, "Detenido", "Movimiento")
        ) %>%
        select(-coordenadas) %>%
        filter(!is.na(longitud) & !is.na(latitud)) %>%
        st_as_sf(coords = c("longitud", "latitud"), crs = 4326)
    },
    error = function(e) {
      cat("❌ ERROR EN EL PROCESAMIENTO ESPACIAL (coordenadas anidadas):\n")
      print(e)
      return(NULL)
    }
  )

  if (is.null(df_sf)) {
    return(NULL)
  }

  cat("✅ Conversión a 'sf' completada con éxito.\n")
  cat("Cantidad final de puntos en el mapa:", nrow(df_sf), "\n")

  if (nrow(df_sf) > 0) {
    cat("\n📋 Columnas del objeto 'sf' final:\n")
    print(names(df_sf))
    cat("\n📋 Primeros 5 puntos resultantes:\n")
    print(head(as.data.frame(df_sf)[, c("matricula", "tiempo", "velocidad", "estado", "geometry")], 5))
  }

  cat("=======================================================\n")
  return(df_sf)
}


#' Consulta de posiciones de toda la flota por turno con logs de depuración completos
#'
#' @param df_matriculas Un data frame que contenga una columna llamada 'Matricula' (ej: df_flota)
#' @param fecha         Fecha a consultar en formato 'YYYY-MM-DD'
#' @param turno         Turno a consultar ('Matutino' o 'Vespertino')
#' @param solo_paradas  Si es TRUE, solicita únicamente las paradas a la API
#' @return Un objeto 'sf' con las posiciones unificadas de todos los vehículos, o NULL
consultar_posiciones_flota_por_turno_interna <- function(df_matriculas, fecha, turno, solo_paradas = FALSE) {
  # 1. Definir horas según el turno
  if (turno == "Matutino") {
    hora_inicio <- "06:00:00"
    hora_fin <- "13:59:59"
  } else if (turno == "Vespertino") {
    hora_inicio <- "14:00:00"
    hora_fin <- "22:00:00"
  } else {
    stop("Turno no válido. Debe ser 'Matutino' o 'Vespertino'.")
  }

  message("\n=======================================================")
  message("🚀 INICIANDO CONSULTA COMPLETA POR TURNO - DIAGNÓSTICO")
  message(paste("Fecha:", fecha, "| Turno:", turno, "| Solo Paradas:", solo_paradas))
  message("=======================================================")

  if (!"Matricula" %in% names(df_matriculas)) {
    if ("matricula" %in% names(df_matriculas)) {
      df_matriculas <- df_matriculas %>% rename(Matricula = matricula)
    } else {
      stop("El data frame de matrículas debe contener una columna llamada 'Matricula'.")
    }
  }

  # 2. Iterar sobre las matrículas usando probar_conexion_api (con purrr::map)
  lista_resultados <- df_matriculas$Matricula %>%
    map(function(m) {
      res <- probar_conexion_api(
        matricula    = m,
        fecha_desde  = fecha, hora_desde = hora_inicio,
        fecha_hasta  = fecha, hora_hasta = hora_fin,
        solo_paradas = solo_paradas
      )

      if (is.null(res) || nrow(res) == 0) {
        message(paste("⚠️ Matrícula", m, ": Sin posiciones en este turno."))
        return(NULL)
      } else {
        message(paste("✅ Matrícula", m, ":", nrow(res), "registros recuperados."))
        return(res)
      }
    })

  # 3. Unir resultados (descartando NULLs)
  resultado_final <- bind_rows(lista_resultados)

  if (is.null(resultado_final) || nrow(resultado_final) == 0) {
    message("\n❌ No se encontraron datos para ninguna matrícula en este turno.")
    return(NULL)
  }

  message("\n=======================================================")
  message(paste("✅ CONSULTA COMPLETADA - REGISTROS TOTALES:", nrow(resultado_final)))
  message("=======================================================")

  return(resultado_final)
}


#' Consulta de posiciones de toda la flota agrupando y separando por turnos (Matutino y Vespertino)
#' usando la lógica de diagnóstico y logs detallados de probar_conexion_api.
#'
#' @param df_matriculas Un data frame que contenga una columna 'Matricula' o 'matricula' (ej: df_flota)
#' @param fecha         Fecha a consultar en formato 'YYYY-MM-DD' (ej: "2026-05-26")
#' @param solo_paradas  Si es TRUE, solicita únicamente las paradas a la API
#' @return Una lista nombrada con los turnos procesados (ej: list(Matutino = sf_df, Vespertino = sf_df))
obtener_posiciones_flota_ambos_turnos_api <- function(df_matriculas, fecha, solo_paradas = FALSE) {
  # Asegurar que purrr esté disponible
  if (!requireNamespace("purrr", quietly = TRUE)) {
    stop("Se requiere el paquete 'purrr' para procesar la lista de matrículas.")
  }
  library(purrr)

  # Normalizar columna Matricula
  if (!"Matricula" %in% names(df_matriculas)) {
    if ("matricula" %in% names(df_matriculas)) {
      df_matriculas <- df_matriculas %>% rename(Matricula = matricula)
    } else {
      stop("El data frame de matrículas debe contener una columna llamada 'Matricula'.")
    }
  }

  turnos <- c("Matutino", "Vespertino")
  resultados <- list()

  for (t in turnos) {
    message(paste("\n======================================================="))
    message(paste("🔄 INICIANDO PROCESAMIENTO TURNO:", toupper(t)))
    message(paste("======================================================="))

    # Reutilizamos consultar_posiciones_flota_por_turno_interna para cada turno, el cual ya
    # usa probar_conexion_api internamente.
    res_turno <- consultar_posiciones_flota_por_turno_interna(
      df_matriculas = df_matriculas,
      fecha         = fecha,
      turno         = t,
      solo_paradas  = solo_paradas
    )

    resultados[[t]] <- res_turno
  }

  return(resultados)
}


#' Buscar vehículos que pasaron por un sector de la capa Hogares_sustentables en una fecha dada (ambos turnos)
#' con un buffer de tolerancia de metros ajustable.
#'
#' @param nombre_sector Nombre del sector en la capa (ej: "CAPURRO 2", "CARRASCO 2")
#' @param fecha         Fecha a consultar en formato 'YYYY-MM-DD' (ej: "2026-05-26")
#' @param buffer_metros Distancia del buffer en metros para la tolerancia espacial (por defecto 70)
#' @param solo_paradas  Si es TRUE, solicita únicamente las paradas a la API
#' @param df_flota_ref  Data frame de la flota de referencia (por defecto df_flota)
#' @param capa_ref      Capa espacial de sectores (por defecto la variable global capa_intra)
#' @return Una lista con los puntos de intersección y un resumen por vehículo, o NULL
buscar_camiones_en_sector_api <- function(nombre_sector,
                                          fecha,
                                          buffer_metros = 70,
                                          solo_paradas = FALSE,
                                          df_flota_ref = df_flota,
                                          capa_ref = capa_intra) {
  message("\n=======================================================")
  message(paste("🔍 BUSCANDO VEHÍCULOS EN SECTOR:", nombre_sector))
  message(paste("📅 Fecha:", fecha, "| Buffer:", buffer_metros, "metros"))
  message("=======================================================")

  # 1. Validar que la capa de referencia exista y contenga el sector
  if (is.null(capa_ref) || !inherits(capa_ref, "sf")) {
    stop("La capa de referencia de sectores ('capa_ref') no es válida o no está cargada.")
  }

  sector_sf <- capa_ref %>% filter(nombre == nombre_sector)
  if (nrow(sector_sf) == 0) {
    message(paste("❌ El sector '", nombre_sector, "' no existe en la capa de referencia."))
    message("Sectores disponibles:")
    print(unique(capa_ref$nombre))
    return(NULL)
  }

  # 2. Consultar o usar posiciones pre-consultadas de la flota para ambos turnos
  if (is.list(df_flota_ref) && !is.data.frame(df_flota_ref)) {
    message("ℹ️ Usando posiciones de la flota pre-consultadas por turno...")
    datos_turnos <- df_flota_ref
  } else {
    datos_turnos <- obtener_posiciones_flota_ambos_turnos_api(
      df_matriculas = df_flota_ref,
      fecha         = fecha,
      solo_paradas  = solo_paradas
    )
  }

  # Combinar las posiciones de ambos turnos
  lista_puntos <- list()
  if (!is.null(datos_turnos$Matutino) && nrow(datos_turnos$Matutino) > 0) {
    lista_puntos[["Matutino"]] <- datos_turnos$Matutino %>% mutate(Turno_Consulta = "Matutino")
  }
  if (!is.null(datos_turnos$Vespertino) && nrow(datos_turnos$Vespertino) > 0) {
    lista_puntos[["Vespertino"]] <- datos_turnos$Vespertino %>% mutate(Turno_Consulta = "Vespertino")
  }

  if (length(lista_puntos) == 0) {
    message("❌ No se obtuvieron posiciones de la API para ninguno de los dos turnos en la fecha indicada.")
    return(NULL)
  }

  puntos_flota_crudos <- bind_rows(lista_puntos)

  # 3. Preparar la geometría espacial del sector
  # Usar UTM 21S (EPSG:32721) para cálculos métricos precisos en Uruguay
  sector_proyectado <- st_transform(sector_sf, 32721)
  puntos_proyectados <- st_transform(puntos_flota_crudos, 32721)

  # Aplicar el buffer al sector
  if (buffer_metros > 0) {
    message(paste("ℹ️ Aplicando buffer de", buffer_metros, "metros al sector", nombre_sector, "..."))
    sector_buffered <- st_buffer(sector_proyectado, dist = buffer_metros)
  } else {
    sector_buffered <- sector_proyectado
  }

  # 4. Intersección espacial
  message("ℹ️ Realizando intersección espacial de posiciones...")
  puntos_interseccion <- st_intersection(puntos_proyectados, sector_buffered)

  if (nrow(puntos_interseccion) == 0) {
    message("\nℹ️ Ningún camión pasó dentro del sector (incluyendo el buffer de tolerancia) en este día.")
    return(NULL)
  }

  # Volver al CRS original (WGS84 EPSG:4326) para visualización
  puntos_final <- st_transform(puntos_interseccion, 4326)

  # 5. Generar resumen analítico de los camiones detectados
  resumen_camiones <- puntos_final %>%
    st_drop_geometry() %>%
    group_by(matricula, Turno_Consulta) %>%
    summarise(
      puntos_en_area = n(),
      velocidad_promedio = mean(velocidad, na.rm = TRUE),
      velocidad_maxima = max(velocidad, na.rm = TRUE),
      .groups = "drop"
    )

  # Obtener el data frame de la flota de metadatos (df_flota) para enriquecer el resumen
  df_flota_metadata <- if (is.data.frame(df_flota_ref) && "Matricula" %in% names(df_flota_ref)) {
    df_flota_ref
  } else if (exists("df_flota", envir = .GlobalEnv)) {
    get("df_flota", envir = .GlobalEnv)
  } else {
    NULL
  }

  if (!is.null(df_flota_metadata)) {
    resumen_camiones <- resumen_camiones %>%
      left_join(df_flota_metadata %>% select(Matricula, Marca, Base, Servicio), by = c("matricula" = "Matricula"))
  }

  message("\n=======================================================")
  message(paste("✅ BÚSQUEDA FINALIZADA EN SECTOR:", nombre_sector))
  message(paste("   Vehículos detectados:", length(unique(resumen_camiones$matricula))))
  message("=======================================================")
  print(resumen_camiones)

  return(list(
    puntos = puntos_final,
    resumen = resumen_camiones,
    sector_buffer = st_transform(sector_buffered, 4326)
  ))
}


#' Buscar vehículos en un sector base y sus sectores nexo (Hogares Sustentables a cierta distancia)
#'
#' @param nombre_sector       Nombre del sector base (ej: "PARQUE RIVERA")
#' @param fecha               Fecha a consultar (ej: "2026-05-28")
#' @param buffer_nexo_metros  Distancia en metros para buscar hogares sustentables conectados (por defecto 150)
#' @param buffer_tolerancia_metros Distancia del buffer en metros para la tolerancia espacial del camión (por defecto 70)
#' @param solo_paradas        Si es TRUE, filtra solo posiciones donde velocidad == 0
#' @param df_flota_ref        Data frame de la flota de referencia (por defecto df_flota)
#' @param capa_sectores_ref   Capa de sectores de referencia (por defecto cargada desde Intradomiciliario_operativo)
#' @param capa_hogares_ref    Capa de hogares sustentables (por defecto cargada desde Hogares_sustentables)
#' @return Una lista con los puntos de intersección, el resumen, el sector base y los hogares nexo
buscar_camiones_en_sector_nexo_api <- function(nombre_sector,
                                               fecha,
                                               buffer_nexo_metros = 150,
                                               buffer_tolerancia_metros = 70,
                                               solo_paradas = FALSE,
                                               df_flota_ref = df_flota,
                                               capa_sectores_ref = NULL,
                                               capa_hogares_ref = NULL) {
  message("\n=======================================================")
  message(paste("🔍 BUSCANDO VEHÍCULOS EN SECTOR BASE:", nombre_sector))
  message(paste("📅 Fecha:", fecha, "| Nexo:", buffer_nexo_metros, "m | Tolerancia:", buffer_tolerancia_metros, "m"))
  message("=======================================================")

  # 1. Cargar capas de referencia si no se proveen
  if (is.null(capa_sectores_ref)) {
    message("ℹ️ Cargando capa de sectores (Intradomiciliario_operativo) desde disco...")
    capa_sectores_ref <- cargar_capa_local_postgres("Intradomiciliario_operativo")
  }
  if (is.null(capa_hogares_ref)) {
    message("ℹ️ Cargando capa de hogares sustentables (Hogares_sustentables) desde disco...")
    capa_hogares_ref <- cargar_capa_local_postgres("Hogares_sustentables")
  }

  # Validar que las capas sean válidas
  if (is.null(capa_sectores_ref) || !inherits(capa_sectores_ref, "sf")) {
    stop("La capa de sectores no es válida.")
  }
  if (is.null(capa_hogares_ref) || !inherits(capa_hogares_ref, "sf")) {
    stop("La capa de hogares sustentables no es válida.")
  }

  # 2. Filtrar sector base
  sector_base <- capa_sectores_ref %>% filter(nombre == nombre_sector)
  if (nrow(sector_base) == 0) {
    message(paste("❌ El sector base '", nombre_sector, "' no existe en la capa de sectores."))
    return(NULL)
  }

  # 3. Proyectar y calcular buffer de nexo para encontrar hogares sustentables conectados
  # Usar UTM 21S (EPSG:32721) para cálculos en metros exactos en Uruguay
  sector_base_proj <- st_transform(sector_base, 32721)
  hogares_proj <- st_transform(capa_hogares_ref, 32721)

  # Generar buffer de nexo (por defecto 150m) alrededor del sector base
  sector_base_buffered <- st_buffer(sector_base_proj, dist = buffer_nexo_metros)

  # Filtrar hogares sustentables que intersectan (hacen nexo geográfico con) este buffer
  hogares_nexo_proj <- hogares_proj %>%
    st_filter(sector_base_buffered)

  # Transformar de vuelta a WGS84 para visualización y exportación
  sector_base_wgs84 <- st_transform(sector_base, 4326)
  hogares_nexo <- st_transform(hogares_nexo_proj, 4326)

  message(paste("✅ Nexo geográfico establecido. Se encontraron", nrow(hogares_nexo), "hogares sustentables conectados."))

  # 4. Unir geometrías proyectadas de búsqueda para la intersección de vehículos
  capas_unidas_proj <- bind_rows(
    sector_base_proj %>% select(geom = matches("geom|geometry")),
    hogares_nexo_proj %>% select(geom = matches("geom|geometry"))
  )

  # 5. Obtener posiciones de la flota
  if (is.list(df_flota_ref) && !is.data.frame(df_flota_ref)) {
    message("ℹ️ Usando posiciones de la flota pre-consultadas por turno...")
    datos_turnos <- df_flota_ref
  } else {
    datos_turnos <- obtener_posiciones_flota_ambos_turnos_api(
      df_matriculas = df_flota_ref,
      fecha         = fecha,
      solo_paradas  = solo_paradas
    )
  }

  # Combinar posiciones
  lista_puntos <- list()
  if (!is.null(datos_turnos$Matutino) && nrow(datos_turnos$Matutino) > 0) {
    lista_puntos[["Matutino"]] <- datos_turnos$Matutino %>% mutate(Turno_Consulta = "Matutino")
  }
  if (!is.null(datos_turnos$Vespertino) && nrow(datos_turnos$Vespertino) > 0) {
    lista_puntos[["Vespertino"]] <- datos_turnos$Vespertino %>% mutate(Turno_Consulta = "Vespertino")
  }

  if (length(lista_puntos) == 0) {
    message("❌ No se obtuvieron posiciones de la API para ninguno de los dos turnos en la fecha indicada.")
    return(list(
      puntos        = NULL,
      resumen       = NULL,
      sector_base   = sector_base_wgs84,
      hogares_nexo  = hogares_nexo,
      sector_buffer = st_transform(sector_base_buffered, 4326),
      fecha         = fecha,
      turno         = "Ambos"
    ))
  }

  puntos_flota_crudos <- bind_rows(lista_puntos)
  puntos_proyectados <- st_transform(puntos_flota_crudos, 32721)

  # Aplicar buffer de tolerancia espacial (por defecto 70m) a las geometrías unidas
  if (buffer_tolerancia_metros > 0) {
    message(paste("ℹ️ Aplicando buffer de tolerancia de", buffer_tolerancia_metros, "metros a la zona total de búsqueda..."))
    capas_unidas_buffered <- st_buffer(capas_unidas_proj, dist = buffer_tolerancia_metros)
  } else {
    capas_unidas_buffered <- capas_unidas_proj
  }

  # Intersección espacial
  message("ℹ️ Realizando intersección espacial de posiciones...")
  puntos_interseccion <- st_intersection(puntos_proyectados, capas_unidas_buffered)

  if (nrow(puntos_interseccion) == 0) {
    message("\nℹ️ Ningún camión pasó dentro del sector base ni de sus nexos en este día.")
    return(list(
      puntos        = NULL,
      resumen       = NULL,
      sector_base   = sector_base_wgs84,
      hogares_nexo  = hogares_nexo,
      sector_buffer = st_transform(sector_base_buffered, 4326),
      fecha         = fecha,
      turno         = "Ambos"
    ))
  }

  puntos_final <- st_transform(puntos_interseccion, 4326)

  # 6. Generar resumen analítico de los camiones detectados
  resumen_camiones <- puntos_final %>%
    st_drop_geometry() %>%
    group_by(matricula, Turno_Consulta) %>%
    summarise(
      puntos_en_area = n(),
      velocidad_promedio = mean(velocidad, na.rm = TRUE),
      velocidad_maxima = max(velocidad, na.rm = TRUE),
      .groups = "drop"
    )

  # Enriquecer resumen con metadatos de flota
  df_flota_metadata <- if (is.data.frame(df_flota_ref) && "Matricula" %in% names(df_flota_ref)) {
    df_flota_ref
  } else if (exists("df_flota", envir = .GlobalEnv)) {
    get("df_flota", envir = .GlobalEnv)
  } else {
    NULL
  }

  if (!is.null(df_flota_metadata)) {
    resumen_camiones <- resumen_camiones %>%
      left_join(df_flota_metadata %>% select(Matricula, Marca, Base, Servicio), by = c("matricula" = "Matricula"))
  }

  message("\n=======================================================")
  message(paste("✅ BÚSQUEDA DE NEXOS FINALIZADA EN:", nombre_sector))
  message(paste("   Vehículos detectados en sector + hogares nexo:", length(unique(resumen_camiones$matricula))))
  message("=======================================================")
  print(resumen_camiones)

  return(list(
    puntos        = puntos_final,
    resumen       = resumen_camiones,
    sector_base   = sector_base_wgs84,
    hogares_nexo  = hogares_nexo,
    sector_buffer = st_transform(sector_base_buffered, 4326),
    fecha         = fecha,
    turno         = "Ambos"
  ))
}


#' Grafica el sector base, sus hogares sustentables nexo y el recorrido/posiciones de la flota
#' utilizando Leaflet, iconos IMM y filtros estilo Radiobutton interactivos.
#'
#' @param res_nexo     Objeto retornado por buscar_camiones_en_sector_nexo_api
#' @param usar_iconos  Si es TRUE (por defecto), dibuja los iconos personalizados IMM compactos
#' @return Un objeto widget de Leaflet listo para mostrar o guardar
graficar_mapa_nexo_estilo_imm <- function(res_nexo, usar_iconos = TRUE) {
  if (is.null(res_nexo)) {
    message("⚠️ No hay resultados para graficar.")
    return(NULL)
  }

  puntos <- res_nexo$puntos
  sector_base <- res_nexo$sector_base
  hogares_nexo <- res_nexo$hogares_nexo

  # Cargar librerías necesarias
  if (!requireNamespace("leaflet", quietly = TRUE)) {
    stop("Se requiere el paquete 'leaflet'. Instálalo con install.packages('leaflet')")
  }
  if (!requireNamespace("htmltools", quietly = TRUE)) {
    stop("Se requiere el paquete 'htmltools'. Instálalo con install.packages('htmltools')")
  }
  library(leaflet)
  library(htmltools)

  # Inicializar el mapa con fondo limpio CartoDB Positron
  mapa <- leaflet() %>%
    addProviderTiles(providers$CartoDB.Positron)

  # 1. Dibujar el sector base (en Naranja brillante con borde grueso)
  if (!is.null(sector_base) && nrow(sector_base) > 0) {
    # Asegurar nombres limpios en popup
    viviendas_val <- if ("viviendas" %in% names(sector_base)) sector_base$viviendas else "N/A"
    turno_val <- if ("TURNO" %in% names(sector_base)) sector_base$TURNO else "N/A"
    frec_val <- if ("FRECUENCIA" %in% names(sector_base)) sector_base$FRECUENCIA else "N/A"
    frac_val <- if ("FRACCION" %in% names(sector_base)) sector_base$FRACCION else "N/A"

    mapa <- mapa %>%
      addPolygons(
        data = sector_base,
        color = "#FF6600",
        weight = 3,
        fillColor = "#FF6600",
        fillOpacity = 0.15,
        group = "Capas Territoriales",
        popup = paste0(
          "<b>Sector Base (Capítulo Operativo)</b><br>",
          "Nombre: ", sector_base$nombre, "<br>",
          "Viviendas: ", viviendas_val, "<br>",
          "Turno: ", turno_val, "<br>",
          "Frecuencia: ", frec_val, "<br>",
          "Fracción: ", frac_val
        ),
        label = ~ paste0("Base: ", nombre),
        labelOptions = labelOptions(noHide = FALSE)
      )
  }

  # 2. Dibujar los hogares vinculados (en Azul y con información filtrada)
  if (!is.null(hogares_nexo) && nrow(hogares_nexo) > 0) {
    mapa <- mapa %>%
      addPolygons(
        data = hogares_nexo,
        color = "#0066CC",
        weight = 1.5,
        fillColor = "#0066CC",
        fillOpacity = 0.25,
        group = "Capas Territoriales",
        popup = paste0(
          "<b>Hogar Sustentable</b><br>",
          "Nombre: ", hogares_nexo$nombre, "<br>",
          "Modalidad: ", hogares_nexo$modalidad, "<br>",
          "Turno Mezcla: ", hogares_nexo$turno_mez, "<br>",
          "Frecuencia Mezcla: ", hogares_nexo$frec_mez, "<br>",
          "Días Mezcla: ", hogares_nexo$dias_mez, "<br>",
          "Turno Reciclable: ", hogares_nexo$turno_rec, "<br>",
          "Días Reciclable: ", hogares_nexo$dias_rec, "<br>",
          "Tipo Reciclable: ", hogares_nexo$tipo_rec
        ),
        label = ~ paste0("Hogar: ", nombre, " (", modalidad, ")"),
        labelOptions = labelOptions(noHide = FALSE)
      )
  }

  # 3. Dibujar los puntos del recorrido del vehículo (con radiobutton y filtro de velocidad == 0)
  if (!is.null(puntos) && nrow(puntos) > 0) {
    puntos_web <- st_transform(puntos, 4326)
    coords <- st_coordinates(puntos_web)

    # Centrar el mapa en los puntos
    mapa <- mapa %>%
      setView(lng = mean(coords[, 1]), lat = mean(coords[, 2]), zoom = 14)

    if (usar_iconos) {
      message("ℹ️ Dibujando iconos IMM compactos para vehículos...")
      for (i in 1:nrow(puntos_web)) {
        vel_val <- puntos_web$velocidad[i]
        orient <- puntos_web$orientacion[i]
        tiempo <- puntos_web$tiempo[i]
        mat <- puntos_web$matricula[i]
        turno_c <- puntos_web$Turno_Consulta[i]

        lon <- coords[i, 1]
        lat <- coords[i, 2]

        if (is.na(vel_val)) vel_val <- 0
        if (is.na(orient)) orient <- 0

        popup_content <- paste0(
          "<b>", ifelse(vel_val == 0, "Parada", "Movimiento"), "</b><br>",
          "Matrícula: ", mat, "<br>",
          "Hora: ", tiempo, "<br>",
          "Velocidad: ", vel_val, " km/h<br>",
          "Orientación: ", orient, "°<br>",
          "Turno Consulta: ", turno_c
        )

        if (vel_val == 0) {
          icon_html <- '
          <div style="
              display: flex; justify-content: center; align-items: center;
              width: 14px; height: 14px; background-color: #FF6600;
              border: 1.5px solid white; border-radius: 50%;
              box-shadow: 0px 1px 3px rgba(0,0,0,0.4);
              box-sizing: border-box;
              transform: translate(-7px, -7px);">
              <div style="display: flex; gap: 1px;">
                  <div style="width: 1.5px; height: 5px; background-color: white;"></div>
                  <div style="width: 1.5px; height: 5px; background-color: white;"></div>
              </div>
          </div>
          '
          grupo_esp <- "Detenidos"
        } else {
          rot_angle <- orient + 45
          icon_html <- paste0('
          <div style="
              display: flex; justify-content: center; align-items: center;
              width: 14px; height: 14px; background-color: #73C01E;
              border: 1.5px solid white; border-radius: 50%;
              box-shadow: 0px 1px 3px rgba(0,0,0,0.4);
              box-sizing: border-box;
              transform: translate(-7px, -7px);">
              <div style="
                  width: 4px; height: 4px;
                  border-left: 1.5px solid white;
                  border-top: 1.5px solid white;
                  transform: rotate(', rot_angle, 'deg);
                  margin-top: 1px; margin-left: 1px;">
              </div>
          </div>
          ')
          grupo_esp <- "Movimiento"
        }

        # 1. Dibujar en "Todos"
        mapa <- mapa %>%
          addLabelOnlyMarkers(
            lng = lon, lat = lat,
            label = htmltools::HTML(icon_html),
            group = "Todos",
            layerId = paste0(mat, "_label_todos_", i),
            labelOptions = labelOptions(noHide = TRUE, direction = "center", textOnly = TRUE)
          ) %>%
          addCircleMarkers(
            lng = lon, lat = lat,
            radius = 7, stroke = FALSE, fillColor = "transparent", fillOpacity = 0,
            group = "Todos",
            layerId = paste0(mat, "_circle_todos_", i),
            popup = popup_content
          )

        # 2. Dibujar en el grupo específico ("Detenidos" o "Movimiento")
        mapa <- mapa %>%
          addLabelOnlyMarkers(
            lng = lon, lat = lat,
            label = htmltools::HTML(icon_html),
            group = grupo_esp,
            layerId = paste0(mat, "_label_esp_", i),
            labelOptions = labelOptions(noHide = TRUE, direction = "center", textOnly = TRUE)
          ) %>%
          addCircleMarkers(
            lng = lon, lat = lat,
            radius = 7, stroke = FALSE, fillColor = "transparent", fillOpacity = 0,
            group = grupo_esp,
            layerId = paste0(mat, "_circle_esp_", i),
            popup = popup_content
          )
      }
    } else {
      # Dibujar círculos simples vectorizados
      df_detenidos <- puntos_web %>% filter(velocidad == 0)
      df_movimiento <- puntos_web %>% filter(velocidad > 0)

      # 1. Todos
      mapa <- mapa %>%
        addCircleMarkers(
          lng = coords[, 1], lat = coords[, 2],
          radius = 5, stroke = TRUE, color = "white", weight = 1.5,
          fillColor = ifelse(puntos_web$velocidad == 0, "#FF6600", "#73C01E"),
          fillOpacity = 0.85,
          group = "Todos",
          layerId = paste0(puntos_web$matricula, "_circle_todos_", 1:nrow(puntos_web)),
          popup = paste0(
            "<b>", ifelse(puntos_web$velocidad == 0, "Parada", "Movimiento"), "</b><br>",
            "Matrícula: ", puntos_web$matricula, "<br>",
            "Hora: ", puntos_web$tiempo, "<br>",
            "Velocidad: ", puntos_web$velocidad, " km/h<br>",
            "Orientación: ", puntos_web$orientacion, "°"
          )
        )

      # 2. Detenidos
      if (nrow(df_detenidos) > 0) {
        coords_det <- st_coordinates(df_detenidos)
        mapa <- mapa %>%
          addCircleMarkers(
            lng = coords_det[, 1], lat = coords_det[, 2],
            radius = 5, stroke = TRUE, color = "white", weight = 1.5,
            fillColor = "#FF6600", fillOpacity = 0.85,
            group = "Detenidos",
            layerId = paste0(df_detenidos$matricula, "_circle_det_", 1:nrow(df_detenidos)),
            popup = paste0(
              "<b>Parada</b><br>",
              "Matrícula: ", df_detenidos$matricula, "<br>",
              "Hora: ", df_detenidos$tiempo, "<br>",
              "Velocidad: ", df_detenidos$velocidad, " km/h<br>",
              "Orientación: ", df_detenidos$orientacion, "°"
            )
          )
      }

      # 3. Movimiento
      if (nrow(df_movimiento) > 0) {
        coords_mov <- st_coordinates(df_movimiento)
        mapa <- mapa %>%
          addCircleMarkers(
            lng = coords_mov[, 1], lat = coords_mov[, 2],
            radius = 5, stroke = TRUE, color = "white", weight = 1.5,
            fillColor = "#73C01E", fillOpacity = 0.85,
            group = "Movimiento",
            layerId = paste0(df_movimiento$matricula, "_circle_mov_", 1:nrow(df_movimiento)),
            popup = paste0(
              "<b>Movimiento</b><br>",
              "Matrícula: ", df_movimiento$matricula, "<br>",
              "Hora: ", df_movimiento$tiempo, "<br>",
              "Velocidad: ", df_movimiento$velocidad, " km/h<br>",
              "Orientación: ", df_movimiento$orientacion, "°"
            )
          )
      }
    }
  } else {
    # Centrar en el sector base si no hay vehículos
    if (!is.null(sector_base) && nrow(sector_base) > 0) {
      coords_base <- st_coordinates(st_centroid(sector_base))
      mapa <- mapa %>%
        setView(lng = coords_base[1, 1], lat = coords_base[1, 2], zoom = 14)
    }
  }

  # 4. Agregar Layer Control (BaseGroups para vehículos y OverlayGroups para capas territoriales)
  mapa <- mapa %>%
    addLayersControl(
      baseGroups = c("Todos", "Detenidos", "Movimiento"),
      overlayGroups = c("Capas Territoriales"),
      options = layersControlOptions(collapsed = FALSE)
    )

  # 5. Agregar cartel informativo en azul con Turno, Día y horas de entrada/salida de cada vehículo
  fecha_val <- if (!is.null(res_nexo$fecha)) res_nexo$fecha else "N/A"
  turno_val <- if (!is.null(res_nexo$turno)) res_nexo$turno else "Ambos"

  cartel_lineas <- c(
    paste0("DÍA: ", fecha_val),
    paste0("TURNO: ", toupper(turno_val))
  )

  if (!is.null(puntos) && nrow(puntos) > 0) {
    # Asegurar que la columna tiempo esté parseada como POSIXct con la hora completa
    puntos_copia <- puntos
    clean_tiempo <- gsub("T", " ", puntos_copia$tiempo)
    clean_tiempo <- gsub("Z", "", clean_tiempo)
    clean_tiempo <- gsub("\\+.*", "", clean_tiempo)

    # Intentar parseo robusto según el formato de fecha detectado
    tiempos_convertidos <- as.POSIXct(rep(NA, length(clean_tiempo)))

    # Formato YYYY-MM-DD HH:MM:SS
    idx_ymd <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", clean_tiempo)
    if (any(idx_ymd)) {
      tiempos_convertidos[idx_ymd] <- as.POSIXct(clean_tiempo[idx_ymd], format = "%Y-%m-%d %H:%M:%S")
    }

    # Formato DD-MM-YYYY HH:MM:SS
    idx_dmy <- grepl("^[0-9]{2}-[0-9]{2}-[0-9]{4}", clean_tiempo)
    if (any(idx_dmy)) {
      tiempos_convertidos[idx_dmy] <- as.POSIXct(clean_tiempo[idx_dmy], format = "%d-%m-%Y %H:%M:%S")
    }

    # Fallback/otros formatos
    idx_na <- is.na(tiempos_convertidos) & !is.na(clean_tiempo) & clean_tiempo != ""
    if (any(idx_na)) {
      tiempos_convertidos[idx_na] <- as.POSIXct(clean_tiempo[idx_na])
    }

    puntos_copia$tiempo_posix <- tiempos_convertidos

    matriculas_unicas <- sort(unique(puntos_copia$matricula))

    for (mat in matriculas_unicas) {
      tiempos_mat <- puntos_copia$tiempo_posix[puntos_copia$matricula == mat]
      tiempos_mat <- tiempos_mat[!is.na(tiempos_mat)]

      if (length(tiempos_mat) > 0) {
        tiempos_mat <- sort(tiempos_mat)
        inicio_f <- format(tiempos_mat[1], "%H:%M:%S")

        if (length(tiempos_mat) == 1) {
          fin_f <- inicio_f
        } else {
          # Calcular diferencias en horas consecutivas
          diff_horas <- as.numeric(difftime(tiempos_mat[-1], tiempos_mat[-length(tiempos_mat)], units = "hours"))

          # Buscar si hay un salto de más de 1 hora
          gap_idx <- which(diff_horas > 1)

          if (length(gap_idx) > 0) {
            # Si hay un salto, la salida es el punto antes de la primera interrupción de más de 1 hora
            fin_f <- format(tiempos_mat[gap_idx[1]], "%H:%M:%S")
          } else {
            # Si no hay saltos, la salida es la última posición registrada
            fin_f <- format(tiempos_mat[length(tiempos_mat)], "%H:%M:%S")
          }
        }

        cartel_lineas <- c(cartel_lineas, paste0("VEHÍCULO ", mat, ": ", inicio_f, " - ", fin_f))
      }
    }
  } else {
    cartel_lineas <- c(cartel_lineas, "SIN VEHÍCULOS DETECTADOS")
  }

  cartel_texto <- paste(cartel_lineas, collapse = "<br>")

  cartel_html <- paste0(
    '<div style="',
    "background-color: #0066CC; ",
    "color: white; ",
    "padding: 8px 12px; ",
    "border-radius: 4px; ",
    "font-family: Arial, sans-serif; ",
    "font-size: 11px; ",
    "font-weight: bold; ",
    "line-height: 1.4; ",
    "box-shadow: 0px 1px 3px rgba(0,0,0,0.4);",
    '">',
    cartel_texto,
    "</div>"
  )

  mapa <- mapa %>%
    addControl(html = cartel_html, position = "topleft") %>%
    htmlwidgets::onRender("
      function(el, x) {
        var map = this;
        var matriculas = new Set();
        map.eachLayer(function(layer) {
          if (layer.options && layer.options.layerId) {
            var id = layer.options.layerId;
            var parts = id.split('_');
            if (parts.length >= 2) {
              matriculas.add(parts[0]);
            }
          }
        });
        if (matriculas.size > 0) {
          var container = L.DomUtil.create('div', 'leaflet-bar leaflet-control');
          container.style.backgroundColor = 'white';
          container.style.padding = '6px 8px';
          container.style.borderRadius = '4px';
          container.style.boxShadow = '0 1px 5px rgba(0,0,0,0.4)';
          
          L.DomEvent.disableClickPropagation(container);
          L.DomEvent.disableScrollPropagation(container);
          
          var label = document.createElement('div');
          label.innerHTML = 'FILTRAR VEHÍCULO:';
          label.style.fontFamily = 'Arial, sans-serif';
          label.style.fontSize = '9px';
          label.style.fontWeight = 'bold';
          label.style.color = '#333333';
          label.style.marginBottom = '4px';
          container.appendChild(label);
          
          var select = document.createElement('select');
          select.style.width = '160px';
          select.style.padding = '4px';
          select.style.border = '1px solid #0066CC';
          select.style.borderRadius = '3px';
          select.style.fontSize = '11px';
          select.style.fontWeight = 'bold';
          select.style.color = '#0066CC';
          select.style.outline = 'none';
          select.style.cursor = 'pointer';
          
          var optAll = document.createElement('option');
          optAll.value = 'ALL';
          optAll.innerHTML = 'MOSTRAR TODOS';
          select.appendChild(optAll);
          
          var sortedMats = Array.from(matriculas).sort();
          sortedMats.forEach(function(mat) {
            var opt = document.createElement('option');
            opt.value = mat;
            opt.innerHTML = mat;
            select.appendChild(opt);
          });
          container.appendChild(select);
          
          var filterControl = L.control({position: 'topright'});
          filterControl.onAdd = function() { return container; };
          filterControl.addTo(map);
          
          function aplicarFiltro() {
            var selected = select.value;
            map.eachLayer(function(layer) {
              if (layer.options && layer.options.layerId) {
                var id = layer.options.layerId;
                var parts = id.split('_');
                if (parts.length >= 2) {
                  var mat = parts[0];
                  var element = layer._path || (layer._icon ? layer._icon : null);
                  if (element) {
                    if (selected === 'ALL' || mat === selected) {
                      element.style.display = '';
                      if (layer._tooltip) layer._tooltip.style.display = '';
                    } else {
                      element.style.display = 'none';
                      if (layer._tooltip) layer._tooltip.style.display = 'none';
                    }
                  }
                }
              }
            });
          }
          
          select.onchange = aplicarFiltro;
          
          map.on('layeradd', function(e) {
            var layer = e.layer;
            if (layer.options && layer.options.layerId) {
              var id = layer.options.layerId;
              var parts = id.split('_');
              if (parts.length >= 2) {
                var mat = parts[0];
                var selected = select.value;
                if (selected !== 'ALL' && mat !== selected) {
                  setTimeout(function() {
                    var element = layer._path || layer._icon;
                    if (element) {
                      element.style.display = 'none';
                      if (layer._tooltip) layer._tooltip.style.display = 'none';
                    }
                  }, 0);
                }
              }
            }
          });
        }
      }
    ")

  mapa
}


#' Exporta el mapa interactivo de nexos a un archivo HTML interactivo autónomo en R
#'
#' @param res_nexo     Objeto retornado por buscar_camiones_en_sector_nexo_api
#' @param salida_html  Ruta de salida del archivo HTML (ej: "salidas/mapas/Mapa_Parque_Rivera_Nexos.html")
#' @param usar_iconos  Si es TRUE (por defecto), dibuja los iconos personalizados IMM compactos
#' @return TRUE si se guardó con éxito, FALSE en caso contrario
exportar_mapa_nexo_estilo_imm <- function(res_nexo, salida_html, usar_iconos = TRUE) {
  if (is.null(res_nexo)) {
    message("⚠️ No hay datos para exportar.")
    return(FALSE)
  }

  puntos <- res_nexo$puntos

  # 1. Si puntos tiene la columna Turno_Consulta y hay múltiples turnos,
  #    generamos automáticamente un mapa distinto para cada turno.
  if (!is.null(puntos) && inherits(puntos, "sf") && "Turno_Consulta" %in% names(puntos)) {
    turnos_unicos <- unique(puntos$Turno_Consulta)

    if (length(turnos_unicos) > 1) {
      message(paste("ℹ️ Se detectaron", length(turnos_unicos), "turnos. Generando un mapa individual por turno..."))
      for (t in turnos_unicos) {
        # Crear copia de la lista de resultados modificando los puntos para este turno
        res_t <- res_nexo
        res_t$puntos <- puntos %>% filter(Turno_Consulta == t)
        res_t$turno <- t

        ext <- tools::file_ext(salida_html)
        base <- tools::file_path_sans_ext(salida_html)
        salida_t <- paste0(base, "_", toupper(t), ".", ext)

        exportar_mapa_nexo_estilo_imm(
          res_nexo    = res_t,
          salida_html = salida_t,
          usar_iconos = usar_iconos
        )
      }
      return(TRUE)
    }
  }

  library(leaflet)
  library(htmlwidgets)

  mapa <- graficar_mapa_nexo_estilo_imm(res_nexo, usar_iconos = usar_iconos)
  if (is.null(mapa)) {
    return(FALSE)
  }

  # Asegurar que el directorio de salida exista
  dir_salida <- dirname(salida_html)
  if (!dir.exists(dir_salida)) {
    dir.create(dir_salida, recursive = TRUE)
  }

  message("ℹ️ Guardando mapa interactivo a archivo HTML...")
  tryCatch(
    {
      saveWidget(mapa, file = salida_html, selfcontained = TRUE)
      message(paste("✅ Mapa interactivo guardado en:", salida_html))
      return(TRUE)
    },
    error = function(e) {
      message("❌ Error al guardar el widget HTML:")
      print(e)
      return(FALSE)
    }
  )
}


#' Genera vectores en forma de flecha para indicar la orientación de los vehículos en movimiento
#'
#' @param df_sf           Objeto 'sf' de puntos (resultado de probar_conexion_api)
#' @param longitud_metros Longitud del eje de la flecha en metros (por defecto 20)
#' @return Un objeto 'sf' con geometrías MULTILINESTRING que forman flechas orientadas
crear_flechas_orientacion <- function(df_sf, longitud_metros = 20) {
  if (!"estado" %in% names(df_sf) || !"orientacion" %in% names(df_sf)) {
    warning("El data frame debe contener las columnas 'estado' y 'orientacion'.")
    return(NULL)
  }

  # Filtrar solo registros en movimiento y con orientación válida
  df_mov <- df_sf %>% filter(estado == "Movimiento" & !is.na(orientacion))

  if (nrow(df_mov) == 0) {
    message("ℹ️ No hay vehículos en movimiento para generar vectores de orientación.")
    return(NULL)
  }

  crs_original <- st_crs(df_sf)

  # Proyectar temporalmente a UTM 21S (EPSG:32721) para cálculos en metros exactos
  df_mov_proj <- st_transform(df_mov, 32721)
  coords <- st_coordinates(df_mov_proj)

  lineas <- lapply(1:nrow(df_mov_proj), function(i) {
    x1 <- coords[i, 1]
    y1 <- coords[i, 2]

    # Convertir orientación (grados compass) a radianes (0 es Norte, sentido horario)
    angle_rad <- df_mov_proj$orientacion[i] * pi / 180

    # 1. Flecha principal (eje)
    x2 <- x1 + longitud_metros * sin(angle_rad)
    y2 <- y1 + longitud_metros * cos(angle_rad)

    # 2. Alas de la punta de la flecha (longitud de 6 metros, ángulo hacia atrás a 30 grados)
    longitud_ala <- 6
    x_l <- x2 - longitud_ala * sin(angle_rad - 30 * pi / 180)
    y_l <- y2 - longitud_ala * cos(angle_rad - 30 * pi / 180)

    x_r <- x2 - longitud_ala * sin(angle_rad + 30 * pi / 180)
    y_r <- y2 - longitud_ala * cos(angle_rad + 30 * pi / 180)

    # Combinar en un MULTILINESTRING (eje + ala izquierda + ala derecha)
    st_multilinestring(list(
      matrix(c(x1, x2, y1, y2), ncol = 2),
      matrix(c(x2, x_l, y2, y_l), ncol = 2),
      matrix(c(x2, x_r, y2, y_r), ncol = 2)
    ))
  })

  flechas_sf <- st_sf(
    matricula   = df_mov_proj$matricula,
    tiempo      = df_mov_proj$tiempo,
    velocidad   = df_mov_proj$velocidad,
    orientacion = df_mov_proj$orientacion,
    geometry    = st_sfc(lineas, crs = 32721)
  )

  # Devolver al CRS original
  st_transform(flechas_sf, crs_original)
}


# =============================================================================
# FUNCIÓN DE VISUALIZACIÓN LEAFLET (ESTILO IMM CON ICONOS ROTADOS)
# =============================================================================
graficar_mapa_estilo_imm <- function(df_sf, usar_iconos = TRUE) {
  if (is.null(df_sf) || nrow(df_sf) == 0) {
    message("⚠️ No hay datos para graficar.")
    return(NULL)
  }

  # Cargar librerías necesarias
  if (!requireNamespace("leaflet", quietly = TRUE)) {
    stop("Se requiere el paquete 'leaflet'. Instálalo con install.packages('leaflet')")
  }
  if (!requireNamespace("htmltools", quietly = TRUE)) {
    stop("Se requiere el paquete 'htmltools'. Instálalo con install.packages('htmltools')")
  }
  library(leaflet)
  library(htmltools)

  # Asegurar CRS en WGS84 (EPSG:4326) para Leaflet
  df_sf_web <- st_transform(df_sf, 4326)
  coords <- st_coordinates(df_sf_web)

  # Inicializar el mapa con el estilo de fondo CartoDB Positron
  mapa <- leaflet(df_sf_web) %>%
    addProviderTiles(providers$CartoDB.Positron) %>%
    setView(lng = mean(coords[, 1]), lat = mean(coords[, 2]), zoom = 14)

  if (usar_iconos) {
    message("ℹ️ Dibujando iconos personalizados compactos (14px) con filtro de radiobutton...")
    for (i in 1:nrow(df_sf_web)) {
      vel_val <- df_sf_web$velocidad[i]
      orient <- df_sf_web$orientacion[i]
      tiempo <- df_sf_web$tiempo[i]
      mat <- df_sf_web$matricula[i]

      lon <- coords[i, 1]
      lat <- coords[i, 2]

      if (is.na(vel_val)) vel_val <- 0
      if (is.na(orient)) orient <- 0

      popup_content <- paste0(
        "<b>", ifelse(vel_val == 0, "Parada", "Movimiento"), "</b><br>",
        "Matrícula: ", mat, "<br>",
        "Hora: ", tiempo, "<br>",
        "Velocidad: ", vel_val, " km/h<br>",
        "Orientación: ", orient, "°"
      )

      if (vel_val == 0) {
        # Icono de parada: Círculo naranja compacto (14px) con "II" en blanco
        icon_html <- '
        <div style="
            display: flex; justify-content: center; align-items: center;
            width: 14px; height: 14px; background-color: #FF6600;
            border: 1.5px solid white; border-radius: 50%;
            box-shadow: 0px 1px 3px rgba(0,0,0,0.4);
            box-sizing: border-box;
            transform: translate(-7px, -7px);">
            <div style="display: flex; gap: 1px;">
                <div style="width: 1.5px; height: 5px; background-color: white;"></div>
                <div style="width: 1.5px; height: 5px; background-color: white;"></div>
            </div>
        </div>
        '
        grupo_esp <- "Detenidos"
      } else {
        # Icono de movimiento: Círculo verde compacto (14px) con flecha blanca rotada
        rot_angle <- orient + 45
        icon_html <- paste0('
        <div style="
            display: flex; justify-content: center; align-items: center;
            width: 14px; height: 14px; background-color: #73C01E;
            border: 1.5px solid white; border-radius: 50%;
            box-shadow: 0px 1px 3px rgba(0,0,0,0.4);
            box-sizing: border-box;
            transform: translate(-7px, -7px);">
            <div style="
                width: 4px; height: 4px;
                border-left: 1.5px solid white;
                border-top: 1.5px solid white;
                transform: rotate(', rot_angle, 'deg);
                margin-top: 1px; margin-left: 1px;">
            </div>
        </div>
        ')
        grupo_esp <- "Movimiento"
      }

      # 1. Dibujar en el grupo "Todos"
      mapa <- mapa %>%
        addLabelOnlyMarkers(
          lng = lon, lat = lat,
          label = htmltools::HTML(icon_html),
          group = "Todos",
          layerId = paste0(mat, "_label_todos_", i),
          labelOptions = labelOptions(
            noHide = TRUE,
            direction = "center",
            textOnly = TRUE
          )
        ) %>%
        addCircleMarkers(
          lng = lon, lat = lat,
          radius = 7,
          stroke = FALSE,
          fillColor = "transparent",
          fillOpacity = 0,
          group = "Todos",
          layerId = paste0(mat, "_circle_todos_", i),
          popup = popup_content
        )

      # 2. Dibujar en el grupo específico ("Detenidos" o "Movimiento")
      mapa <- mapa %>%
        addLabelOnlyMarkers(
          lng = lon, lat = lat,
          label = htmltools::HTML(icon_html),
          group = grupo_esp,
          layerId = paste0(mat, "_label_esp_", i),
          labelOptions = labelOptions(
            noHide = TRUE,
            direction = "center",
            textOnly = TRUE
          )
        ) %>%
        addCircleMarkers(
          lng = lon, lat = lat,
          radius = 7,
          stroke = FALSE,
          fillColor = "transparent",
          fillOpacity = 0,
          group = grupo_esp,
          layerId = paste0(mat, "_circle_esp_", i),
          popup = popup_content
        )
    }
  } else {
    message("ℹ️ Dibujando círculos de colores simples agrupados por estado con filtro de radiobutton...")
    # Separar datos
    df_detenidos <- df_sf_web %>% filter(velocidad == 0)
    df_movimiento <- df_sf_web %>% filter(velocidad > 0)

    # 1. Agregar todos los puntos al grupo "Todos"
    mapa <- mapa %>%
      addCircleMarkers(
        lng = coords[, 1], lat = coords[, 2],
        radius = 5,
        stroke = TRUE,
        color = "white",
        weight = 1.5,
        fillColor = ifelse(df_sf_web$velocidad == 0, "#FF6600", "#73C01E"),
        fillOpacity = 0.85,
        group = "Todos",
        layerId = paste0(df_sf_web$matricula, "_circle_todos_", 1:nrow(df_sf_web)),
        popup = paste0(
          "<b>", ifelse(df_sf_web$velocidad == 0, "Parada", "Movimiento"), "</b><br>",
          "Matrícula: ", df_sf_web$matricula, "<br>",
          "Hora: ", df_sf_web$tiempo, "<br>",
          "Velocidad: ", df_sf_web$velocidad, " km/h<br>",
          "Orientación: ", df_sf_web$orientacion, "°"
        )
      )

    # 2. Agregar detenidos al grupo "Detenidos"
    if (nrow(df_detenidos) > 0) {
      coords_det <- st_coordinates(df_detenidos)
      mapa <- mapa %>%
        addCircleMarkers(
          lng = coords_det[, 1], lat = coords_det[, 2],
          radius = 5,
          stroke = TRUE,
          color = "white",
          weight = 1.5,
          fillColor = "#FF6600",
          fillOpacity = 0.85,
          group = "Detenidos",
          layerId = paste0(df_detenidos$matricula, "_circle_det_", 1:nrow(df_detenidos)),
          popup = paste0(
            "<b>Parada</b><br>",
            "Matrícula: ", df_detenidos$matricula, "<br>",
            "Hora: ", df_detenidos$tiempo, "<br>",
            "Velocidad: ", df_detenidos$velocidad, " km/h<br>",
            "Orientación: ", df_detenidos$orientacion, "°"
          )
        )
    }

    # 3. Agregar movimiento al grupo "Movimiento"
    if (nrow(df_movimiento) > 0) {
      coords_mov <- st_coordinates(df_movimiento)
      mapa <- mapa %>%
        addCircleMarkers(
          lng = coords_mov[, 1], lat = coords_mov[, 2],
          radius = 5,
          stroke = TRUE,
          color = "white",
          weight = 1.5,
          fillColor = "#73C01E",
          fillOpacity = 0.85,
          group = "Movimiento",
          layerId = paste0(df_movimiento$matricula, "_circle_mov_", 1:nrow(df_movimiento)),
          popup = paste0(
            "<b>Movimiento</b><br>",
            "Matrícula: ", df_movimiento$matricula, "<br>",
            "Hora: ", df_movimiento$tiempo, "<br>",
            "Velocidad: ", df_movimiento$velocidad, " km/h<br>",
            "Orientación: ", df_movimiento$orientacion, "°"
          )
        )
    }
  }

  # Agregar el control de capas interactivo con estilo Radiobutton (baseGroups)
  mapa <- mapa %>%
    addLayersControl(
      baseGroups = c("Todos", "Detenidos", "Movimiento"),
      options = layersControlOptions(collapsed = FALSE)
    ) %>%
    htmlwidgets::onRender("
      function(el, x) {
        var map = this;
        var matriculas = new Set();
        map.eachLayer(function(layer) {
          if (layer.options && layer.options.layerId) {
            var id = layer.options.layerId;
            var parts = id.split('_');
            if (parts.length >= 2) {
              matriculas.add(parts[0]);
            }
          }
        });
        if (matriculas.size > 0) {
          var container = L.DomUtil.create('div', 'leaflet-bar leaflet-control');
          container.style.backgroundColor = 'white';
          container.style.padding = '6px 8px';
          container.style.borderRadius = '4px';
          container.style.boxShadow = '0 1px 5px rgba(0,0,0,0.4)';
          
          L.DomEvent.disableClickPropagation(container);
          L.DomEvent.disableScrollPropagation(container);
          
          var label = document.createElement('div');
          label.innerHTML = 'FILTRAR VEHÍCULO:';
          label.style.fontFamily = 'Arial, sans-serif';
          label.style.fontSize = '9px';
          label.style.fontWeight = 'bold';
          label.style.color = '#333333';
          label.style.marginBottom = '4px';
          container.appendChild(label);
          
          var select = document.createElement('select');
          select.style.width = '160px';
          select.style.padding = '4px';
          select.style.border = '1px solid #0066CC';
          select.style.borderRadius = '3px';
          select.style.fontSize = '11px';
          select.style.fontWeight = 'bold';
          select.style.color = '#0066CC';
          select.style.outline = 'none';
          select.style.cursor = 'pointer';
          
          var optAll = document.createElement('option');
          optAll.value = 'ALL';
          optAll.innerHTML = 'MOSTRAR TODOS';
          select.appendChild(optAll);
          
          var sortedMats = Array.from(matriculas).sort();
          sortedMats.forEach(function(mat) {
            var opt = document.createElement('option');
            opt.value = mat;
            opt.innerHTML = mat;
            select.appendChild(opt);
          });
          container.appendChild(select);
          
          var filterControl = L.control({position: 'topright'});
          filterControl.onAdd = function() { return container; };
          filterControl.addTo(map);
          
          function aplicarFiltro() {
            var selected = select.value;
            map.eachLayer(function(layer) {
              if (layer.options && layer.options.layerId) {
                var id = layer.options.layerId;
                var parts = id.split('_');
                if (parts.length >= 2) {
                  var mat = parts[0];
                  var element = layer._path || (layer._icon ? layer._icon : null);
                  if (element) {
                    if (selected === 'ALL' || mat === selected) {
                      element.style.display = '';
                      if (layer._tooltip) layer._tooltip.style.display = '';
                    } else {
                      element.style.display = 'none';
                      if (layer._tooltip) layer._tooltip.style.display = 'none';
                    }
                  }
                }
              }
            });
          }
          
          select.onchange = aplicarFiltro;
          
          map.on('layeradd', function(e) {
            var layer = e.layer;
            if (layer.options && layer.options.layerId) {
              var id = layer.options.layerId;
              var parts = id.split('_');
              if (parts.length >= 2) {
                var mat = parts[0];
                var selected = select.value;
                if (selected !== 'ALL' && mat !== selected) {
                  setTimeout(function() {
                    var element = layer._path || layer._icon;
                    if (element) {
                      element.style.display = 'none';
                      if (layer._tooltip) layer._tooltip.style.display = 'none';
                    }
                  }, 0);
                }
              }
            }
          });
        }
      }
    ")

  mapa
}


#' Exporta el recorrido a un archivo HTML interactivo usando Leaflet y htmlwidgets (estilo IMM con iconos personalizados)
#'
#' @param df_sf       Objeto 'sf' de puntos (resultado de probar_conexion_api)
#' @param salida_html Ruta del archivo HTML de salida (ej: "salidas/mapas/Mapa_Estilo_IMM.html")
#' @param usar_iconos Si es TRUE (por defecto), dibuja iconos de pausa/flecha compactos. Si es FALSE, dibuja círculos simples ultrarrápidos.
#' @return TRUE si se guardó con éxito, FALSE en caso contrario
exportar_mapa_estilo_imm <- function(df_sf, salida_html, usar_iconos = TRUE) {
  if (is.null(df_sf) || nrow(df_sf) == 0) {
    message("⚠️ No hay datos para exportar.")
    return(FALSE)
  }

  # Cargar librerías necesarias
  if (!requireNamespace("leaflet", quietly = TRUE)) {
    stop("Se requiere el paquete 'leaflet'. Instálalo con install.packages('leaflet')")
  }
  if (!requireNamespace("htmlwidgets", quietly = TRUE)) {
    stop("Se requiere el paquete 'htmlwidgets'. Instálalo con install.packages('htmlwidgets')")
  }
  library(leaflet)
  library(htmlwidgets)

  # Generar el mapa leaflet con la misma lógica de graficar_mapa_estilo_imm
  mapa <- graficar_mapa_estilo_imm(df_sf, usar_iconos = usar_iconos)

  if (is.null(mapa)) {
    return(FALSE)
  }

  # Asegurar que el directorio de destino exista
  dir_salida <- dirname(salida_html)
  if (!dir.exists(dir_salida)) {
    dir.create(dir_salida, recursive = TRUE)
  }

  message("ℹ | Guardando mapa interactivo HTML de forma autónoma...")

  tryCatch(
    {
      saveWidget(mapa, file = salida_html, selfcontained = TRUE)
      message(paste("✅ Mapa interactivo guardado con éxito en:", salida_html))
      return(TRUE)
    },
    error = function(e) {
      message("❌ Error al guardar el widget HTML con htmlwidgets::saveWidget:")
      print(e)
      return(FALSE)
    }
  )
}


# =============================================================================
# EJEMPLOS DE PRUEBA RÁPIDOS
# =============================================================================
# Puedes seleccionar una de las líneas de abajo y ejecutarla en la consola de R
# para ver el diagnóstico exacto de lo que está ocurriendo:

if (FALSE) {
  # Ejemplo 1: Consultar todas las posiciones de una matrícula en un día común
  res_completo <- probar_conexion_api(
    matricula = "SIM2188",
    fecha_desde = "2026-05-28", hora_desde = "06:00:00",
    fecha_hasta = "2026-05-28", hora_hasta = "20:59:59",
    solo_paradas = FALSE
  )

  # Ejemplo 2: Consultar SOLO paradas de la misma matrícula y período
  res_paradas <- probar_conexion_api(
    matricula = "SIM2188",
    fecha_desde = "2026-05-28", hora_desde = "06:00:00",
    fecha_hasta = "2026-05-28", hora_hasta = "20:59:59",
    solo_paradas = TRUE
  )

  # Ejemplo 3: Graficar las PARADAS interactiva en RStudio con iconos IMM (Naranja con "II")
  if (!is.null(res_paradas) && nrow(res_paradas) > 0) {
    graficar_mapa_estilo_imm(res_paradas)
  }

  # Ejemplo 4: Graficar TODO el recorrido en RStudio con iconos IMM (Verdes rotados + Naranjas)
  if (!is.null(res_completo) && nrow(res_completo) > 0) {
    graficar_mapa_estilo_imm(res_completo)
  }

  # Ejemplo 5: Exportar todo el recorrido a un archivo HTML interactivo con el estilo IMM (Flechas verdes rotadas + Paradas naranjas)
  # Esta función es autónoma en R, no requiere Python ni cargar otros scripts:
  if (!is.null(res_busqueda_paradas$puntos) && nrow(res_busqueda_paradas$puntos) > 0) {
    exportar_mapa_estilo_imm(
      df_sf       = res_busqueda_paradas$puntos,
      salida_html = "salidas/mapas/Mapa_Estilo_IMM.html"
    )
  }

  # Ejemplo 6: Consultar toda la flota separando por turnos
  # Nota: Requiere haber cargado df_flota ejecutando primero: source("db/POSTGRES/conexionPOSTGRES.R")
  df_flota_turnos <- obtener_posiciones_flota_ambos_turnos_api(
    df_matriculas = df_flota,
    fecha         = "2026-05-26",
    solo_paradas  = FALSE
  )
  print(names(df_flota_turnos)) # Muestra: "Matutino" "Vespertino"
  print(nrow(df_flota_turnos$Matutino))

  df_flota_matutino <- df_flota_turnos[["Matutino"]] %>%
    group_by(matricula) %>%
    summarise(total = n())

  # Ejemplo 7: Buscar camiones en un sector específico con un buffer de 70 metros (ambos turnos combinados)
  # Primero se obtienen las posiciones por turno para evitar llamadas a la API repetidas si se buscan múltiples sectores
  df_flota_turnos_ej7 <- obtener_posiciones_flota_ambos_turnos_api(
    df_matriculas = df_flota,
    fecha         = "2026-05-28",
    solo_paradas  = FALSE
  )

  res_busqueda <- buscar_camiones_en_sector_api(
    nombre_sector = "PARQUE RIVERA",
    fecha         = "2026-05-28",
    buffer_metros = 70,
    df_flota_ref  = df_flota_turnos_ej7
  )

  ver <- res_busqueda[["puntos"]]

  # Si se encontraron datos, graficar el resultado general y exportar mapa interactivo HTML por turno
  if (!is.null(res_busqueda) && !is.null(res_busqueda$puntos) && nrow(res_busqueda$puntos) > 0) {
    # 1. Graficar en consola interactiva (ambos turnos)
    graficar_mapa_estilo_imm(res_busqueda$puntos)

    # 2. Separar por turnos y exportar mapas interactivos HTML individuales
    puntos_matutino <- res_busqueda$puntos %>% filter(Turno_Consulta == "Matutino")
    puntos_vespertino <- res_busqueda$puntos %>% filter(Turno_Consulta == "Vespertino")

    if (nrow(puntos_matutino) > 0) {
      exportar_mapa_estilo_imm(
        df_sf       = puntos_matutino,
        salida_html = "salidas/mapas/Mapa_Parque_Rivera_Matutino.html"
      )
    }

    if (nrow(puntos_vespertino) > 0) {
      exportar_mapa_estilo_imm(
        df_sf       = puntos_vespertino,
        salida_html = "salidas/mapas/Mapa_Parque_Rivera_Vespertino.html"
      )
    }
  }

  # Ejemplo 8: Buscar SOLO paradas de camiones en un sector específico con un buffer de 70 metros (ambos turnos combinados)
  # Primero se obtienen únicamente las paradas por turno para evitar llamadas a la API repetidas
  df_flota_turnos_ej8 <- obtener_posiciones_flota_ambos_turnos_api(
    df_matriculas = df_flota,
    fecha         = "2026-05-28",
    solo_paradas  = TRUE
  )

  res_busqueda_paradas <- buscar_camiones_en_sector_api(
    nombre_sector = "PARQUE RIVERA",
    fecha         = "2026-05-28",
    buffer_metros = 70,
    solo_paradas  = TRUE,
    df_flota_ref  = df_flota_turnos_ej8
  )

  ver_paradas <- res_busqueda_paradas[["puntos"]]

  # Si se encontraron datos, graficar el resultado
  if (!is.null(res_busqueda_paradas)) {
    graficar_mapa_estilo_imm(res_busqueda_paradas$puntos)
  }

  # Ejemplo 9: Buscar camiones en un sector base y en todos sus Hogares Sustentables vinculados (buffer de 150m)
  # Primero se obtienen las posiciones por turno para evitar llamadas a la API repetidas
  df_flota_turnos_ej9 <- obtener_posiciones_flota_ambos_turnos_api(
    df_matriculas = df_flota,
    fecha         = "2026-05-28",
    solo_paradas  = FALSE
  )

  # res_nexo <- buscar_camiones_en_sector_nexo_api(
  #   nombre_sector            = "PARQUE RIVERA",
  #   fecha                    = "2026-05-28",
  #   buffer_nexo_metros       = 150,
  #   buffer_tolerancia_metros = 70,
  #   df_flota_ref             = df_flota_turnos_ej9
  # )
  # 
  # # Si se encontraron datos, graficar y exportar el mapa interactivo
  # if (!is.null(res_nexo)) {
  #   # Mostrar mapa en consola
  #   graficar_mapa_nexo_estilo_imm(res_nexo)
  # 
  #   # Guardar mapa interactivo HTML autónomo
  #   exportar_mapa_nexo_estilo_imm(
  #     res_nexo    = res_nexo,
  #     salida_html = "salidas/mapas/Mapa_Parque_Rivera_Vinculados.html"
  #   )
  # }

  # Ejemplo 10: Buscar camiones en un sector base y en todos sus Hogares Sustentables vinculados (buffer de 150m) - SIN ICONOS (Ultrarrápido y liviano)
  # Reutilizamos las posiciones ya consultadas en el Ejemplo 9 (df_flota_turnos_ej9) para evitar llamadas adicionales a la API
  res_nexo_ej10 <- buscar_camiones_en_sector_nexo_api(
    nombre_sector            = "PARQUE RIVERA",
    fecha                    = "2026-05-28",
    buffer_nexo_metros       = 150,
    buffer_tolerancia_metros = 70,
    df_flota_ref             = df_flota_turnos_ej9
  )

  # Si se encontraron datos, graficar y exportar el mapa interactivo ultrarrápido sin iconos
  if (!is.null(res_nexo_ej10)) {
    # Mostrar mapa en consola sin iconos (usando usar_iconos = FALSE)
    graficar_mapa_nexo_estilo_imm(res_nexo_ej10, usar_iconos = FALSE)

    # Guardar mapa interactivo HTML autónomo sin iconos
    exportar_mapa_nexo_estilo_imm(
      res_nexo    = res_nexo_ej10,
      salida_html = "salidas/mapas/Mapa_Parque_Rivera_Vinculados_Rapido.html",
      usar_iconos = FALSE
    )
  }
}
