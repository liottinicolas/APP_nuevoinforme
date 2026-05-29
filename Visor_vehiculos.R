# =============================================================================
# VISOR VEHÍCULOS IMM
# Dependencias externas cargadas via source() más abajo:
#   - df_flota, conectar_postgres(), actualizar_capa_postgres() → conexionPOSTGRES.R
#   - python_venv → debe estar definido en el entorno antes de ejecutar este script
# =============================================================================

# --- Librerías ---------------------------------------------------------------
library(httr2)
library(jsonlite)
library(purrr)
library(dplyr)
library(tidyr)
library(sf)

# --- Dependencias externas ---------------------------------------------------
source("db/POSTGRES/conexionPOSTGRES.R")   # carga df_flota, conectar_postgres(), etc.


# =============================================================================
# FUNCIÓN 1: Obtener posiciones de UN vehículo desde la API del visor IMM
# =============================================================================
obtener_posiciones_imm <- function(matricula,
                                   fecha_desde, hora_desde = "00:00:00",
                                   fecha_hasta, hora_hasta = "23:59:59",
                                   grupo = "sisconve",
                                   solo_paradas = FALSE) {

  # 1. Formatear fechas al estándar de la API (YYYY-MM-DDTHH:MM:SS)
  f_desde <- paste0(as.character(as.Date(fecha_desde)), "T", hora_desde)
  f_hasta <- paste0(as.character(as.Date(fecha_hasta)), "T", hora_hasta)

  base_url <- "https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones"

  # 2. Construir la petición
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

  # 3. Ejecutar con manejo de errores HTTP
  resp <- tryCatch(
    req_perform(req),
    error = function(e) {
      message(paste("❌ Error al consultar matrícula", toupper(matricula), ":", conditionMessage(e)))
      return(NULL)
    }
  )
  if (is.null(resp)) return(NULL)

  # 4. Parsear JSON
  datos_raw <- resp_body_json(resp, simplifyVector = TRUE)

  if (length(datos_raw) == 0) {
    message(paste("ℹ️  Sin posiciones para", toupper(matricula), "en el período indicado."))
    return(NULL)
  }

  # 5. Procesamiento espacial: extraer lon/lat del campo anidado y convertir a sf
  df_sf <- datos_raw %>%
    mutate(
      longitud = sapply(coordenadas$coordinates, function(x) x[1]),
      latitud  = sapply(coordenadas$coordinates, function(x) x[2]),
      estado   = ifelse(velocidad == 0, "Detenido", "Movimiento")
    ) %>%
    select(-coordenadas) %>%
    filter(!is.na(longitud) & !is.na(latitud)) %>%
    st_as_sf(coords = c("longitud", "latitud"), crs = 4326)

  return(df_sf)
}

# Ejemplo de uso puntual (comentar cuando no se necesite):
# res <- obtener_posiciones_imm(
#   matricula   = "SIM3042",
#   fecha_desde = "2026-04-10", hora_desde = "09:42:50",
#   fecha_hasta = "2026-04-21", hora_hasta = "09:42:50"
# )
# library(mapview); mapview(res)

# Ejemplo de uso puntual (comentar cuando no se necesite):
# res <- obtener_posiciones_imm(
#   matricula   = "SIM3127",
#   fecha_desde = "2026-05-25", hora_desde = "06:00:50",
#   fecha_hasta = "2026-05-25", hora_hasta = "19:42:50"
# )
# 
# res_quieto <- res %>% 
#   filter(velocidad == 0)
# library(mapview); mapview(res_quieto)
# #install.packages("mapview")

# =============================================================================
# FUNCIÓN 2: Obtener posiciones de TODA LA FLOTA para un turno y fecha dados
# =============================================================================
obtener_posiciones_por_turno <- function(df_matriculas, fecha, turno, solo_paradas = FALSE) {

  # 1. Definir horas según el turno
  if (turno == "Matutino") {
    hora_inicio <- "06:00:00"
    hora_fin    <- "13:59:59"
  } else if (turno == "Vespertino") {
    hora_inicio <- "14:00:00"
    hora_fin    <- "22:00:00"
  } else {
    stop("Turno no válido. Debe ser 'Matutino' o 'Vespertino'.")
  }

  message(paste("--- Iniciando consulta Turno", turno, "-", fecha, "---"))

  # 2. Iterar sobre las matrículas
  lista_resultados <- df_matriculas$Matricula %>%
    map(function(m) {
      res <- obtener_posiciones_imm(
        matricula   = m,
        fecha_desde = fecha, hora_desde = hora_inicio,
        fecha_hasta = fecha, hora_hasta = hora_fin,
        solo_paradas = solo_paradas
      )

      if (is.null(res) || nrow(res) == 0) {
        message(paste("⚠️  Matrícula", m, ": Sin posiciones encontradas."))
        return(NULL)
      } else {
        message(paste("✅ Matrícula", m, ":", nrow(res), "posiciones obtenidas."))
        return(res)
      }
    })

  # 3. Unir resultados (descartando NULLs)
  resultado_final <- bind_rows(lista_resultados)

  if (nrow(resultado_final) == 0) {
    message("❌ No se encontraron datos para ninguna matrícula en este turno.")
    return(NULL)
  }

  message(paste("Total de registros recuperados:", nrow(resultado_final)))
  return(resultado_final)
}


# =============================================================================
# FUNCIÓN 3: Buscar vehículos que pasaron/pararon por una geometría
# =============================================================================
buscar_vehiculos_en_geometria <- function(capa_geometria,
                                          fecha,
                                          turno = c("Matutino", "Vespertino"),
                                          df_flota_ref = df_flota,
                                          buffer_metros = 50,
                                          solo_paradas = TRUE) {

  # 1. Validar y combinar la geometría de entrada (sf o lista de sf)
  if (is.list(capa_geometria) && !is.data.frame(capa_geometria)) {
    message("ℹ️ Combinando lista de geometrías...")
    # Filtrar solo elementos sf válidos
    capa_geometria <- capa_geometria[sapply(capa_geometria, function(x) inherits(x, "sf"))]
    
    if (length(capa_geometria) == 0) {
      stop("La lista no contiene objetos 'sf' válidos.")
    }
    
    # Obtener el CRS de referencia del primer elemento
    crs_referencia <- st_crs(capa_geometria[[1]])
    
    capa_geometria <- lapply(capa_geometria, function(x) {
      # Alinear el CRS si difiere del primero
      if (st_crs(x) != crs_referencia) {
        message("ℹ️ Ajustando CRS de una de las capas para coincidir con la de referencia...")
        x <- st_transform(x, crs_referencia)
      }
      
      # Validar/crear columna nombre
      if (!"nombre" %in% names(x)) {
        if ("name" %in% names(x)) {
          x <- x %>% rename(nombre = name)
        } else if ("nom" %in% names(x)) {
          x <- x %>% rename(nombre = nom)
        } else {
          x$nombre <- "Área de Interés"
        }
      }
      x$nombre <- as.character(x$nombre)
      # Seleccionar únicamente la columna nombre (geometry se mantiene de forma automática)
      x %>% select(nombre)
    })
    capa_geometria <- bind_rows(capa_geometria)
  }

  if (!inherits(capa_geometria, "sf")) {
    stop("La geometría de entrada debe ser un objeto 'sf' o una lista de objetos 'sf'.")
  }

  # Asegurar columna nombre y tipo character para entrada única
  if (!"nombre" %in% names(capa_geometria)) {
    if ("name" %in% names(capa_geometria)) {
      capa_geometria <- capa_geometria %>% rename(nombre = name)
    } else if ("nom" %in% names(capa_geometria)) {
      capa_geometria <- capa_geometria %>% rename(nombre = nom)
    } else {
      capa_geometria$nombre <- "Área de Interés"
    }
  }
  capa_geometria$nombre <- as.character(capa_geometria$nombre)

  if (nrow(capa_geometria) == 0) {
    message("⚠️ Geometría de entrada vacía.")
    return(NULL)
  }

  # 2. Manejo de CRS y Buffer sin modificar la geometría original de entrada
  crs_original <- st_crs(capa_geometria)
  
  # Si el CRS es geográfico (grados, e.g. WGS84 EPSG:4326), proyectamos temporalmente a UTM 21S (EPSG:32721)
  is_geographic <- st_is_longlat(capa_geometria)
  if (is_geographic) {
    message("ℹ️ Proyección geográfica detectada. Proyectando a EPSG:32721 (UTM 21S) para cálculo preciso de buffer en metros...")
    capa_proyectada <- st_transform(capa_geometria, 32721)
  } else {
    capa_proyectada <- capa_geometria
  }

  # Aplicar buffer
  if (buffer_metros > 0) {
    message(paste("ℹ️ Aplicando buffer de", buffer_metros, "metros a la geometría de búsqueda..."))
    capa_con_buffer <- st_buffer(capa_proyectada, dist = buffer_metros)
  } else {
    capa_con_buffer <- capa_proyectada
  }

  puntos_solapados_lista <- list()

  # 3. Iterar por cada turno solicitado
  for (t in turno) {
    message(paste("\n--- Buscando vehículos en Turno", t, "-", fecha, "---"))
    
    # Obtener posiciones de la flota para este turno
    posiciones_turno <- obtener_posiciones_por_turno(
      df_matriculas = df_flota_ref,
      fecha         = fecha,
      turno         = t,
      solo_paradas  = solo_paradas
    )

    if (is.null(posiciones_turno) || nrow(posiciones_turno) == 0) {
      message(paste("⚠️ Sin posiciones de vehículos para el Turno", t))
      next
    }

    # Transformar las posiciones del vehículo al CRS proyectado para hacer la intersección
    posiciones_proyectadas <- st_transform(posiciones_turno, st_crs(capa_con_buffer))

    # Intersección: puntos dentro de la geometría bufferizada
    solapados_t <- st_intersection(posiciones_proyectadas, capa_con_buffer)

    if (nrow(solapados_t) > 0) {
      # Agregar el indicador de turno al resultado
      solapados_t <- solapados_t %>% mutate(Turno_Consulta = t)
      puntos_solapados_lista[[t]] <- solapados_t
    } else {
      message(paste("ℹ️ Ningún vehículo coincidió con la geometría en el Turno", t))
    }
  }

  # 4. Consolidar resultados
  if (length(puntos_solapados_lista) == 0) {
    message("\nℹ️ No se encontraron vehículos que hayan pasado/parado en la fecha y turnos indicados.")
    return(NULL)
  }

  puntos_final_proyectados <- bind_rows(puntos_solapados_lista)

  # Devolver los puntos detallados al CRS original
  puntos_final <- st_transform(puntos_final_proyectados, crs_original)

  # Enriquecer los puntos con la columna FRACCION para compatibilidad con el mapa de Python
  puntos_final <- puntos_final %>%
    left_join(df_flota_ref %>% select(Matricula, FRACCION = Servicio), by = c("matricula" = "Matricula"))

  # Crear resumen tabular agrupado por vehículo y turno
  # st_drop_geometry para hacer resumen rápido
  resumen <- puntos_final %>%
    st_drop_geometry() %>%
    group_by(matricula, Turno_Consulta) %>%
    summarise(
      puntos_detectados = n(),
      velocidad_promedio = mean(velocidad, na.rm = TRUE),
      velocidad_maxima   = max(velocidad, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    # Enriquecer con datos de flota
    left_join(df_flota_ref, by = c("matricula" = "Matricula"))

  message(paste("\n✅ Búsqueda completada. Total de vehículos encontrados:", length(unique(resumen$matricula))))
  
  return(list(
    puntos  = puntos_final,
    resumen = resumen
  ))
}


# =============================================================================
# FUNCIÓN 4: Generar mapa interactivo HTML usando el script de Python
# =============================================================================
exportar_mapa_interactivo <- function(capa_geometria,
                                      puntos_detectados,
                                      salida_html,
                                      python_path = python_venv,
                                      capa_geometria_2 = NULL) {

  # 1. Si puntos_detectados tiene la columna Turno_Consulta y hay múltiples turnos,
  #    generamos automáticamente un mapa distinto para cada turno.
  if (!is.null(puntos_detectados) && inherits(puntos_detectados, "sf") && "Turno_Consulta" %in% names(puntos_detectados)) {
    turnos_unicos <- unique(puntos_detectados$Turno_Consulta)
    
    if (length(turnos_unicos) > 1) {
      message(paste("ℹ️ Se detectaron", length(turnos_unicos), "turnos en los resultados. Generando un mapa individual para cada uno..."))
      for (t in turnos_unicos) {
        puntos_t <- puntos_detectados %>% filter(Turno_Consulta == t)
        
        # Generar nombre del archivo para este turno (ej. NombreSector_MATUTINO.html)
        ext <- tools::file_ext(salida_html)
        base <- tools::file_path_sans_ext(salida_html)
        salida_t <- paste0(base, "_", toupper(t), ".", ext)
        
        # Llamada recursiva para este turno en particular
        exportar_mapa_interactivo(
          capa_geometria    = capa_geometria,
          puntos_detectados = puntos_t,
          salida_html       = salida_t,
          python_path       = python_path,
          capa_geometria_2  = capa_geometria_2
        )
      }
      return(TRUE)
    }
  }

  # 2. Validar y combinar la primera geometría de entrada (sf o lista de sf)
  if (is.list(capa_geometria) && !is.data.frame(capa_geometria)) {
    message("ℹ️ Combinando lista de geometrías para la primera capa...")
    capa_geometria <- capa_geometria[sapply(capa_geometria, function(x) inherits(x, "sf"))]
    
    if (length(capa_geometria) == 0) {
      stop("La lista de la primera capa no contiene objetos 'sf' válidos.")
    }
    
    crs_referencia <- st_crs(capa_geometria[[1]])
    
    capa_geometria <- lapply(capa_geometria, function(x) {
      # Alinear el CRS si difiere del primero
      if (st_crs(x) != crs_referencia) {
        message("ℹ️ Ajustando CRS de una de las capas para coincidir con la de referencia en el mapa...")
        x <- st_transform(x, crs_referencia)
      }
      
      # Validar/crear columna nombre
      if (!"nombre" %in% names(x)) {
        if ("name" %in% names(x)) {
          x <- x %>% rename(nombre = name)
        } else if ("nom" %in% names(x)) {
          x <- x %>% rename(nombre = nom)
        } else {
          x$nombre <- "Área de Interés"
        }
      }
      x$nombre <- as.character(x$nombre)
      # Seleccionar únicamente la columna nombre (geometry se mantiene de forma automática)
      x %>% select(nombre)
    })
    capa_geometria <- bind_rows(capa_geometria)
  }

  if (!inherits(capa_geometria, "sf")) {
    stop("La 'capa_geometria' debe ser un objeto 'sf' o una lista de objetos 'sf'.")
  }

  # Asegurar columna nombre y tipo character para entrada única
  if (!"nombre" %in% names(capa_geometria)) {
    if ("name" %in% names(capa_geometria)) {
      capa_geometria <- capa_geometria %>% rename(nombre = name)
    } else if ("nom" %in% names(capa_geometria)) {
      capa_geometria <- capa_geometria %>% rename(nombre = nom)
    } else {
      capa_geometria$nombre <- "Área de Interés"
    }
  }
  capa_geometria$nombre <- as.character(capa_geometria$nombre)

  # 3. Validar y combinar la segunda geometría de entrada (opcional)
  temp_path_referencia <- NULL
  if (!is.null(capa_geometria_2)) {
    if (is.list(capa_geometria_2) && !is.data.frame(capa_geometria_2)) {
      message("ℹ️ Combinando lista de geometrías para la segunda capa...")
      capa_geometria_2 <- capa_geometria_2[sapply(capa_geometria_2, function(x) inherits(x, "sf"))]
      
      if (length(capa_geometria_2) > 0) {
        crs_referencia_2 <- st_crs(capa_geometria_2[[1]])
        capa_geometria_2 <- lapply(capa_geometria_2, function(x) {
          if (st_crs(x) != crs_referencia_2) {
            x <- st_transform(x, crs_referencia_2)
          }
          if (!"nombre" %in% names(x)) {
            if ("name" %in% names(x)) {
              x <- x %>% rename(nombre = name)
            } else if ("nom" %in% names(x)) {
              x <- x %>% rename(nombre = nom)
            } else {
              x$nombre <- "Área de Interés"
            }
          }
          x$nombre <- as.character(x$nombre)
          x %>% select(nombre)
        })
        capa_geometria_2 <- bind_rows(capa_geometria_2)
      }
    }
    
    if (inherits(capa_geometria_2, "sf") && nrow(capa_geometria_2) > 0) {
      # Asegurar alineación de CRS con la primera capa
      if (st_crs(capa_geometria_2) != st_crs(capa_geometria)) {
        message("ℹ️ Ajustando CRS de la segunda capa para coincidir con la primera...")
        capa_geometria_2 <- st_transform(capa_geometria_2, st_crs(capa_geometria))
      }
      
      if (!"nombre" %in% names(capa_geometria_2)) {
        if ("name" %in% names(capa_geometria_2)) {
          capa_geometria_2 <- capa_geometria_2 %>% rename(nombre = name)
        } else if ("nom" %in% names(capa_geometria_2)) {
          capa_geometria_2 <- capa_geometria_2 %>% rename(nombre = nom)
        } else {
          capa_geometria_2$nombre <- "Área de Referencia"
        }
      }
      capa_geometria_2$nombre <- as.character(capa_geometria_2$nombre)
      
      # Seleccionar únicamente la columna nombre para evitar tipos de datos incompatibles (como integer64)
      capa_geometria_2 <- capa_geometria_2 %>% select(nombre)
      
      temp_path_referencia <- tempfile(fileext = ".geojson")
      st_write(capa_geometria_2, temp_path_referencia, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
    }
  }
  
  if (!inherits(puntos_detectados, "sf")) {
    stop("Los 'puntos_detectados' deben ser un objeto 'sf'.")
  }

  if (nrow(puntos_detectados) == 0) {
    message("⚠️ No hay puntos detectados para graficar en el mapa.")
    return(FALSE)
  }

  # 4. Asegurar que el directorio de salida exista
  dir_salida <- dirname(salida_html)
  if (!dir.exists(dir_salida)) {
    dir.create(dir_salida, recursive = TRUE)
  }

  # Guardar las capas en archivos GeoJSON temporales
  temp_path_intra  <- tempfile(fileext = ".geojson")
  temp_path_puntos <- tempfile(fileext = ".geojson")

  message("ℹ️ Exportando capas temporales a GeoJSON...")
  st_write(capa_geometria,     temp_path_intra,  driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
  st_write(puntos_detectados,  temp_path_puntos, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)

  # 5. Ejecutar Python con argumentos
  message("ℹ️ Ejecutando script de Python para dibujar el mapa...")
  args_py <- c(
    "vistas/mapas/mapa_intro_dibujarutas.py",
    temp_path_intra,
    temp_path_puntos,
    salida_html
  )
  if (!is.null(temp_path_referencia)) {
    args_py <- c(args_py, temp_path_referencia)
  }
  
  status <- system2(
    python_path,
    args = args_py
  )

  if (status == 0) {
    message(paste("✅ Mapa interactivo generado con éxito en:", salida_html))
    return(TRUE)
  } else {
    message("❌ Error al ejecutar el script de Python para generar el mapa.")
    return(FALSE)
  }
}


# 1. Cargar dependencias y capas territoriales
source("db/POSTGRES/conexionPOSTGRES.R")
capa_intra <- cargar_capa_local_postgres("Intradomiciliario_operativo")
Hogares_sustentables <- cargar_capa_local_postgres("Hogares_sustentables")

# 2. Seleccionar los sectores
capa_sector <- capa_intra[capa_intra$nombre == "PARQUE RIVERA", ]

# 3. Filtrar Hogares Sustentables en un radio ajustable (ej: 100 metros) de Parque Rivera
distancia_radio <- 100  # <-- Distancia de búsqueda en metros (ajustable)

# Proyectar a un CRS métrico estándar (EPSG:32721) para cálculos precisos de distancia
capa_sector_proj          <- st_transform(capa_sector, 32721)
Hogares_sustentables_proj <- st_transform(Hogares_sustentables, st_crs(capa_sector_proj))

# Aplicar el buffer de distancia al sector
sector_con_buffer <- st_buffer(capa_sector_proj, dist = distancia_radio)

# Filtrar espacialmente los hogares que están dentro del sector extendido
capa_sector_hogares <- Hogares_sustentables_proj %>%
  st_filter(sector_con_buffer) %>%
  st_transform(st_crs(Hogares_sustentables))  # Retornar al CRS original

message(paste("ℹ️ Hogares sustentables a menos de", distancia_radio, "metros de Parque Rivera:", nrow(capa_sector_hogares)))

# 4. Buscar vehículos en la combinación de geometrías (sector + hogares filtrados)
resultado <- buscar_vehiculos_en_geometria(
  capa_geometria = list(capa_sector, capa_sector_hogares),
  fecha          = "2026-05-26",
  turno          = c("Matutino", "Vespertino"),
  buffer_metros  = 50,
  solo_paradas   = TRUE
)

# 5. Exportar resultados diferenciando los colores en el mapa y separando por turno
if (!is.null(resultado)) {
  print(resultado$resumen)
  
  # Generará automáticamente:
  #   - "salidas/mapas/Mapa_PARQUE_RIVERA_MATUTINO.html"   (para el turno matutino)
  #   - "salidas/mapas/Mapa_PARQUE_RIVERA_VESPERTINO.html"  (para el turno vespertino)
  exportar_mapa_interactivo(
    capa_geometria    = capa_sector,           # Capa 1: Se dibujará en NARANJA
    capa_geometria_2  = capa_sector_hogares,  # Capa 2: Se dibujará en AZUL (dentro del radio)
    puntos_detectados = resultado$puntos,
    salida_html       = "salidas/mapas/Mapa_PARQUE_RIVERA.html"
  )
}
  



# =============================================================================
# EJECUCIÓN: consulta de turnos y generación de mapas por sector
# =============================================================================

fecha_proceso <- "2026-05-25"   # <-- ajustar la fecha de consulta

# --- Consultar ambos turnos --------------------------------------------------
datos_por_turno <- list(
  Matutino   = obtener_posiciones_por_turno(df_flota, fecha_proceso, "Matutino"),
  Vespertino = obtener_posiciones_por_turno(df_flota, fecha_proceso, "Vespertino")
)

# --- Cargar capa territorial desde disco (sin conectar a Postgres) -----------
capa_intra <- cargar_capa_local_postgres("Intradomiciliario_operativo")

sectores <- unique(capa_intra$nombre)

# --- Loop externo: por turno -------------------------------------------------
for (turno in names(datos_por_turno)) {

  capa_recorrido_original <- datos_por_turno[[turno]]

  # Si no hay datos para este turno, saltamos completamente
  if (is.null(capa_recorrido_original) || nrow(capa_recorrido_original) == 0) {
    message(paste("⚠️  Sin datos para el turno", turno, "- Saltando turno completo."))
    next
  }

  message(paste("\n====== Procesando turno:", turno, "| Fecha:", fecha_proceso, "======"))

  # Carpeta de salida específica del turno (se crea si no existe)
  carpeta_turno <- file.path("salidas", "mapas", turno)
  if (!dir.exists(carpeta_turno)) dir.create(carpeta_turno, recursive = TRUE)

  # --- Loop interno: por sector ----------------------------------------------
  for (sector_nombre in sectores) {

    message(paste("  Procesando sector:", sector_nombre))

    # 1. Filtrar capa territorial
    capa_filtrada <- capa_intra[capa_intra$nombre == sector_nombre, ]

    # 2. Intersección: puntos del recorrido dentro del sector
    capa_recorrido   <- st_transform(capa_recorrido_original, st_crs(capa_filtrada))
    puntos_solapados <- st_intersection(capa_recorrido, capa_filtrada)

    if (nrow(puntos_solapados) == 0) {
      message(paste("  Sin datos de recorrido para:", sector_nombre, "- Saltando..."))
      next
    }

    # 3. Enriquecer con información de flota (servicio asignado)
    matricula_ref       <- puntos_solapados$matricula[1]
    servicio_encontrado <- df_flota %>%
      filter(Matricula == matricula_ref) %>%
      pull(Servicio)

    if (length(servicio_encontrado) > 0) {
      puntos_solapados <- puntos_solapados %>%
        mutate(FRACCION = servicio_encontrado[1])
    }

    # 4. Nombre de archivo: YYYY-MM-DD_Mapa_NombreSector_TURNO.html
    nombre_limpio <- gsub("[^[:alnum:]]", "_", sector_nombre)
    nombre_archivo <- paste0(fecha_proceso, "_Mapa_", nombre_limpio, "_", toupper(turno), ".html")
    salida_html    <- file.path(carpeta_turno, nombre_archivo)

    # 5. Guardar capas como GeoJSON temporales para Python
    temp_path_intra  <- tempfile(fileext = ".geojson")
    temp_path_puntos <- tempfile(fileext = ".geojson")
    st_write(capa_filtrada,    temp_path_intra,  driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
    st_write(puntos_solapados, temp_path_puntos, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)

    # 6. Generar mapa interactivo con Python
    system2(python_venv, args = c("vistas/mapas/mapa_intro_dibujarutas.py",
                                  temp_path_intra,
                                  temp_path_puntos,
                                  salida_html))

    # Mapa estático (descomentar si se necesita):
    # nombre_png  <- paste0(fecha_proceso, "_Estatico_", nombre_limpio, "_", toupper(turno), ".png")
    # salida_png  <- file.path(carpeta_turno, nombre_png)
    # system2(python_venv, args = c("vistas/mapas/mapa_intra_estatico.py",
    #                               temp_path_intra, temp_path_puntos, salida_png))

    message(paste("  ✅ Generado:", nombre_archivo))
  }

  message(paste("====== Turno", turno, "finalizado. ======\n"))
}


# =============================================================================
# SECCIÓN EN DESARROLLO (mantener al final hasta consolidar)
# =============================================================================

# Grupos disponibles en la API:
#   sisconve - Vehículos propios de la IM
#   waste    - Transportistas de residuos privados
#   crane    - Grúas
#   hired    - Vehículos de alquiler

obtener_posiciones <- function(matricula, desde, hasta, grupo = "sisconve", stops_only = FALSE) {

  base_url <- "https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones"

  req <- request(base_url) %>%
    req_url_query(
      matricula     = matricula,
      fechaDesde    = desde,
      fechaHasta    = hasta,
      grupo         = grupo,
      showStopsOnly = tolower(as.character(stops_only))
    )

  resp  <- req_perform(req)
  datos <- resp %>% resp_body_json(simplifyVector = TRUE)

  return(datos)
}

# Ejemplo de uso:
# df_posiciones <- obtener_posiciones("SIM3024", "2026-04-10T13:49:11", "2026-04-14T13:49:11")

### HAY QUE LLAMAR ANTES EN CONEXIONPOSTRES LAS MATRICULAS

obtener_posiciones_por_turno_v2 <- function(df, fecha, turno) {

  # 1. Definir horas según el turno
  if (turno == "Matutino") {
    hora_inicio <- "06:00:00"
    hora_fin    <- "13:59:59"
  } else if (turno == "Vespertino") {
    hora_inicio <- "14:00:00"
    hora_fin    <- "22:00:00"
  } else {
    stop("Turno no válido. Debe ser 'Matutino' o 'Vespertino'.")
  }

  desde <- paste0(fecha, "T", hora_inicio)
  hasta <- paste0(fecha, "T", hora_fin)

  message(paste("Consultando turno", turno, "para la fecha", fecha, "..."))

  # 2. Llamada a la API (map_dfr deprecado en purrr >= 1.0; usar map + list_rbind)
  resultado <- df$Matricula %>%
    map(\(x) obtener_posiciones(matricula = x, desde = desde, hasta = hasta)) %>%
    list_rbind()

  if (nrow(resultado) == 0) {
    message("No se encontraron posiciones.")
    return(NULL)
  }

  # 3. Procesamiento espacial
  resultado_sf <- resultado %>%
    unpack(coordenadas) %>%
    hoist(coordinates, lon = 1, lat = 2) %>%
    mutate(
      lon = as.numeric(lon),
      lat = as.numeric(lat)
    ) %>%
    filter(!is.na(lon) & !is.na(lat)) %>%
    st_as_sf(coords = c("lon", "lat"), crs = 4326)

  return(resultado_sf)
}

# df_matutino  <- obtener_posiciones_por_turno_v2(df_flota, "2026-04-15", "Matutino")
# df_vespertino <- obtener_posiciones_por_turno_v2(df_flota, "2026-04-15", "Vespertino")

# Loop por sector (versión con script mapa_intra.py sin salida_html explícita)
# capa_recorrido_original <- df_matutino
# sectores <- unique(capa_intra$nombre)
#
# for (sector_nombre in sectores) {
#   capa_filtrada    <- capa_intra[capa_intra$nombre == sector_nombre, ]
#   temp_path_intra  <- tempfile(fileext = ".geojson")
#   st_write(capa_filtrada, temp_path_intra, driver = "GeoJSON", delete_dsn = TRUE)
#
#   capa_recorrido   <- st_transform(capa_recorrido_original, st_crs(capa_filtrada))
#   puntos_solapados <- st_intersection(capa_recorrido, capa_filtrada)
#
#   if (nrow(puntos_solapados) == 0) { next }
#
#   matricula_ref       <- puntos_solapados$matricula[1]
#   servicio_encontrado <- df_flota %>% filter(Matricula == matricula_ref) %>% pull(Servicio)
#   if (length(servicio_encontrado) > 0) {
#     puntos_solapados <- puntos_solapados %>% mutate(FRACCION = servicio_encontrado[1])
#   }
#
#   temp_path_puntos <- tempfile(fileext = ".geojson")
#   st_write(puntos_solapados, temp_path_puntos, driver = "GeoJSON", delete_dsn = TRUE)
#
#   system2(python_venv, args = c("vistas/mapas/mapa_intra.py", temp_path_intra, temp_path_puntos))
#   system2(python_venv, args = c("vistas/mapas/mapa_intra_estatico.py", temp_path_intra, temp_path_puntos))
# }