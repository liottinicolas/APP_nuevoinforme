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
#
# Los datos se publican en un repo de GitHub aparte (APP_nuevoinforme-data),
# no en este repo de código (ver vistas/App_informe_llenado/limpieza_datos.R).
REPO_DATOS <- "liottinicolas/APP_nuevoinforme-data"
url_github <- paste0("https://raw.githubusercontent.com/", REPO_DATOS, "/master/data/")

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
  # board_url() con una única URL base lee el manifest (_pins.yaml, generado
  # por write_board_manifest() en limpieza_datos.R) para resolver la
  # subcarpeta de versión vigente de cada pin. Una URL fija por pin no
  # funciona porque esa subcarpeta cambia de hash en cada corrida.
  global_board <- pins::board_url(url_github)
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
        url_commit <- paste0("https://api.github.com/repos/", REPO_DATOS, "/commits/master")
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
      current_board <- pins::board_url(url_github)
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
    skin = "dark",
    rightUi = tags$li(
      class = "nav-item dropdown d-flex align-items-center px-3",
      tags$span(
        style = "background-color: rgba(255,255,255,0.08); color: #f3f4f6; border: 1px solid rgba(255,255,255,0.12); padding: 6px 16px; border-radius: 30px; font-size: 0.85rem; font-weight: 600;",
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
    # Tema oscuro/neutro (paleta tomada del tablero de referencia de la IM)
    tags$head(
      tags$link(href = "https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap", rel = "stylesheet"),
      tags$style(HTML("
        :root {
          --bg: #080c14;
          --card-bg: rgba(17, 24, 39, 0.6);
          --card-border: rgba(255, 255, 255, 0.08);
          --text-main: #f3f4f6;
          --text-muted: #9ca3af;
          --primary: #2563eb;
          --success: #10b981;
          --warning: #f59e0b;
          --danger: #ef4444;
          --neutral: #6b7280;
          --header-gradient: linear-gradient(135deg, #0f172a, #1e293b);
        }

        /* Base */
        body, .content-wrapper { background-color: var(--bg) !important; color: var(--text-main); font-family: 'Outfit', sans-serif; font-size: 0.82rem !important; }

        /* Header y sidebar */
        .main-header.navbar { background: var(--header-gradient) !important; border-bottom: 1px solid var(--card-border) !important; }
        .main-sidebar { background: var(--header-gradient) !important; }
        .brand-link { background: transparent !important; border-bottom: 1px solid var(--card-border) !important; }
        .nav-sidebar .nav-link { color: var(--text-muted) !important; font-size: 0.8rem !important; }
        .nav-sidebar .nav-link:hover { color: var(--text-main) !important; }
        .nav-sidebar > .nav-item > .nav-link.active { background-color: var(--primary) !important; color: #fff !important; }

        /* Tarjetas / paneles: estilo 'glass' neutro, sin franja de color por status */
        .card { background: var(--card-bg) !important; backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border: 1px solid var(--card-border) !important; border-radius: 16px; box-shadow: 0 4px 15px rgba(0,0,0,0.25); margin-bottom: 20px; font-size: 0.82rem; color: var(--text-main); }
        .card.card-primary, .card.card-success, .card.card-info, .card.card-warning, .card.card-danger { border-top: 1px solid var(--card-border) !important; }
        .card-header { border-bottom: 1px solid var(--card-border); background-color: transparent; color: var(--text-main); }
        /* bs4Dash pinta de color sólido el header cuando solidHeader = TRUE; se neutraliza explícitamente */
        .card.card-primary:not(.card-outline) > .card-header,
        .card.card-success:not(.card-outline) > .card-header,
        .card.card-info:not(.card-outline) > .card-header,
        .card.card-warning:not(.card-outline) > .card-header,
        .card.card-danger:not(.card-outline) > .card-header {
          background-color: transparent !important;
          color: var(--text-main) !important;
        }
        .card-title { color: var(--text-main); }
        .info-box { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.25); }

        /* Indicadores KPI (Value Boxes): fondo neutro 'glass' + franja de color a la izquierda como acento */
        .small-box { background: var(--card-bg) !important; backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border: 1px solid var(--card-border); border-left: 4px solid var(--neutral); border-radius: 16px; box-shadow: 0 4px 15px rgba(0,0,0,0.25); font-size: 0.8rem; transition: transform 0.2s ease, box-shadow 0.2s ease; }
        .small-box:hover { transform: translateY(-3px); box-shadow: 0 8px 20px rgba(0,0,0,0.35); }
        .small-box .inner h3, .small-box .inner p { color: var(--text-main) !important; }
        .small-box h3 { font-size: 1.4rem !important; font-weight: 700; }
        .small-box p { font-size: 0.72rem !important; color: var(--text-muted) !important; text-transform: uppercase; letter-spacing: 0.5px; }
        .small-box .icon { opacity: 0.3; }
        .small-box.bg-primary   { border-left-color: var(--primary); }   .small-box.bg-primary .icon   { color: var(--primary) !important; }
        .small-box.bg-info      { border-left-color: var(--primary); }   .small-box.bg-info .icon      { color: var(--primary) !important; }
        .small-box.bg-success   { border-left-color: var(--success); }   .small-box.bg-success .icon   { color: var(--success) !important; }
        .small-box.bg-warning   { border-left-color: var(--warning); }   .small-box.bg-warning .icon   { color: var(--warning) !important; }
        .small-box.bg-danger    { border-left-color: var(--danger); }    .small-box.bg-danger .icon    { color: var(--danger) !important; }
        .small-box.bg-secondary { border-left-color: var(--neutral); }   .small-box.bg-secondary .icon { color: var(--neutral) !important; }
        .small-box.bg-primary, .small-box.bg-info, .small-box.bg-success, .small-box.bg-warning, .small-box.bg-danger, .small-box.bg-secondary { background: var(--card-bg) !important; }

        /* Botones */
        .btn { border-radius: 6px; font-weight: 500; font-size: 0.78rem; }
        .btn-primary { background-color: var(--primary) !important; border-color: var(--primary) !important; }
        .btn-primary:hover { transform: translateY(-1px); box-shadow: 0 4px 8px rgba(37,99,235,0.35); transition: all 0.2s ease; }

        /* Controles e inputs */
        .form-control, .selectize-input, .selectize-dropdown { background-color: #111827 !important; border: 1px solid var(--card-border) !important; color: var(--text-main) !important; font-size: 0.78rem !important; }
        .radio label, .checkbox label { color: var(--text-main) !important; font-size: 0.78rem !important; }
        .control-label, label { color: var(--text-muted) !important; font-weight: 600; font-size: 0.78rem !important; }
        .help-block, .text-muted { color: var(--text-muted) !important; }

        /* Mapa */
        .leaflet-container { border-radius: 10px; box-shadow: 0 4px 10px rgba(0,0,0,0.25); border: 1px solid var(--card-border); }
        .leaflet-popup-content-wrapper { font-size: 0.75rem; border-radius: 8px; }

        /* Tabla de histórico (DT) */
        #tabla_historico table { background-color: transparent !important; border-radius: 8px; overflow: hidden; font-size: 0.76rem; color: var(--text-main); }
        #tabla_historico table.dataTable thead th { background: rgba(255,255,255,0.03); color: var(--text-muted); border-bottom: 2px solid var(--card-border) !important; }
        #tabla_historico table.dataTable tbody td { border-bottom: 1px solid var(--card-border) !important; color: var(--text-main); background-color: transparent !important; }
        #tabla_historico table.dataTable.hover tbody tr:hover td, #tabla_historico table.dataTable.stripe tbody tr.odd { background-color: rgba(255,255,255,0.02) !important; }
        .dataTables_wrapper { font-size: 0.76rem; color: var(--text-muted); }
        .dataTables_wrapper .dataTables_info, .dataTables_wrapper .dataTables_paginate, .dataTables_wrapper .dataTables_length, .dataTables_wrapper .dataTables_filter { color: var(--text-muted); font-size: 0.72rem; }
        .dataTables_wrapper .dataTables_filter input, .dataTables_wrapper .dataTables_length select { background-color: #111827; border: 1px solid var(--card-border); color: var(--text-main); }
        .dataTables_wrapper .paginate_button { color: var(--text-main) !important; }
        .dataTables_wrapper .paginate_button.current { background: var(--primary) !important; border-color: var(--primary) !important; }
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

            tags$label("Buscar por dirección:"),
            tags$div(
              style = "display: flex; gap: 6px;",
              textInput("busqueda_dir_mapa", label = NULL, placeholder = "Ej: 18 de Julio 1234"),
              actionButton("btn_buscar_dir", label = NULL, icon = icon("map-marker-alt"),
                           class = "btn-primary", style = "margin-top: 0px;")
            ),
            tags$small(class = "text-muted", "Geocodificación limitada a Montevideo / Uruguay")
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
            helpText("Presione Enter para ver los resultados."),

            dateRangeInput(
              "rango_fechas_historico",
              "Rango de fechas a consultar:",
              start = Sys.Date() - 90,
              end = Sys.Date(),
              max = Sys.Date(),
              format = "dd/mm/yyyy",
              separator = "a",
              language = "es"
            )
          )
        ),
        
        # Fila 2: KPIs dinámicos del GID buscado (¡Nuevo!)
        uiOutput("kpis_historico"),

        # Fila 2b: Frecuencia de levante y saturación reciente
        uiOutput("kpis_historico_frecuencia"),

        # Fila 2c: No levante justificado (incidencia) vs. camión no pasó (sin registro)
        uiOutput("kpis_historico_no_levante"),

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
    # Tiles de CARTO (basemap "voyager"): mapa claro y mucho más liviano que
    # OpenStreetMap. Requiere API key de CARTO. maxZoom = 19 es el nivel de
    # detalle nativo máximo de estos tiles; pedir más generaría tiles vacíos/rotos.
    carto_key <- "cb1_2v24_1_3157bbb3b317c6d177c4d450"
    leaflet(options = leafletOptions(maxZoom = 19)) %>%
      addTiles(
        urlTemplate = paste0(
          "https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=",
          carto_key
        ),
        attribution = paste(
          '&copy; <a href="https://carto.com/attributions">CARTO</a>',
          '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        ),
        options = tileOptions(maxZoom = 19)
      ) %>%
      setView(lng = lng_mvd, lat = lat_mvd, zoom = 12)
  })
  
  # Actualización dinámica de marcadores mediante leafletProxy
  observe({
    req(datos())
    proxy <- leafletProxy("map")
    
    # Limpiamos grupos anteriores
    proxy %>% clearGroup("activos") %>% clearGroup("inactivos")
    
    # Configuración de clustering según checkbox de la UI.
    # disableClusteringAtZoom: a partir de ese nivel de zoom los clusters se
    # deshacen del todo y quedan los puntos individuales clickeables (sin esto,
    # el círculo con el número puede seguir tapando el click a un GID puntual).
    cluster_opts <- if (input$usar_clustering) {
      markerClusterOptions(disableClusteringAtZoom = 17)
    } else {
      NULL
    }
    
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
        addPopups(lng = coords[1], lat = coords[2], popup = popup_content)
        
    } else {
      showNotification(
        paste0("GID '", gid_buscado, "' no encontrado."),
        type = "warning", duration = 4
      )
    }
  })

  # --- Buscador por dirección (geocodificación con Nominatim / OpenStreetMap) ---
  # Prioriza Montevideo de tres formas combinadas:
  #   1. countrycodes = uy  -> nunca sale de Uruguay.
  #   2. viewbox del departamento + bounded = 1 -> primero busca SÓLO dentro del
  #      recuadro de Montevideo.
  #   3. si el usuario escribió sólo calle/número (sin coma), se agrega
  #      ", Montevideo" al texto para desambiguar de localidades homónimas de
  #      otros departamentos (ej.: "18 de Julio" también es un pueblo en Rocha).
  # Además, de los resultados se elige el primero cuyo departamento (address$state)
  # sea Montevideo; sólo si ninguno lo es se cae a un resultado del resto del país.
  observeEvent(input$btn_buscar_dir, {
    query <- trimws(input$busqueda_dir_mapa)
    req(nchar(query) >= 3)

    # Recuadro aproximado del departamento de Montevideo: left,top,right,bottom
    viewbox_mvd <- "-56.52,-34.68,-56.00,-34.98"
    query_ctx <- if (grepl(",", query)) query else paste0(query, ", Montevideo")

    geocodificar <- function(q, bounded) {
      resp <- tryCatch(
        httr::GET(
          "https://nominatim.openstreetmap.org/search",
          query = list(
            q              = q,
            format         = "jsonv2",
            countrycodes   = "uy",
            viewbox        = viewbox_mvd,
            bounded        = bounded,
            addressdetails = 1,
            limit          = 5
          ),
          httr::user_agent("ShinyApp-Nicolas (gestion GIDs Montevideo)"),
          httr::timeout(10)
        ),
        error = function(e) NULL
      )
      if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)
      res <- tryCatch(
        jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8")),
        error = function(e) NULL
      )
      if (is.null(res) || !is.data.frame(res) || nrow(res) == 0) return(NULL)
      res
    }

    # Primer resultado cuyo departamento sea Montevideo (NULL si ninguno lo es).
    fila_montevideo <- function(res) {
      if (is.null(res) || is.null(res$address) || is.null(res$address$state)) return(NULL)
      estado <- res$address$state
      idx <- which(!is.na(estado) & grepl("Montevideo", estado, ignore.case = TRUE))
      if (length(idx) == 0) return(NULL)
      res[idx[1], ]
    }

    hit <- fila_montevideo(geocodificar(query_ctx, bounded = 1))
    if (is.null(hit)) hit <- fila_montevideo(geocodificar(query,     bounded = 1))
    if (is.null(hit)) hit <- fila_montevideo(geocodificar(query_ctx, bounded = 0))

    fuera_mvd <- FALSE
    if (is.null(hit)) {
      res <- geocodificar(query, bounded = 0)
      if (!is.null(res)) {
        hit <- res[1, ]
        fuera_mvd <- TRUE
      }
    }

    if (is.null(hit)) {
      showNotification(
        paste0("No se encontró la dirección: '", query, "'"),
        type = "warning", duration = 4
      )
      return(invisible())
    }

    lat <- as.numeric(hit$lat)
    lon <- as.numeric(hit$lon)

    leafletProxy("map") %>%
      clearGroup("geocode") %>%
      setView(lng = lon, lat = lat, zoom = 18) %>%
      addMarkers(
        lng = lon, lat = lat, group = "geocode",
        popup = paste0(
          "<div style='font-family: Arial, sans-serif; min-width: 200px;'>",
          "<h6 style='margin: 0 0 8px 0; color: #007bff; font-weight: bold;'>",
          "<i class='fas fa-map-marker-alt'></i> Direccion</h6>",
          hit$display_name,
          "</div>"
        )
      )

    if (fuera_mvd) {
      showNotification(
        "La direccion esta fuera de Montevideo (resultado en Uruguay).",
        type = "message", duration = 4
      )
    }
  })

  # --- Lógica del Histórico ---

  # Filtramos el dataframe reactivamente según el GID y el rango de fechas elegidos
  datos_filtrados <- reactive({
    req(input$busqueda_gid, input$rango_fechas_historico)
    gid_buscado <- trimws(input$busqueda_gid)
    fecha_desde <- input$rango_fechas_historico[1]
    fecha_hasta <- input$rango_fechas_historico[2]

    datos()$historico_llenado %>%
      filter(
        as.character(gid) == gid_buscado,
        as.Date(Fecha) >= fecha_desde,
        as.Date(Fecha) <= fecha_hasta
      ) %>%
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
              icon("exclamation-triangle"), " No se encontraron registros de llenado para el GID ", input$busqueda_gid, " en el rango de fechas seleccionado"
            )
          )
        )
      )
    }

    # Llenado promedio en el rango seleccionado (ignorando NA)
    llenado_prom <- mean(as.numeric(df$Porcentaje_llenado), na.rm = TRUE)
    llenado_prom_txt <- if (is.nan(llenado_prom)) "N/A" else paste0(round(llenado_prom, 1), "%")

    # Determinar estado activo/inactivo actual del GID
    gid_actual <- trimws(input$busqueda_gid)
    esta_activo <- gid_actual %in% as.character(datos()$activos$GID)
    estado_txt <- if (esta_activo) "Activo" else "Inactivo"
    estado_color <- if (esta_activo) "success" else "danger"
    estado_icon <- if (esta_activo) "check-circle" else "ban"

    fluidRow(
      # Tarjeta 1: Llenado promedio en el rango
      valueBox(
        value = llenado_prom_txt,
        subtitle = "Llenado Promedio (en el rango)",
        icon = icon("tachometer-alt"),
        color = "info",
        width = 6
      ),
      # Tarjeta 2: Estado actual
      valueBox(
        value = estado_txt,
        subtitle = "Estado del Contenedor",
        icon = icon(estado_icon),
        color = estado_color,
        width = 6
      )
    )
  })

  # Segunda fila de KPIs: frecuencia de levante y saturación, ambas acotadas
  # al rango de fechas elegido por el usuario (input$rango_fechas_historico).
  output$kpis_historico_frecuencia <- renderUI({
    req(input$busqueda_gid)
    df <- datos_filtrados()
    if (nrow(df) == 0) return(NULL)

    levantes <- df %>%
      filter(Levantado == "S") %>%
      mutate(Fecha = as.Date(Fecha)) %>%
      arrange(Fecha)

    fechas_unicas <- unique(levantes$Fecha)
    frecuencia_txt <- if (length(fechas_unicas) >= 2) {
      dias_entre_levantes <- as.numeric(diff(fechas_unicas), units = "days")
      paste0("cada ", round(mean(dias_entre_levantes), 1), " días")
    } else {
      "N/A"
    }

    saturacion_txt <- if (nrow(levantes) > 0) {
      pct_saturacion <- mean(as.numeric(levantes$Porcentaje_llenado) == 100, na.rm = TRUE) * 100
      paste0(round(pct_saturacion, 0), "%")
    } else {
      "N/A"
    }

    fluidRow(
      # Tarjeta 5: Frecuencia promedio de levante en el rango
      valueBox(
        value = frecuencia_txt,
        subtitle = "Frecuencia de Levante (promedio, en el rango)",
        icon = icon("calendar-check"),
        color = "primary",
        width = 6
      ),
      # Tarjeta 6: % de saturación en el rango
      valueBox(
        value = saturacion_txt,
        subtitle = "% Saturación (en el rango)",
        icon = icon("exclamation-triangle"),
        color = "warning",
        width = 6
      )
    )
  })

  # Tercera fila de KPIs: diferencia entre "no levantado con incidencia" (N)
  # y "camión no pasó" (NA) — son dos fallas distintas, no se agrupan.
  output$kpis_historico_no_levante <- renderUI({
    req(input$busqueda_gid)
    df <- datos_filtrados()
    if (nrow(df) == 0) return(NULL)

    total_programado <- nrow(df)

    # "N": el camión pasó pero no levantó, hay una Incidencia que lo justifica
    n_no_levante_justificado <- sum(df$Levantado == "N", na.rm = TRUE)
    # NA: estaba programado en el circuito pero el camión no llegó a pasar (sin registro)
    n_camion_no_paso <- sum(is.na(df$Levantado))

    pct_justificado_txt <- paste0(round(100 * n_no_levante_justificado / total_programado, 1), "%")
    pct_no_paso_txt      <- paste0(round(100 * n_camion_no_paso / total_programado, 1), "%")

    fluidRow(
      # Tarjeta 8: No levantado con incidencia justificada
      valueBox(
        value = pct_justificado_txt,
        subtitle = paste0("No Levantado con Incidencia (", n_no_levante_justificado, " de ", total_programado, ")"),
        icon = icon("triangle-exclamation"),
        color = "danger",
        width = 6
      ),
      # Tarjeta 9: Camión no pasó (programado pero sin registro)
      valueBox(
        value = pct_no_paso_txt,
        subtitle = paste0("Camión No Pasó, Programado (", n_camion_no_paso, " de ", total_programado, ")"),
        icon = icon("route"),
        color = "secondary",
        width = 6
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