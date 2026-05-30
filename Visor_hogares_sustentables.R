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
        orient  <- puntos_web$orientacion[i]
        tiempo  <- puntos_web$tiempo[i]
        mat     <- puntos_web$matricula[i]
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

  cartel_lineas <- c(
    paste0("DÍA: ", fecha_val),
    paste0("TURNO: ", toupper(turno_val))
  )

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

    # 3. Fallback automático de R (para otros formatos / locales)
    idx_na <- is.na(tiempos_convertidos) & !is.na(clean_tiempo) & clean_tiempo != ""
    if (any(idx_na)) {
      tiempos_convertidos[idx_na] <- tryCatch(
        as.POSIXct(clean_tiempo[idx_na]),
        error = function(e) as.POSIXct(rep(NA, sum(idx_na)))
      )
    }
    
    puntos_copia$tiempo_posix <- tiempos_convertidos
    matriculas_unicas <- sort(unique(puntos_copia$matricula))

    for (mat in matriculas_unicas) {
      idx_mat <- puntos_copia$matricula == mat
      tiempos_mat <- puntos_copia$tiempo_posix[idx_mat]
      tiempos_mat <- tiempos_mat[!is.na(tiempos_mat)]

      if (length(tiempos_mat) > 0) {
        tiempos_mat <- sort(tiempos_mat)
        inicio_f <- format(tiempos_mat[1], "%H:%M:%S")

        if (length(tiempos_mat) == 1) {
          fin_f <- inicio_f
        } else {
          diff_horas <- as.numeric(difftime(tiempos_mat[-1], tiempos_mat[-length(tiempos_mat)], units = "hours"))
          gap_idx <- which(diff_horas > 1)

          if (length(gap_idx) > 0) {
            fin_f <- format(tiempos_mat[gap_idx[1]], "%H:%M:%S")
          } else {
            fin_f <- format(tiempos_mat[length(tiempos_mat)], "%H:%M:%S")
          }
        }

        cartel_lineas <- c(cartel_lineas, paste0("VEHÍCULO ", mat, ": ", inicio_f, " - ", fin_f))
      } else {
        # Fallback de seguridad por strings si la conversión a POSIXct resulta en NA
        raw_tiempos_mat <- sort(clean_tiempo[idx_mat])
        if (length(raw_tiempos_mat) > 0) {
          extraer_hora <- function(x) {
            h <- regmatches(x, regexpr("[0-9]{2}:[0-9]{2}:[0-9]{2}", x))
            if (length(h) > 0) h[1] else substr(x, 12, 19)
          }
          inicio_raw <- extraer_hora(raw_tiempos_mat[1])
          fin_raw    <- extraer_hora(raw_tiempos_mat[length(raw_tiempos_mat)])
          cartel_lineas <- c(cartel_lineas, paste0("VEHÍCULO ", mat, ": ", inicio_raw, " - ", fin_raw))
        }
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

  tryCatch(
    {
      saveWidget(mapa, file = salida_html, selfcontained = TRUE)
      return(TRUE)
    },
    error = function(e) {
      message("❌ Error al guardar el widget HTML:")
      print(e)
      return(FALSE)
    }
  )
}

# =============================================================================
# SECCIÓN 3: BUCLE DE EJECUCIÓN (Replicando Visor_vehiculos.R)
# =============================================================================

# --- Ajustar parámetros de ejecución ---
fecha_proceso <- "2026-05-25"   # <-- Ajustar la fecha de consulta aquí
tolerancia_metros <- 30          # <-- Buffer en metros alrededor de las casas
usar_iconos_proc <- FALSE         # <-- Poner en FALSE para círculos simples, TRUE para iconos personalizados IMM
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
  carpeta_turno <- file.path("salidas", "mapas_hogares", turno)
  if (!dir.exists(carpeta_turno)) dir.create(carpeta_turno, recursive = TRUE)

  # 4. Iteración sobre cada sector de Hogares Sustentables
  for (sector_nombre in sectores) {
    if (is.na(sector_nombre) || sector_nombre == "") next

    message(paste("  🔍 Sector:", sector_nombre))

    # Filtrar el polígono del sector actual
    capa_filtrada <- capa_hogares[capa_hogares$nombre == sector_nombre, ]

    # Intersección espacial: Proyectar temporalmente a UTM 21S (EPSG:32721) para buffer métrico
    capa_filtrada_proj  <- st_transform(capa_filtrada, 32721)
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

    # Volver al CRS original (WGS84)
    puntos_solapados <- st_transform(puntos_solapados_proj, 4326)
    puntos_solapados <- puntos_solapados %>% mutate(Turno_Consulta = turno)

    # Enriquecer con información de flota (servicio asignado / FRACCION)
    matricula_ref <- puntos_solapados$matricula[1]
    servicio_encontrado <- df_flota %>%
      filter(Matricula == matricula_ref) %>%
      pull(Servicio)

    if (length(servicio_encontrado) > 0) {
      puntos_solapados <- puntos_solapados %>%
        mutate(FRACCION = servicio_encontrado[1])
    }

    # Definir nombre de salida del archivo HTML
    nombre_limpio  <- gsub("[^[:alnum:]]", "_", sector_nombre)
    nombre_archivo <- paste0(fecha_proceso, "_Mapa_Hogar_", nombre_limpio, "_", toupper(turno), ".html")
    salida_html    <- file.path(carpeta_turno, nombre_archivo)

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
