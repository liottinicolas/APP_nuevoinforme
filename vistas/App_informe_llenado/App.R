library(shiny)
library(leaflet)
library(leaflet.extras)
library(sf)
library(pins)
library(dplyr)
library(DT)
library(bs4Dash)
library(jsonlite)
library(httr)

# --- DETECCIÓN DE ENTORNO Y CARGA DE DATOS ---
# En local: lee desde la carpeta "data/" (generada por limpieza_datos.R)
# En Shiny: lee directamente desde GitHub raw (sin necesidad de PAT si el repo es público)

url_github <- "https://raw.githubusercontent.com/liottinicolas/APP_nuevoinforme/main/vistas/App_informe_llenado/data/"

# Función de preprocesamiento (se define una vez al inicio, no depende de los datos)
preprocesar_datos <- function(df) {
  if (!inherits(df, "sf")) {
    df <- st_as_sf(df, wkt = "THE_GEOM", crs = 32721)
  }
  return(st_transform(df, 4326))
}

# Inicialización de la placa de datos (global)
if (dir.exists("data")) {
  global_board <- pins::board_folder("data", versioned = FALSE)
} else {
  global_board <- pins::board_url(c(
    "GID_activos"           = paste0(url_github, "GID_activos/"),
    "GID_inactivos"         = paste0(url_github, "GID_inactivos/"),
    "historico_llenado_web" = paste0(url_github, "historico_llenado_web/")
  ))
}

# Intervalo de recarga automática (10 minutos * 60 segundos * 1000 milisegundos)
INTERVALO_RECARGA_MS <- 10 * 60 * 1000

# Carga de datos compartida y optimizada mediante reactivePoll.
# Se evalúa en el inicio de la app y luego busca actualizaciones cada 10 minutos.
# checkFunc utiliza la API ligera de GitHub (con un timeout corto) en producción,
# lo que evita recargas y cálculos innecesarios del st_transform si los datos no cambiaron.
datos_compartidos <- reactivePoll(
  intervalMillis = INTERVALO_RECARGA_MS,
  session = NULL,
  checkFunc = function() {
    if (dir.exists("data")) {
      files <- list.files("data", recursive = TRUE, full.names = TRUE)
      if (length(files) > 0) {
        return(max(file.info(files)$mtime, na.rm = TRUE))
      }
      return(Sys.time())
    } else {
      # Comprobación ligera del último commit en GitHub
      tryCatch({
        url_commit <- "https://api.github.com/repos/liottinicolas/APP_nuevoinforme/commits/main"
        req <- httr::GET(
          url_commit, 
          httr::timeout(3),
          httr::user_agent("ShinyApp-Nicolas")
        )
        if (httr::status_code(req) == 200) {
          content <- httr::content(req, as = "text", encoding = "UTF-8")
          commit_data <- jsonlite::fromJSON(content)
          return(commit_data$sha)
        }
      }, error = function(e) {
        # Fallback si no hay conexión o API límite
        return(floor(as.numeric(Sys.time()) / 3600)) 
      })
      return(floor(as.numeric(Sys.time()) / 3600))
    }
  },
  valueFunc = function() {
    message("🔄 [Carga Global] Descargando y preprocesando datos (pins + st_transform)...")
    
    if (dir.exists("data")) {
      current_board <- global_board
    } else {
      current_board <- pins::board_url(c(
        "GID_activos"           = paste0(url_github, "GID_activos/"),
        "GID_inactivos"         = paste0(url_github, "GID_inactivos/"),
        "historico_llenado_web" = paste0(url_github, "historico_llenado_web/")
      ))
    }
    
    list(
      activos           = preprocesar_datos(pin_read(current_board, "GID_activos")),
      inactivos         = preprocesar_datos(pin_read(current_board, "GID_inactivos")),
      historico_llenado = pin_read(current_board, "historico_llenado_web")
    )
  }
)

lat_mvd <- -34.8636
lng_mvd <- -56.1679

ui <- dashboardPage(
  title = "Gestión de GIDs - Montevideo",
  
  # 1. Barra Superior
  header = dashboardHeader(
    title = dashboardBrand(
      title = "Gestión de GIDs",
      color = "primary",
      href = "#"
    ),
    skin = "light",
    rightUi = tags$li(
      class = "nav-item dropdown d-flex align-items-center px-3",
      tags$span(
        style = "background-color: #17a2b8; color: white; padding: 6px 16px; border-radius: 30px; font-size: 0.85rem; font-weight: 600; box-shadow: 0 2px 4px rgba(0,0,0,0.1);",
        icon("calendar-alt"),
        textOutput("fecha_actualizacion", inline = TRUE)
      )
    )
  ),
  
  # 2. Menú Lateral
  sidebar = dashboardSidebar(
    skin = "dark",
    status = "primary",
    elevation = 3,
    sidebarMenu(
      id = "menu_tabs", # Añadido ID para navegación programática
      menuItem("Mapa Interactivo", tabName = "mapa", icon = icon("map")),
      menuItem("Histórico de Llenado", tabName = "hist", icon = icon("table"))
    )
  ),
  
  # 3. Cuerpo Principal
  body = dashboardBody(
    # Estilos customizados CSS para un look moderno y premium (Rich Aesthetics)
    tags$head(
      tags$style(HTML("
        /* Reducir tamaño de letra global de la aplicación */
        body { font-size: 0.82rem !important; }
        .content-wrapper { background-color: #f4f6f9; }
        .card { border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); border: none; margin-bottom: 20px; font-size: 0.82rem; }
        .card-header { border-bottom: 1px solid rgba(0,0,0,0.08); background-color: transparent; }
        .btn { border-radius: 6px; font-weight: 500; font-size: 0.78rem; }
        .info-box { border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        .leaflet-container { border-radius: 10px; box-shadow: 0 4px 10px rgba(0,0,0,0.08); }
        
        /* Estilos específicos de tablas */
        #tabla_historico table { background-color: white; border-radius: 8px; overflow: hidden; font-size: 0.76rem; }
        .dataTables_wrapper { font-size: 0.76rem; }
        .dataTables_wrapper .dataTables_info, .dataTables_wrapper .dataTables_paginate { font-size: 0.72rem; }
        
        /* Controles e inputs */
        .form-control, .selectize-input, .radio label, .checkbox label, .control-label { font-size: 0.78rem !important; }
        .control-label { font-weight: 600; color: #495057; }
        
        /* Menú lateral (Sidebar) */
        .main-sidebar, .nav-sidebar .nav-link { font-size: 0.8rem !important; }
        
        /* Indicadores KPI (Value Boxes) */
        .small-box { font-size: 0.8rem; }
        .small-box h3 { font-size: 1.4rem !important; }
        .small-box p { font-size: 0.72rem !important; }
        
        /* Popups del mapa */
        .leaflet-popup-content-wrapper { font-size: 0.75rem; border-radius: 8px; }
        
        /* Efecto hover suave en botones */
        .btn:hover { transform: translateY(-1px); box-shadow: 0 4px 8px rgba(0,0,0,0.1); transition: all 0.2s ease; }
      "))
    ),
    
    tabItems(
      # Contenido de la pestaña MAPA
      tabItem(
        tabName = "mapa",
        fluidRow(
          # Tarjeta de controles (3 columnas)
          box(
            title = "Filtros y Búsqueda", 
            width = 3, 
            status = "primary",
            solidHeader = FALSE,
            collapsible = FALSE,
            
            radioButtons("seleccion_estado", "Ver en el mapa:",
                         choices = list("GIDs Activos" = "act", "GIDs Inactivos" = "inact")),
            hr(),
            
            # Switch para activar o desactivar clustering (Gran mejora de rendimiento)
            checkboxInput("usar_clustering", "Agrupar marcadores (Clustering)", value = TRUE),
            hr(),
            
            tags$label("Buscar por GID:"),
            tags$div(
              style = "display: flex; gap: 6px;",
              textInput("busqueda_gid_mapa", label = NULL, placeholder = "Ej: 12345"),
              actionButton("btn_buscar_gid", label = NULL, icon = icon("search"),
                           class = "btn-primary", style = "margin-top: 0px;")
            ),
            tags$small(class = "text-muted", "Busca en activos e inactivos"),
            hr(),
            
            tags$label("Buscar calle / dirección:"),
            tags$div(
              style = "display: flex; gap: 6px;",
              textInput("busqueda_calle", label = NULL, placeholder = "Ej: Av. 18 de Julio"),
              actionButton("btn_buscar_calle", label = NULL, icon = icon("map-marker-alt"),
                           class = "btn-info", style = "margin-top: 0px;")
            ),
            tags$small(class = "text-muted", "Busca en OpenStreetMap (Montevideo)")
          ),
          
          # Tarjeta del mapa (9 columnas)
          box(
            title = "Visor Geográfico de Montevideo", 
            width = 9, 
            maximizable = TRUE, 
            status = "primary",
            solidHeader = FALSE,
            leafletOutput("map", height = "650px")
          )
        )
      ),
      
      # Contenido de la pestaña HISTÓRICO
      tabItem(
        tabName = "hist",
        # Fila 1: Buscador (Arriba)
        fluidRow(
          box(
            title = "Consulta de Contenedor", 
            width = 12, 
            status = "primary", 
            solidHeader = TRUE, 
            icon = icon("search"),
            
            textInput("busqueda_gid", "Ingrese el número de GID para consultar su historial:", 
                      placeholder = "Ej: 100299"),
            helpText("Presione Enter para ver los resultados.")
          )
        ),
        
        # Fila 2: KPIs dinámicos del GID buscado (¡Nuevo!)
        uiOutput("kpis_historico"),
        
        # Fila 3: Tabla de Resultados
        fluidRow(
          box(
            title = "Historial de Llenado y Vaciamiento (GOL)", 
            width = 12, 
            status = "success", 
            solidHeader = TRUE,
            icon = icon("list"),
            
            DTOutput("tabla_historico")
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {

  # datos() ahora lee de los datos compartidos globales (cargados una sola vez)
  datos <- reactive({
    datos_compartidos()
  })

  # Fecha máxima dinámica: se actualiza cuando datos() cambia
  output$fecha_actualizacion <- renderText({
    req(datos())
    fecha <- format(max(as.Date(datos()$historico_llenado$Fecha), na.rm = TRUE), "%d/%m/%Y")
    paste0(" Datos al: ", fecha)
  })

  # --- Lógica del Mapa (Inicialización Base) ---
  # El mapa base se renderiza una sola vez. Los marcadores se agregan dinámicamente con leafletProxy.
  # Esto previene que el zoom del mapa se resetee cuando cambian los datos o filtros.
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = lng_mvd, lat = lat_mvd, zoom = 12)
  })
  
  # Actualización dinámica de marcadores mediante leafletProxy
  observe({
    req(datos())
    proxy <- leafletProxy("map")
    
    # Limpiamos grupos anteriores
    proxy %>% clearGroup("activos") %>% clearGroup("inactivos")
    
    # Configuración de clustering según checkbox de la UI
    cluster_opts <- if (input$usar_clustering) markerClusterOptions() else NULL
    
    if (input$seleccion_estado == "act") {
      proxy %>%
        addCircleMarkers(
          data = datos()$activos,
          group = "activos",
          radius = 5,
          color = "#007bff",
          stroke = TRUE,
          weight = 1.5,
          opacity = 0.8,
          fillColor = "#007bff",
          fillOpacity = 0.6,
          popup = ~paste0(
            "<div style='font-family: Arial, sans-serif; min-width: 200px;'>",
            "<h6 style='margin: 0 0 8px 0; color: #007bff; font-weight: bold;'><i class='fas fa-cube'></i> Contenedor Activo</h6>",
            "<b>GID:</b> ", GID, "<br>",
            "<b>Dirección:</b> ", DIRECCION, "<br>",
            "<b>Circuito:</b> ", COD_RECORRIDO, "<br>",
            "<b>Posición:</b> ", POSICION, "<br>",
            "<b>Fecha Desde:</b> ", format(FECHA_DESDE, "%d/%m/%Y"), "<br>",
            "<hr style='margin: 8px 0;'>",
            "<button class='btn btn-xs btn-primary' style='color: white; font-weight: bold; width: 100%; border: none;' ",
            "onclick='Shiny.setInputValue(\"ver_historial_gid\", ", GID, ", {priority: \"event\"})'>",
            "🔍 Ver Historial Completo",
            "</button>",
            "</div>"
          ),
          label = ~as.character(GID),
          layerId = ~as.character(GID),
          clusterOptions = cluster_opts
        )
    } else {
      proxy %>%
        addCircleMarkers(
          data = datos()$inactivos,
          group = "inactivos",
          radius = 5,
          color = "#dc3545",
          stroke = TRUE,
          weight = 1.5,
          opacity = 0.8,
          fillColor = "#dc3545",
          fillOpacity = 0.6,
          popup = ~paste0(
            "<div style='font-family: Arial, sans-serif; min-width: 200px;'>",
            "<h6 style='margin: 0 0 8px 0; color: #dc3545; font-weight: bold;'><i class='fas fa-history'></i> Contenedor Inactivo</h6>",
            "<b>GID:</b> ", GID, "<br>",
            "<b>Fecha Hasta:</b> ", format(FECHA_HASTA, "%d/%m/%Y"), "<br>",
            "<b>Último Circuito:</b> ", COD_RECORRIDO, "<br>",
            "<hr style='margin: 8px 0;'>",
            "<button class='btn btn-xs btn-danger' style='color: white; font-weight: bold; width: 100%; border: none;' ",
            "onclick='Shiny.setInputValue(\"ver_historial_gid\", ", GID, ", {priority: \"event\"})'>",
            "🔍 Ver Historial Completo",
            "</button>",
            "</div>"
          ),
          label = ~as.character(GID),
          layerId = ~as.character(GID),
          clusterOptions = cluster_opts
        )
    }
  })
  
  # Redirección cruzada: al hacer click en "Ver Historial" en el popup del mapa,
  # se cambia de pestaña y se rellena la búsqueda de GID automáticamente.
  observeEvent(input$ver_historial_gid, {
    gid_seleccionado <- input$ver_historial_gid
    
    # 1. Cambiar a la pestaña "hist" en el menú
    updateTabItems(session, "menu_tabs", "hist")
    
    # 2. Rellenar el input de búsqueda del histórico con el GID seleccionado
    updateTextInput(session, "busqueda_gid", value = as.character(gid_seleccionado))
  })
  
  # --- Búsqueda de GID en el mapa (Autofocus + Popup automático) ---
  observeEvent(input$btn_buscar_gid, {
    req(input$busqueda_gid_mapa)
    gid_buscado <- trimws(input$busqueda_gid_mapa)
    
    # Buscar primero en activos, luego en inactivos
    df_act  <- datos()$activos
    df_inac <- datos()$inactivos
    
    encontrado <- df_act[as.character(df_act$GID) == gid_buscado, ]
    grupo <- "activos"
    if (nrow(encontrado) == 0) {
      encontrado <- df_inac[as.character(df_inac$GID) == gid_buscado, ]
      grupo <- "inactivos"
    }
    
    proxy <- leafletProxy("map")
    
    if (nrow(encontrado) > 0) {
      coords <- st_coordinates(encontrado[1, ])
      
      # Si el GID está en el grupo opuesto al seleccionado, cambiamos el interruptor
      if (grupo == "activos" && input$seleccion_estado != "act") {
        updateRadioButtons(session, "seleccion_estado", selected = "act")
      } else if (grupo == "inactivos" && input$seleccion_estado != "inact") {
        updateRadioButtons(session, "seleccion_estado", selected = "inact")
      }
      
      # Generar contenido del popup
      popup_content <- if (grupo == "activos") {
        paste0(
          "<div style='font-family: Arial, sans-serif; min-width: 200px;'>",
          "<h6 style='margin: 0 0 8px 0; color: #007bff; font-weight: bold;'><i class='fas fa-cube'></i> Contenedor Activo</h6>",
          "<b>GID:</b> ", encontrado$GID[1], "<br>",
          "<b>Dirección:</b> ", encontrado$DIRECCION[1], "<br>",
          "<b>Circuito:</b> ", encontrado$COD_RECORRIDO[1], "<br>",
          "<b>Posición:</b> ", encontrado$POSICION[1], "<br>",
          "<b>Fecha Desde:</b> ", format(encontrado$FECHA_DESDE[1], "%d/%m/%Y"), "<br>",
          "<hr style='margin: 8px 0;'>",
          "<button class='btn btn-xs btn-primary' style='color: white; font-weight: bold; width: 100%; border: none;' ",
          "onclick='Shiny.setInputValue(\"ver_historial_gid\", ", encontrado$GID[1], ", {priority: \"event\"})'>",
          "🔍 Ver Historial Completo",
          "</button>",
          "</div>"
        )
      } else {
        paste0(
          "<div style='font-family: Arial, sans-serif; min-width: 200px;'>",
          "<h6 style='margin: 0 0 8px 0; color: #dc3545; font-weight: bold;'><i class='fas fa-history'></i> Contenedor Inactivo</h6>",
          "<b>GID:</b> ", encontrado$GID[1], "<br>",
          "<b>Fecha Hasta:</b> ", format(encontrado$FECHA_HASTA[1], "%d/%m/%Y"), "<br>",
          "<b>Último Circuito:</b> ", encontrado$COD_RECORRIDO[1], "<br>",
          "<hr style='margin: 8px 0;'>",
          "<button class='btn btn-xs btn-danger' style='color: white; font-weight: bold; width: 100%; border: none;' ",
          "onclick='Shiny.setInputValue(\"ver_historial_gid\", ", encontrado$GID[1], ", {priority: \"event\"})'>",
          "🔍 Ver Historial Completo",
          "</button>",
          "</div>"
        )
      }
      
      proxy %>%
        setView(lng = coords[1], lat = coords[2], zoom = 18) %>%
        clearPopups() %>%
        showPopup(lng = coords[1], lat = coords[2], popup = popup_content)
        
    } else {
      showNotification(
        paste0("GID '", gid_buscado, "' no encontrado."),
        type = "warning", duration = 4
      )
    }
  })

  # --- Búsqueda de calle via Nominatim ---
  observeEvent(input$btn_buscar_calle, {
    req(input$busqueda_calle)
    query <- paste0(trimws(input$busqueda_calle), ", Montevideo, Uruguay")
    
    tryCatch({
      url <- paste0(
        "https://nominatim.openstreetmap.org/search?q=",
        utils::URLencode(query, reserved = TRUE),
        "&format=json&limit=1&addressdetails=0"
      )
      # Petición HTTP con timeout seguro
      req_search <- httr::GET(url, httr::timeout(4), httr::user_agent("ShinyApp-Nicolas"))
      
      if (httr::status_code(req_search) == 200) {
        resp <- jsonlite::fromJSON(httr::content(req_search, as = "text", encoding = "UTF-8"))
        
        if (length(resp) > 0 && nrow(as.data.frame(resp)) > 0) {
          lat <- as.numeric(resp$lat[1])
          lon <- as.numeric(resp$lon[1])
          leafletProxy("map") %>%
            clearGroup("busqueda_calle") %>%
            addCircleMarkers(
              lng = lon, lat = lat,
              group = "busqueda_calle",
              radius = 14,
              color = "#e0a800",
              weight = 3,
              fill = TRUE,
              fillColor = "#ffc107",
              fillOpacity = 0.35,
              popup = paste0("<b>📍 Ubicación buscada:</b><br>", input$busqueda_calle)
            ) %>%
            setView(lng = lon, lat = lat, zoom = 17)
        } else {
          showNotification(
            paste0("No se encontró: '", input$busqueda_calle, "'"),
            type = "warning", duration = 4
          )
        }
      }
    }, error = function(e) {
      showNotification("Error al conectar con el geocodificador Nominatim.", type = "danger", duration = 4)
    })
  })

  # --- Lógica del Histórico ---

  # Filtramos el dataframe reactivamente según el texto ingresado
  datos_filtrados <- reactive({
    req(input$busqueda_gid)
    gid_buscado <- trimws(input$busqueda_gid)
    
    datos()$historico_llenado %>%
      filter(as.character(gid) == gid_buscado) %>%
      mutate(
        Hora_pasaje = ifelse(is.na(Fecha_hora_pasaje), "", format(as.POSIXct(Fecha_hora_pasaje), "%H:%M:%S"))
      ) %>%
      select(
        Fecha, Circuito_corto, Posicion, Direccion, Levantado,
        Turno_levantado, Hora_pasaje, Id_viaje_GOL,
        Incidencia, Porcentaje_llenado, Condicion, contenedor_activo
      )
  })
  
  # KPI Boxes dinámicos en la pestaña de Histórico
  output$kpis_historico <- renderUI({
    req(input$busqueda_gid)
    df <- datos_filtrados()
    if (nrow(df) == 0) {
      return(
        fluidRow(
          box(
            width = 12, status = "warning",
            tags$div(
              style = "text-align: center; padding: 20px; font-weight: bold; color: #856404;",
              icon("exclamation-triangle"), " No se encontraron registros de llenado para el GID ", input$busqueda_gid
            )
          )
        )
      )
    }
    
    # 1. KPIs Cálculos
    total_visitas <- nrow(df)
    
    # Llenado promedio (ignorando NA)
    llenado_prom <- mean(as.numeric(df$Porcentaje_llenado), na.rm = TRUE)
    llenado_prom_txt <- if (is.nan(llenado_prom)) "N/A" else paste0(round(llenado_prom, 1), "%")
    
    # Último llenado registrado
    # Se asegura la conversión a Date o POSIXct para ordenar cronológicamente
    df_sorted <- df %>%
      mutate(fecha_orden = as.Date(Fecha)) %>%
      arrange(desc(fecha_orden))
      
    ultimo_registro <- df_sorted %>% slice(1)
    ultimo_llenado <- ultimo_registro$Porcentaje_llenado
    ultimo_llenado_txt <- if (is.null(ultimo_llenado) || is.na(ultimo_llenado)) "N/A" else paste0(ultimo_llenado, "%")
    
    # Determinar estado activo/inactivo actual del GID
    gid_actual <- trimws(input$busqueda_gid)
    esta_activo <- gid_actual %in% as.character(datos()$activos$GID)
    estado_txt <- if (esta_activo) "Activo" else "Inactivo"
    estado_color <- if (esta_activo) "success" else "danger"
    estado_icon <- if (esta_activo) "check-circle" else "ban"
    
    fluidRow(
      # Tarjeta 1: Total de visitas
      valueBox(
        value = total_visitas,
        subtitle = "Registros de Visitas (GOL)",
        icon = icon("truck"),
        color = "primary",
        width = 3
      ),
      # Tarjeta 2: Último nivel de llenado
      valueBox(
        value = ultimo_llenado_txt,
        subtitle = "Último Llenado Reportado",
        icon = icon("battery-three-quarters"),
        color = "warning",
        width = 3
      ),
      # Tarjeta 3: Llenado promedio
      valueBox(
        value = llenado_prom_txt,
        subtitle = "Llenado Promedio Histórico",
        icon = icon("tachometer-alt"),
        color = "info",
        width = 3
      ),
      # Tarjeta 4: Estado actual
      valueBox(
        value = estado_txt,
        subtitle = "Estado del Contenedor",
        icon = icon(estado_icon),
        color = estado_color,
        width = 3
      )
    )
  })
  
  output$tabla_historico <- renderDT({
    req(datos_filtrados())
    if (nrow(datos_filtrados()) == 0) return(NULL)
    
    # Ordenamos el dataframe reactivo de más reciente a más antiguo
    datos_ordenados <- datos_filtrados() %>%
      arrange(desc(as.Date(Fecha))) 
    
    datatable(
      datos_ordenados,
      colnames = c(
        "Fecha", "Circuito", "Posicion", "Dirección", "¿Levantado?", 
        "Turno", "Hora pasaje", "ID Viaje GOL", "Incidencia", 
        "% Llenado", "Condición", "Activo"
      ),
      options = list(
        pageLength = 10,
        lengthMenu = c(5, 10, 25, 50),
        language = list(url = '//cdn.datatables.net/plug-ins/1.10.11/i18n/Spanish.json'),
        scrollX = TRUE
      ),
      rownames = FALSE
    )
  })
}

shinyApp(ui, server)