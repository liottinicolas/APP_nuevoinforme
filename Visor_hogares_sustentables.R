# =============================================================================
# VISOR DE VEHÍCULOS EN HOGARES SUSTENTABLES
# =============================================================================
# Este script realiza la consulta de turnos de la flota de camiones de la IMM
# a través de la API intranet y genera mapas interactivos en R con Leaflet
# detallando el recorrido de los vehículos dentro de cada sector de la capa
# territorial "Hogares_sustentables".
# =============================================================================

library(httr2)
library(jsonlite)
library(dplyr)
library(sf)
library(purrr)
library(leaflet)
library(htmltools)
library(htmlwidgets)

# Cargar conexión a Postgres y definición de la flota (df_flota)
source("db/POSTGRES/conexionPOSTGRES.R")

# =============================================================================
# SECCIÓN 1: FUNCIONES DE CONSULTA A LA API (Lógica de prueba_api.R)
# =============================================================================

#' Consulta detallada a la API de visor de vehículos IMM
#'
#' @param matricula   Matrícula del vehículo (ej: "SIM3127")
#' @param fecha_desde Fecha de inicio (ej: "2026-05-23")
#' @param hora_desde  Hora de inicio (ej: "06:00:00")
#' @param fecha_hasta Fecha de fin (ej: "2026-05-23")
#' @param hora_hasta  Hora de fin (ej: "13:59:59")
#' @param grupo       Grupo de flota (por defecto "sisconve")
#' @param solo_paradas Si es TRUE, solicita showStopsOnly = "true" a la API
#' @return Un sf data frame o NULL
probar_conexion_api <- function(matricula,
                                fecha_desde, hora_desde = "00:00:00",
                                fecha_hasta, hora_hasta = "23:59:59",
                                grupo = "sisconve",
                                solo_paradas = FALSE) {
  f_desde <- paste0(as.character(as.Date(fecha_desde)), "T", hora_desde)
  f_hasta <- paste0(as.character(as.Date(fecha_hasta)), "T", hora_hasta)

  base_url <- "https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones"

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

  resp <- tryCatch(
    req_perform(req),
    error = function(e) {
      return(NULL)
    }
  )

  if (is.null(resp)) {
    return(NULL)
  }

  texto_crudo <- resp_body_string(resp)

  if (nchar(texto_crudo) == 0) {
    return(NULL)
  }

  datos_raw <- tryCatch(
    fromJSON(texto_crudo, simplifyVector = TRUE),
    error = function(e) {
      return(NULL)
    }
  )

  if (is.null(datos_raw) || length(datos_raw) == 0) {
    return(NULL)
  }

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
      return(NULL)
    }
  )

  return(df_sf)
}


#' Consulta de posiciones de toda la flota por turno
#'
#' @param df_matriculas Un data frame que contenga una columna llamada 'Matricula'
#' @param fecha         Fecha a consultar en formato 'YYYY-MM-DD'
#' @param turno         Turno a consultar ('Matutino' o 'Vespertino')
#' @param solo_paradas  Si es TRUE, solicita únicamente las paradas a la API
#' @return Un objeto 'sf' con las posiciones unificadas de todos los vehículos, o NULL
consultar_posiciones_flota_por_turno_interna <- function(df_matriculas, fecha, turno, solo_paradas = FALSE) {
  if (turno == "Matutino") {
    hora_inicio <- "06:00:00"
    hora_fin <- "13:59:59"
  } else if (turno == "Vespertino") {
    hora_inicio <- "14:00:00"
    hora_fin <- "22:00:00"
  } else {
    stop("Turno no válido. Debe ser 'Matutino' o 'Vespertino'.")
  }

  message(paste("🚀 Consultando posiciones flota para turno:", turno, "| Fecha:", fecha))

  if (!"Matricula" %in% names(df_matriculas)) {
    if ("matricula" %in% names(df_matriculas)) {
      df_matriculas <- df_matriculas %>% rename(Matricula = matricula)
    } else {
      stop("El data frame de matrículas debe contener una columna llamada 'Matricula'.")
    }
  }

  lista_resultados <- df_matriculas$Matricula %>%
    map(function(m) {
      res <- probar_conexion_api(
        matricula    = m,
        fecha_desde  = fecha, hora_desde = hora_inicio,
        fecha_hasta  = fecha, hora_hasta = hora_fin,
        solo_paradas = solo_paradas
      )
      return(res)
    })

  resultado_final <- bind_rows(lista_resultados)

  if (is.null(resultado_final) || nrow(resultado_final) == 0) {
    return(NULL)
  }

  return(resultado_final)
}


#' Consulta de posiciones de toda la flota separando por turnos (Matutino y Vespertino)
#'
#' @param df_matriculas Un data frame que contenga una columna 'Matricula' o 'matricula'
#' @param fecha         Fecha a consultar en formato 'YYYY-MM-DD'
#' @param solo_paradas  Si es TRUE, solicita únicamente las paradas a la API
#' @return Una lista nombrada con los turnos procesados (ej: list(Matutino = sf_df, Vespertino = sf_df))
obtener_posiciones_flota_ambos_turnos_api <- function(df_matriculas, fecha, solo_paradas = FALSE) {
  turnos <- c("Matutino", "Vespertino")
  resultados <- list()

  for (t in turnos) {
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

# =============================================================================
# SECCIÓN 2: FUNCIONES DE VISUALIZACIÓN LEAFLET (Lógica de prueba_api.R)
# =============================================================================

#' Grafica el sector de Hogar Sustentable y el recorrido de los vehículos
#' utilizando Leaflet, iconos personalizados IMM y panel de filtro interactivo.
#'
#' @param df_sf           Objeto 'sf' de puntos detectados con columna Turno_Consulta
#' @param sector_polygon  Objeto 'sf' del sector de Hogares Sustentables
#' @param usar_iconos     Si es TRUE (por defecto), dibuja iconos de pausa/flecha compactos
#' @return Un objeto widget de Leaflet listo para mostrar o guardar
graficar_mapa_hogar_sector <- function(df_sf, sector_polygon, usar_iconos = TRUE, fecha = NULL, turno = NULL) {
  # Inicializar mapa
  mapa <- leaflet() %>%
    addProviderTiles(providers$CartoDB.Positron)

  # 1. Dibujar el sector de Hogar Sustentable (en Azul de Hogares Sustentables)
  if (!is.null(sector_polygon) && nrow(sector_polygon) > 0) {
    # Transformar a WGS84 para Leaflet
    sector_wgs84 <- st_transform(sector_polygon, 4326)

    mapa <- mapa %>%
      addPolygons(
        data = sector_wgs84,
        color = "#0066CC",
        weight = 3,
        fillColor = "#0066CC",
        fillOpacity = 0.20,
        group = "Capas Territoriales",
        popup = paste0(
          "<b>Hogar Sustentable</b><br>",
          "Nombre: ", sector_wgs84$nombre, "<br>",
          "Modalidad: ", if ("modalidad" %in% names(sector_wgs84)) sector_wgs84$modalidad else "N/A", "<br>",
          "Turno Mezcla: ", if ("turno_mez" %in% names(sector_wgs84)) sector_wgs84$turno_mez else "N/A", "<br>",
          "Frecuencia Mezcla: ", if ("frec_mez" %in% names(sector_wgs84)) sector_wgs84$frec_mez else "N/A", "<br>",
          "Días Mezcla: ", if ("dias_mez" %in% names(sector_wgs84)) sector_wgs84$dias_mez else "N/A", "<br>",
          "Turno Reciclable: ", if ("turno_rec" %in% names(sector_wgs84)) sector_wgs84$turno_rec else "N/A", "<br>",
          "Días Reciclable: ", if ("dias_rec" %in% names(sector_wgs84)) sector_wgs84$dias_rec else "N/A", "<br>",
          "Tipo Reciclable: ", if ("tipo_rec" %in% names(sector_wgs84)) sector_wgs84$tipo_rec else "N/A"
        ),
        label = ~ paste0("Hogar: ", nombre)
      )
  }

  # 2. Dibujar puntos de recorrido del vehículo
  puntos <- df_sf
  if (!is.null(puntos) && nrow(puntos) > 0) {
    puntos_web <- st_transform(puntos, 4326)
    coords <- st_coordinates(puntos_web)

    # Centrar el mapa en los puntos detectados
    mapa <- mapa %>%
      setView(lng = mean(coords[, 1]), lat = mean(coords[, 2]), zoom = 15)

    if (usar_iconos) {
      for (i in 1:nrow(puntos_web)) {
        vel_val <- puntos_web$velocidad[i]
        orient <- puntos_web$orientacion[i]
        tiempo <- puntos_web$tiempo[i]
        mat <- puntos_web$matricula[i]
        turno_c <- if ("Turno_Consulta" %in% names(puntos_web)) puntos_web$Turno_Consulta[i] else "N/A"

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
          # Icono de parada: Círculo naranja con pausa
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
          # Icono de movimiento: Círculo verde con flecha
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

        # Dibujar en "Todos"
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

        # Dibujar en el grupo específico ("Detenidos" o "Movimiento")
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
      # Círculos vectorizados simples
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
    # Centrar en el sector si no hay puntos detectados
    if (!is.null(sector_polygon) && nrow(sector_polygon) > 0) {
      sector_wgs84 <- st_transform(sector_polygon, 4326)
      coords_base <- st_coordinates(st_centroid(st_union(sector_wgs84)))
      mapa <- mapa %>%
        setView(lng = coords_base[1, 1], lat = coords_base[1, 2], zoom = 15)
    }
  }

  # 3. Agregar control de capas interactivo (baseGroups)
  mapa <- mapa %>%
    addLayersControl(
      baseGroups = c("Todos", "Detenidos", "Movimiento"),
      overlayGroups = c("Capas Territoriales"),
      options = layersControlOptions(collapsed = FALSE)
    )

  # 4. Agregar cartel informativo en la esquina superior izquierda
  turno_val <- if (!is.null(turno)) {
    turno
  } else if (!is.null(puntos) && nrow(puntos) > 0 && "Turno_Consulta" %in% names(puntos)) {
    puntos$Turno_Consulta[1]
  } else {
    "Ambos"
  }

  fecha_val <- if (!is.null(fecha)) {
    fecha
  } else if (!is.null(puntos) && nrow(puntos) > 0) {
    substr(puntos$tiempo[1], 1, 10)
  } else {
    "N/A"
  }

  zona_val <- "N/A"
  if (!is.null(sector_polygon) && nrow(sector_polygon) > 0) {
    if ("nombre" %in% names(sector_polygon)) {
      zona_val <- sector_polygon$nombre[1]
    }
  }

  # Formatear fecha a DD/MM/YYYY si viene en formato YYYY-MM-DD
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", fecha_val)) {
    parts <- strsplit(fecha_val, "-")[[1]]
    fecha_formateada <- paste0(parts[3], "/", parts[2], "/", parts[1])
  } else {
    fecha_formateada <- fecha_val
  }

  vehicles_html <- ""
  if (!is.null(puntos) && nrow(puntos) > 0) {
    puntos_copia <- puntos
    tiempo_char <- as.character(puntos_copia$tiempo)
    clean_tiempo <- gsub("T", " ", tiempo_char)
    clean_tiempo <- gsub("Z", "", clean_tiempo)
    clean_tiempo <- gsub("\\+.*", "", clean_tiempo)

    tiempos_convertidos <- as.POSIXct(rep(NA, length(clean_tiempo)))

    # 1. Formato YYYY-MM-DD HH:MM:SS
    idx_ymd <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", clean_tiempo)
    if (any(idx_ymd)) {
      tiempos_convertidos[idx_ymd] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_ymd], format = "%Y-%m-%d %H:%M:%S"),
        error = function(e) as.POSIXct(rep(NA, sum(idx_ymd)))
      )
    }

    # 2. Formato DD-MM-YYYY HH:MM:SS
    idx_dmy <- grepl("^[0-9]{2}-[0-9]{2}-[0-9]{4}", clean_tiempo)
    if (any(idx_dmy)) {
      tiempos_convertidos[idx_dmy] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_dmy], format = "%d-%m-%Y %H:%M:%S"),
        error = function(e) as.POSIXct(rep(NA, sum(idx_dmy)))
      )
    }

    # 3. Fallback automático de R
    idx_na <- is.na(tiempos_convertidos) & !is.na(clean_tiempo) & clean_tiempo != ""
    if (any(idx_na)) {
      tiempos_convertidos[idx_na] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_na]),
        error = function(e) as.POSIXct(rep(NA, sum(idx_na)))
      )
    }

    puntos_copia$tiempo_posix <- tiempos_convertidos
    matriculas_unicas <- sort(unique(puntos_copia$matricula))
    vehicles_str_list <- c()

    for (mat in matriculas_unicas) {
      idx_mat <- puntos_copia$matricula == mat
      tiempos_mat <- puntos_copia$tiempo_posix[idx_mat]
      tiempos_mat <- tiempos_mat[!is.na(tiempos_mat)]
      
      # Obtener FRACCION para este vehículo
      fraccion_val <- "N/A"
      if ("FRACCION" %in% names(puntos_copia)) {
        val_frac <- unique(puntos_copia$FRACCION[idx_mat])
        val_frac <- val_frac[!is.na(val_frac) & val_frac != ""]
        if (length(val_frac) > 0) {
          fraccion_val <- val_frac[1]
        }
      }

      if (length(tiempos_mat) > 0) {
        tiempos_mat <- sort(tiempos_mat)
        
        # Segmentar en visitas usando un gap de 20 minutos (tz = "UTC" para coincidir exactamente con los popups del mapa)
        if (length(tiempos_mat) == 1) {
          visitas_str <- format(tiempos_mat[1], "%H:%M:%S", tz = "UTC")
        } else {
          diff_mins <- as.numeric(difftime(tiempos_mat[-1], tiempos_mat[-length(tiempos_mat)], units = "mins"))
          saltos <- which(diff_mins > 20)
          
          inicio_indices <- c(1, saltos + 1)
          fin_indices <- c(saltos, length(tiempos_mat))
          
          visitas_str_vector <- character(length(inicio_indices))
          for (v in seq_along(inicio_indices)) {
            t_ini <- tiempos_mat[inicio_indices[v]]
            t_fin <- tiempos_mat[fin_indices[v]]
            
            if (t_ini == t_fin) {
              visitas_str_vector[v] <- format(t_ini, "%H:%M:%S", tz = "UTC")
            } else {
              visitas_str_vector[v] <- paste0(format(t_ini, "%H:%M:%S", tz = "UTC"), " - ", format(t_fin, "%H:%M:%S", tz = "UTC"))
            }
          }
          visitas_str <- paste(visitas_str_vector, collapse = " | ")
        }
        
        # Crear bloque del vehículo
        vehicles_str_list <- c(
          vehicles_str_list,
          paste0(
            '<div style="margin-bottom: 8px;">',
            '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Matrícula:</span> ', mat, '<br>',
            '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Horario:</span> ', visitas_str,
            '</div>'
          )
        )
      } else {
        # Fallback de seguridad por strings si la conversión a POSIXct resulta en NA
        raw_tiempos_mat <- sort(clean_tiempo[idx_mat])
        if (length(raw_tiempos_mat) > 0) {
          extraer_hora <- function(x) {
            h <- regmatches(x, regexpr("[0-9]{2}:[0-9]{2}:[0-9]{2}", x))
            if (length(h) > 0) h[1] else substr(x, 12, 19)
          }
          inicio_raw <- extraer_hora(raw_tiempos_mat[1])
          fin_raw <- extraer_hora(raw_tiempos_mat[length(raw_tiempos_mat)])
          
          vehicles_str_list <- c(
            vehicles_str_list,
            paste0(
              '<div style="margin-bottom: 8px;">',
              '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Matrícula:</span> ', mat, '<br>',
              '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Horario:</span> ', inicio_raw, ' - ', fin_raw,
              '</div>'
            )
          )
        }
      }
    }
    
    vehicles_html <- paste(vehicles_str_list, collapse = "")
  } else {
    vehicles_html <- '<div style="text-align: center; font-style: italic; color: rgba(255,255,255,0.75);">SIN VEHÍCULOS DETECTADOS</div>'
  }

  logo_html <- ""
  if (file.exists("logoazul_transparent.png") && requireNamespace("base64enc", quietly = TRUE)) {
    tryCatch({
      logo_base64 <- base64enc::dataURI(file = "logoazul_transparent.png", mime = "image/png")
      logo_html <- paste0(
        '<div style="background-color: #0050D0; padding: 12px 10px; text-align: center; border-bottom: 1px solid rgba(255,255,255,0.2);">',
        '<img src="', logo_base64, '" style="max-height: 35px; max-width: 140px; display: block; margin: 0 auto;">',
        '</div>'
      )
    }, error = function(e) {
      # Fallback silencioso
    })
  } else if (file.exists("logoazul.png") && requireNamespace("base64enc", quietly = TRUE)) {
    tryCatch({
      logo_base64 <- base64enc::dataURI(file = "logoazul.png", mime = "image/png")
      logo_html <- paste0(
        '<div style="background-color: white; padding: 10px; text-align: center; border-bottom: 1px solid rgba(0,0,0,0.1);">',
        '<img src="', logo_base64, '" style="max-height: 35px; max-width: 140px; display: block; margin: 0 auto;">',
        '</div>'
      )
    }, error = function(e) {
      # Fallback silencioso
    })
  }

  cartel_html <- paste0(
    '<div style="',
    "background-color: #0050D0; ",
    "color: white; ",
    "border-radius: 8px; ",
    "overflow: hidden; ",
    "font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; ",
    "font-size: 12px; ",
    "line-height: 1.5; ",
    "box-shadow: 0px 4px 15px rgba(0,0,0,0.25); ",
    "width: 250px; ",
    '">',
    # Logo
    logo_html,
    # Contenido con padding
    '<div style="padding: 14px 18px;">',
    # Title
    '<div style="font-size: 13px; font-weight: 800; text-align: center; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px;">',
    'MAPA DE VEHÍCULOS',
    '</div>',
    '<hr style="border: none; border-top: 1px solid rgba(255,255,255,0.25); margin: 4px 0 10px 0;">',
    # Info body
    '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Día:</span> ', fecha_formateada, '<br>',
    '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Turno:</span> ', toupper(turno_val), '<br>',
    '<span style="font-weight: 700; color: rgba(255,255,255,0.95);">Zona:</span> ', toupper(zona_val),
    # Separator for Vehicles
    '<hr style="border: none; border-top: 1px solid rgba(255,255,255,0.15); margin: 8px 0 8px 0;">',
    # Vehicles list
    vehicles_html,
    '</div>',
    '</div>'
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

  return(mapa)
}


#' Exporta el recorrido de un sector de Hogar Sustentable a un archivo HTML interactivo
#'
#' @param df_sf           Objeto 'sf' de puntos detectados
#' @param sector_polygon  Objeto 'sf' del sector de Hogares Sustentables
#' @param salida_html     Ruta del archivo HTML de salida
#' @param usar_iconos     Si es TRUE (por defecto), dibuja iconos de pausa/flecha compactos
#' @return TRUE si se guardó con éxito, FALSE en caso contrario
exportar_mapa_hogares_sector <- function(df_sf, sector_polygon, salida_html, usar_iconos = TRUE, fecha = NULL, turno = NULL) {
  mapa <- graficar_mapa_hogar_sector(df_sf = df_sf, sector_polygon = sector_polygon, usar_iconos = usar_iconos, fecha = fecha, turno = turno)

  if (is.null(mapa)) {
    return(FALSE)
  }

  dir_salida <- dirname(salida_html)
  if (!dir.exists(dir_salida)) {
    dir.create(dir_salida, recursive = TRUE)
  }

  # Limpieza preventiva de carpetas residuales *_files en el directorio de salida
  tryCatch({
    carpetas_residuos <- list.dirs(dir_salida, full.names = TRUE, recursive = FALSE)
    carpetas_residuos <- carpetas_residuos[grepl("_files$", carpetas_residuos)]
    if (length(carpetas_residuos) > 0) {
      unlink(carpetas_residuos, recursive = TRUE, force = TRUE)
    }
  }, error = function(e) {})

  # Obtener el nombre del sector para el título del HTML
  sector_nombre <- "N/A"
  if (!is.null(sector_polygon) && nrow(sector_polygon) > 0 && "nombre" %in% names(sector_polygon)) {
    sector_nombre <- sector_polygon$nombre[1]
  }

  # Construir título de la página
  mapa_titulo <- paste("Mapa de Vehículos -", sector_nombre)
  if (!is.null(fecha)) {
    # Formatear fecha a DD/MM/YYYY si viene en formato YYYY-MM-DD
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", fecha)) {
      parts <- strsplit(fecha, "-")[[1]]
      fecha_formateada <- paste0(parts[3], "/", parts[2], "/", parts[1])
    } else {
      fecha_formateada <- fecha
    }
    mapa_titulo <- paste(mapa_titulo, "-", fecha_formateada)
  }
  if (!is.null(turno)) {
    mapa_titulo <- paste(mapa_titulo, "-", toupper(turno))
  }

  # Configurar pandoc desde rmarkdown si está disponible (evita fallos de compilación selfcontained)
  if (requireNamespace("rmarkdown", quietly = TRUE)) {
    tryCatch({
      pandoc_info <- rmarkdown::find_pandoc()
      if (!is.null(pandoc_info$dir)) {
        Sys.setenv(RSTUDIO_PANDOC = pandoc_info$dir)
        Sys.setenv(PATH = paste(pandoc_info$dir, Sys.getenv("PATH"), sep = ";"))
      }
    }, error = function(e) {})
  }

  # Guardar en directorio temporal y copiar al destino para evitar creación de carpetas de paquetes
  temp_html <- tempfile(fileext = ".html")

  tryCatch(
    {
      saveWidget(mapa, file = temp_html, selfcontained = TRUE, title = mapa_titulo)
      
      # Eliminar carpeta de dependencias temporal si saveWidget la creó en R's temp dir
      temp_base <- tools::file_path_sans_ext(temp_html)
      dir_residuos_temp <- paste0(temp_base, "_files")
      if (dir.exists(dir_residuos_temp)) {
        unlink(dir_residuos_temp, recursive = TRUE, force = TRUE)
      }

      if (file.exists(temp_html)) {
        file.copy(temp_html, salida_html, overwrite = TRUE)
        file.remove(temp_html)
        
        # Limpieza posterior de carpetas residuales *_files en el directorio de salida por si acaso
        tryCatch({
          carpetas_residuos <- list.dirs(dir_salida, full.names = TRUE, recursive = FALSE)
          carpetas_residuos <- carpetas_residuos[grepl("_files$", carpetas_residuos)]
          if (length(carpetas_residuos) > 0) {
            unlink(carpetas_residuos, recursive = TRUE, force = TRUE)
          }
        }, error = function(e) {})
        
        return(TRUE)
      } else {
        return(FALSE)
      }
    },
    error = function(e) {
      message("❌ Error al guardar el widget HTML:")
      print(e)
      if (file.exists(temp_html)) file.remove(temp_html)
      # Limpieza en caso de error
      tryCatch({
        carpetas_residuos <- list.dirs(dir_salida, full.names = TRUE, recursive = FALSE)
        carpetas_residuos <- carpetas_residuos[grepl("_files$", carpetas_residuos)]
        if (length(carpetas_residuos) > 0) {
          unlink(carpetas_residuos, recursive = TRUE, force = TRUE)
        }
      }, error = function(e) {})
      return(FALSE)
    }
  )
}

# =============================================================================
# SECCIÓN 3: BUCLE DE EJECUCIÓN (Replicando Visor_vehiculos.R)
# =============================================================================

# --- Ajustar parámetros de ejecución ---
fecha_proceso <- "2026-05-26" # <-- Ajustar la fecha de consulta aquí
tolerancia_metros <- 50 # <-- Buffer en metros para visualización en el mapa (captura amplia)
umbral_validacion_metros <- 15 # <-- Buffer en metros para validar que el vehículo ingresó al sector (validación estrecha)
min_paradas_vehiculo <- 10 # <-- Mínimo de paradas (velocidad == 0) por camión para ser registrado e incluido
distancia_recorte_puntos <- 10 # <-- Distancia máxima en metros al polígono original para incluir un punto en el mapa (limpieza de perimetrales)
distancia_erosion_metros <- 20 # <-- Distancia de erosión en metros para definir el núcleo interno (excluir calles limítrofes)
min_cobertura_diagonal <- 0.35 # <-- Proporción mínima de extensión diagonal (35%) del núcleo que deben cubrir los puntos del camión (evita pasos por una sola calle o esquinas)
min_ratio_area <- 0.08 # <-- Proporción mínima de área del convex hull (8%) en el núcleo (evita tránsitos lineales o colineales por una sola calle)
min_tiempo_permanencia_minutos <- 30 # <-- Tiempo mínimo en minutos de permanencia del vehículo dentro del sector para ser incluido (excluye camiones de paso rápido)
usar_iconos_proc <- FALSE # <-- Poner en FALSE para círculos simples, TRUE para iconos personalizados IMM
modalidades_filtro <- c("intradomiciliario") # <-- Filtro por modalidad (ej: c("intradomiciliario") o c("intradomiciliario", "intrapredial") o NULL para todos)




message("\n=========================================================================")
message(paste("🚀 INICIANDO PROCESO BATCH PARA SECTORES HOGARES SUSTENTABLES"))
message(paste("📅 Fecha Proceso:", fecha_proceso, "| Tolerancia Espacial:", tolerancia_metros, "metros"))
if (!is.null(modalidades_filtro)) {
  message(paste("📋 Filtrando modalidades:", paste(modalidades_filtro, collapse = ", ")))
}
message("=========================================================================")

# 1. Consultar posiciones de toda la flota para ambos turnos a través de la API
datos_por_turno <- obtener_posiciones_flota_ambos_turnos_api(
  df_matriculas = df_flota,
  fecha         = fecha_proceso,
  solo_paradas  = FALSE
)

# 2. Cargar capa territorial local de Hogares Sustentables
capa_hogares <- cargar_capa_local_postgres("Hogares_sustentables")

# Aplicar filtro por modalidad si está especificado
if (!is.null(modalidades_filtro) && length(modalidades_filtro) > 0) {
  capa_hogares <- capa_hogares %>%
    filter(tolower(modalidad) %in% tolower(modalidades_filtro))
}

sectores <- unique(capa_hogares$nombre)

message(paste("ℹ️ Capa territorial cargada. Total de sectores a procesar:", length(sectores)))

# 3. Iteración sobre turnos (Matutino y Vespertino)
for (turno in names(datos_por_turno)) {
  capa_recorrido_original <- datos_por_turno[[turno]]

  # Si no hay datos para este turno, saltamos completamente
  if (is.null(capa_recorrido_original) || nrow(capa_recorrido_original) == 0) {
    message(paste("⚠️ Sin datos de la API para el turno", turno, "- Saltando turno completo."))
    next
  }

  message(paste("\n======================================================="))
  message(paste("🔄 PROCESANDO TURNO:", toupper(turno)))
  message(paste("======================================================="))

  # Carpeta de salida específica del turno (se crea si no existe)
  nombre_carpeta_fecha <- paste0(fecha_proceso, " recoleccion Hogares sustentables")
  carpeta_turno <- file.path("vistas", "mapas", nombre_carpeta_fecha, turno)
  if (!dir.exists(carpeta_turno)) dir.create(carpeta_turno, recursive = TRUE)

  # 4. Iteración sobre cada sector de Hogares Sustentables
  for (sector_nombre in sectores) {
    if (is.na(sector_nombre) || sector_nombre == "") next

    message(paste("  🔍 Sector:", sector_nombre))

    # Filtrar el polígono del sector actual
    capa_filtrada <- capa_hogares[capa_hogares$nombre == sector_nombre, ]

    # Intersección espacial: Proyectar temporalmente a UTM 21S (EPSG:32721) para buffer métrico
    capa_filtrada_proj <- st_transform(capa_filtrada, 32721)
    capa_recorrido_proj <- st_transform(capa_recorrido_original, 32721)

    # Aplicar el buffer al sector para tener una tolerancia
    if (tolerancia_metros > 0) {
      capa_filtrada_buffered <- st_buffer(capa_filtrada_proj, dist = tolerancia_metros)
    } else {
      capa_filtrada_buffered <- capa_filtrada_proj
    }

    # Intersección espacial
    puntos_solapados_proj <- st_intersection(capa_recorrido_proj, capa_filtrada_buffered)

    if (nrow(puntos_solapados_proj) == 0) {
      message(paste("    ↳ Sin vehículos solapados en este sector. Saltando."))
      next
    }

    # =========================================================================
    # FILTRO POR MÍNIMO DE PARADAS REALES POR VEHÍCULO
    # =========================================================================
    # Identificar qué camiones se detuvieron al menos 'min_paradas_vehiculo' veces
    camiones_validos <- puntos_solapados_proj %>%
      as.data.frame() %>%
      group_by(matricula) %>%
      summarise(paradas = sum(velocidad == 0, na.rm = TRUE), .groups = "drop") %>%
      filter(paradas >= min_paradas_vehiculo) %>%
      pull(matricula)

    # Conservar únicamente los puntos correspondientes a esos camiones
    puntos_solapados_proj <- puntos_solapados_proj %>%
      filter(matricula %in% camiones_validos)

    if (nrow(puntos_solapados_proj) == 0) {
      message(paste("    ↳ ⚠️ Ningún vehículo alcanzó el mínimo de", min_paradas_vehiculo, "paradas. Saltando mapa."))
      next
    }
    # =========================================================================

    # =========================================================================
    # FILTRO POR TIEMPO MÍNIMO DE PERMANENCIA (Evitar camiones de paso rápido)
    # =========================================================================
    # Convertimos los tiempos a POSIXct para poder calcular la duración real en minutos de forma robusta
    tiempo_char <- as.character(puntos_solapados_proj$tiempo)
    clean_tiempo <- gsub("T", " ", tiempo_char)
    clean_tiempo <- gsub("Z", "", clean_tiempo)
    clean_tiempo <- gsub("\\+.*", "", clean_tiempo)

    tiempos_posix <- as.POSIXct(rep(NA, length(clean_tiempo)), tz = "UTC")

    # 1. Formato YYYY-MM-DD HH:MM:SS
    idx_ymd <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", clean_tiempo)
    if (any(idx_ymd)) {
      tiempos_posix[idx_ymd] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_ymd], format = "%Y-%m-%d %H:%M:%S", tz = "UTC"),
        error = function(e) as.POSIXct(rep(NA, sum(idx_ymd)), tz = "UTC")
      )
    }

    # 2. Formato DD-MM-YYYY HH:MM:SS
    idx_dmy <- grepl("^[0-9]{2}-[0-9]{2}-[0-9]{4}", clean_tiempo)
    if (any(idx_dmy)) {
      tiempos_posix[idx_dmy] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_dmy], format = "%d-%m-%Y %H:%M:%S", tz = "UTC"),
        error = function(e) as.POSIXct(rep(NA, sum(idx_dmy)), tz = "UTC")
      )
    }

    # 3. Fallback automático de R
    idx_na <- is.na(tiempos_posix) & !is.na(clean_tiempo) & clean_tiempo != ""
    if (any(idx_na)) {
      tiempos_posix[idx_na] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_na], tz = "UTC"),
        error = function(e) as.POSIXct(rep(NA, sum(idx_na)), tz = "UTC")
      )
    }

    puntos_solapados_proj$tiempo_posix <- tiempos_posix

    # Evaluar permanencia por camión considerando múltiples visitas independientes (excluyendo grandes saltos de tiempo)
    calcular_max_duracion_visita <- function(tiempos, gap_max_mins = 20) {
      if (length(tiempos) <= 1) return(0)
      
      tiempos_ordenados <- sort(tiempos)
      diff_mins <- as.numeric(difftime(tiempos_ordenados[-1], tiempos_ordenados[-length(tiempos_ordenados)], units = "mins"))
      
      # Encontrar dónde están los saltos de tiempo mayores al gap permitido (ej. 20 min de inactividad o salida del sector)
      saltos <- which(diff_mins > gap_max_mins)
      
      # Definir los límites de cada visita
      inicio_indices <- c(1, saltos + 1)
      fin_indices <- c(saltos, length(tiempos_ordenados))
      
      # Calcular la duración de cada visita individual
      duraciones <- numeric(length(inicio_indices))
      for (i in seq_along(inicio_indices)) {
        t_inicio <- tiempos_ordenados[inicio_indices[i]]
        t_fin    <- tiempos_ordenados[fin_indices[i]]
        duraciones[i] <- as.numeric(difftime(t_fin, t_inicio, units = "mins"))
      }
      
      return(max(duraciones, na.rm = TRUE))
    }

    camiones_duracion <- puntos_solapados_proj %>%
      as.data.frame() %>%
      filter(!is.na(tiempo_posix)) %>%
      group_by(matricula) %>%
      summarise(
        duracion_max_visita = calcular_max_duracion_visita(tiempo_posix, gap_max_mins = 20),
        .groups = "drop"
      ) %>%
      filter(duracion_max_visita >= min_tiempo_permanencia_minutos & !is.na(duracion_max_visita)) %>%
      pull(matricula)

    # Filtrar puntos solapados para mantener solo los camiones que cumplen el tiempo mínimo en al menos una visita continua
    puntos_solapados_proj <- puntos_solapados_proj %>%
      filter(matricula %in% camiones_duracion)

    if (nrow(puntos_solapados_proj) == 0) {
      message(paste("    ↳ ⚠️ Ningún vehículo permaneció más de los", min_tiempo_permanencia_minutos, "minutos mínimos. Saltando mapa."))
      next
    }
    # =========================================================================

    # =========================================================================
    # FILTRO DE NÚCLEO INTERNO, COBERTURA DIAGONAL Y DISPERSIÓN 2D (Evitar tránsitos lineales/colineales de una sola calle o esquina)
    # =========================================================================
    # Reducimos (erosionamos) el polígono original para obtener el "núcleo interno" (core)
    core_interno_proj <- st_buffer(capa_filtrada_proj, dist = -distancia_erosion_metros)

    # Validamos que el núcleo erosionado no sea una geometría vacía (para mapas pequeños/estrechos)
    if (nrow(core_interno_proj) > 0 && !any(st_is_empty(core_interno_proj))) {
      # Obtener qué puntos del camión caen dentro del núcleo interno
      puntos_en_core <- st_intersection(puntos_solapados_proj, core_interno_proj)

      if (nrow(puntos_en_core) == 0) {
        message(paste("    ↳ ⚠️ Tránsito únicamente perimetral (fuera del núcleo interno de", distancia_erosion_metros, "m). Saltando mapa."))
        next
      }

      # Evaluar si los puntos del camión cubren una extensión razonable del núcleo o si es solo un tránsito lineal/esquina
      bbox_core <- st_bbox(core_interno_proj)
      ancho_core <- bbox_core[["xmax"]] - bbox_core[["xmin"]]
      alto_core <- bbox_core[["ymax"]] - bbox_core[["ymin"]]
      diagonal_core <- sqrt(ancho_core^2 + alto_core^2)

      bbox_puntos <- st_bbox(puntos_en_core)
      ancho_puntos <- bbox_puntos[["xmax"]] - bbox_puntos[["xmin"]]
      alto_puntos <- bbox_puntos[["ymax"]] - bbox_puntos[["ymin"]]
      diagonal_puntos <- sqrt(ancho_puntos^2 + alto_puntos^2)

      cobertura_diagonal <- diagonal_puntos / diagonal_core

      if (cobertura_diagonal < min_cobertura_diagonal) {
        message(paste0("    ↳ ⚠️ Extensión interna insuficiente en el núcleo (", round(cobertura_diagonal * 100, 1), "% < ", round(min_cobertura_diagonal * 100, 1), "%). Tránsito lineal o de esquina. Saltando mapa."))
        next
      }

      # 2. Cobertura de área 2D (Convex Hull) para evitar collinearidad de una única calle diagonal/lineal
      chull_puntos <- st_convex_hull(st_union(puntos_en_core))
      area_chull <- as.numeric(st_area(chull_puntos))
      area_core <- as.numeric(st_area(st_union(core_interno_proj)))

      ratio_area <- ifelse(area_core > 0, area_chull / area_core, 0)

      if (ratio_area < min_ratio_area) {
        message(paste0("    ↳ ⚠️ Dispersión superficial insuficiente (", round(ratio_area * 100, 1), "% de área 2D < ", round(min_ratio_area * 100, 1), "%). Tránsito lineal por una sola calle. Saltando mapa."))
        next
      }
    }
    # =========================================================================

    # =========================================================================
    # RECORTE DE PUNTOS FUERA DEL MAPA Y VALIDACIÓN DE SERVICIO REAL
    # =========================================================================
    # 1. Calcular la distancia de todos los puntos solapados al polígono original (sin buffer)
    distancias_poligono <- as.numeric(st_distance(puntos_solapados_proj, st_union(capa_filtrada_proj)))
    distancia_minima <- min(distancias_poligono, na.rm = TRUE)

    # 2. RECORTE DE PUNTOS: Conservar únicamente los puntos que están a menos de 'distancia_recorte_puntos' del polígono real (ej. 10m)
    # Esto elimina visualmente todos los puntos que están en la periferia/frontera (ej: María Ramírez en La Teja)
    puntos_solapados_proj <- puntos_solapados_proj[distancias_poligono <= distancia_recorte_puntos, ]

    if (nrow(puntos_solapados_proj) == 0) {
      message(paste("    ↳ ⚠️ Todos los puntos del camión quedaron en la periferia fuera de los", distancia_recorte_puntos, "m del recorte. Saltando mapa."))
      next
    }

    # 3. Separar puntos que son paradas (velocidad == 0) entre los puntos ya recortados
    paradas_solapadas <- puntos_solapados_proj %>% filter(velocidad == 0)

    servicio_valido <- FALSE

    # Dado que los puntos ya fueron recortados a 'distancia_recorte_puntos', la distancia_minima será menor o igual a esta.
    # Evaluamos si hay paradas efectivas dentro del área recortada, o si pasó a menos de 5m (para evitar simples tránsitos rápidos de esquina).
    if (nrow(paradas_solapadas) > 0) {
      servicio_valido <- TRUE
    } else {
      # Si es todo en movimiento, requerimos cercanía extrema para validar ingreso
      nueva_dist_minima <- min(as.numeric(st_distance(puntos_solapados_proj, st_union(capa_filtrada_proj))), na.rm = TRUE)
      if (nueva_dist_minima <= 5) {
        servicio_valido <- TRUE
      }
    }

    if (!servicio_valido) {
      message("    ↳ ⚠️ Tránsito rápido perimetral detectado en la zona de recorte. Saltando mapa.")
      next
    }
    # =========================================================================

    # =========================================================================
    # FILTRO FINAL POR DURACIÓN DE CADA VISITA INDIVIDUAL (LUEGO DE TODO)
    # =========================================================================
    # Después de aplicar erosión, recorte y validación, dividimos los puntos restantes
    # de cada vehículo en visitas independientes (gap > 20 min). 
    # Filtramos y eliminamos los puntos de aquellas visitas individuales que duren menos 
    # de 'min_tiempo_permanencia_minutos' (30 minutos).
    if (nrow(puntos_solapados_proj) > 0) {
      puntos_filtrados_lista <- list()
      matriculas_restantes <- unique(puntos_solapados_proj$matricula)
      
      for (mat in matriculas_restantes) {
        pts_mat <- puntos_solapados_proj[puntos_solapados_proj$matricula == mat, ]
        
        # Eliminar posibles valores NA en tiempo y asegurar orden temporal
        pts_mat <- pts_mat[!is.na(pts_mat$tiempo_posix), ]
        pts_mat <- pts_mat[order(pts_mat$tiempo_posix), ]
        
        tiempos_mat <- pts_mat$tiempo_posix
        
        if (length(tiempos_mat) > 0) {
          # Si hay solo un punto, la duración es 0, menor que 30, se descarta
          if (length(tiempos_mat) == 1) {
            next
          }
          
          # Calcular diferencias de tiempo en minutos
          diff_mins <- as.numeric(difftime(tiempos_mat[-1], tiempos_mat[-length(tiempos_mat)], units = "mins"))
          saltos <- which(diff_mins > 20)
          
          inicio_indices <- c(1, saltos + 1)
          fin_indices <- c(saltos, length(tiempos_mat))
          
          # Identificar qué índices de puntos pertenecen a visitas >= 30 minutos
          indices_validos <- c()
          for (v in seq_along(inicio_indices)) {
            idx_rango <- inicio_indices[v]:fin_indices[v]
            t_ini <- tiempos_mat[inicio_indices[v]]
            t_fin <- tiempos_mat[fin_indices[v]]
            duracion_visita <- as.numeric(difftime(t_fin, t_ini, units = "mins"))
            
            if (!is.na(duracion_visita) && duracion_visita >= min_tiempo_permanencia_minutos) {
              indices_validos <- c(indices_validos, idx_rango)
            }
          }
          
          if (length(indices_validos) > 0) {
            puntos_filtrados_lista[[mat]] <- pts_mat[indices_validos, ]
          }
        }
      }
      
      if (length(puntos_filtrados_lista) > 0) {
        puntos_solapados_proj <- do.call(rbind, puntos_filtrados_lista)
      } else {
        # Si ningún punto de ningún camión cumple, vaciamos el sf
        puntos_solapados_proj <- puntos_solapados_proj[0, ]
      }
    }
    
    if (nrow(puntos_solapados_proj) == 0) {
      message(paste("    ↳ ⚠️ Ningún intervalo de visita individual superó los", min_tiempo_permanencia_minutos, "minutos mínimos después de aplicar todos los filtros. Saltando mapa."))
      next
    }
    # =========================================================================

    # Volver al CRS original (WGS84)
    puntos_solapados <- st_transform(puntos_solapados_proj, 4326)
    puntos_solapados <- puntos_solapados %>% mutate(Turno_Consulta = turno)

    # Enriquecer con información de flota (servicio asignado / FRACCION) en forma vectorizada para múltiples vehículos
    puntos_solapados <- puntos_solapados %>%
      left_join(
        df_flota %>% select(Matricula, Servicio) %>% distinct(),
        by = c("matricula" = "Matricula")
      ) %>%
      rename(FRACCION = Servicio)

    # Definir nombre de salida del archivo HTML
    nombre_limpio <- gsub("[^[:alnum:]]", "_", sector_nombre)
    nombre_archivo <- paste0(fecha_proceso, "_Mapa_Hogar_", nombre_limpio, "_", toupper(turno), ".html")
    salida_html <- file.path(carpeta_turno, nombre_archivo)

    # Exportar el mapa
    exito <- exportar_mapa_hogares_sector(
      df_sf          = puntos_solapados,
      sector_polygon = capa_filtrada,
      salida_html    = salida_html,
      usar_iconos    = usar_iconos_proc,
      fecha          = fecha_proceso,
      turno          = turno
    )

    if (exito) {
      message(paste("    ✅ Mapa generado con éxito:", nombre_archivo))
    } else {
      message(paste("    ❌ Error al generar el mapa para:", sector_nombre))
    }
  }

  message(paste("====== Fin Turno:", turno, "======\n"))
}

message("=========================================================================")
message("✅ PROCESAMIENTO BATCH COMPLETADO CON ÉXITO")
message("=========================================================================")
