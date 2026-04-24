library(shiny)
library(leaflet)
library(leaflet.extras)
library(sf)
library(pins)
library(dplyr)
library(DT)
library(bs4Dash)

# --- DETECCIÓN DE ENTORNO Y CARGA DE DATOS ---
# En local: lee desde la carpeta "data/" (generada por limpieza_datos.R)
# En Shiny: lee directamente desde GitHub raw (sin necesidad de PAT si el repo es público)

url_github <- "https://raw.githubusercontent.com/liottinicolas/APP_nuevoinforme/main/vistas/App_informe_llenado/data/"

if (dir.exists("data")) {
  # Entorno local: usar carpeta de datos local
  board <- pins::board_folder("data", versioned = FALSE)
} else {
  # Entorno Shiny: leer desde GitHub raw URLs
  board <- pins::board_url(c(
    "GID_activos"           = paste0(url_github, "GID_activos/"),
    "GID_inactivos"         = paste0(url_github, "GID_inactivos/"),
    "historico_llenado_web" = paste0(url_github, "historico_llenado_web/")
  ))
}

# Función de preprocesamiento (se define una vez al inicio, no depende de los datos)
preprocesar_datos <- function(df) {
  if (!inherits(df, "sf")) {
    df <- st_as_sf(df, wkt = "THE_GEOM", crs = 32721)
  }
  return(st_transform(df, 4326))
}

# Intervalo de recarga automática: cada 6 horas (en milisegundos)
# Ajustá este valor si necesitás más o menos frecuencia
INTERVALO_RECARGA_MS <- 6 * 60 * 60 * 1000

lat_mvd <- -34.8636
lng_mvd <- -56.1679

ui <- dashboardPage(
  
  # 1. Barra Superior
  header = dashboardHeader(
    title = "Gestión de GIDs",
    skin = "light",
    rightUi = tags$li(
      class = "nav-item dropdown d-flex align-items-center px-3",
      tags$span(
        style = "background-color: #17a2b8; color: white; padding: 4px 12px; border-radius: 20px; font-size: 0.85rem; font-weight: 600;",
        icon("calendar-alt"),
        textOutput("fecha_actualizacion", inline = TRUE)
      )
    )
  ),
  
  # 2. Menú Lateral (Tus antiguas pestañas van aquí)
  sidebar = dashboardSidebar(
    skin = "dark",
    sidebarMenu(
      menuItem("Mapa Interactivo", tabName = "mapa", icon = icon("map")),
      menuItem("Histórico de Llenado", tabName = "hist", icon = icon("table"))
    )
  ),
  
  # 3. Cuerpo Principal (El contenido de cada pestaña)
  body = dashboardBody(
    tabItems(
      
      # Contenido de la pestaña MAPA
      tabItem(tabName = "mapa",
              fluidRow(
                # Una tarjeta (box) para los controles
                box(
                  title = "Controles", width = 3, status = "primary",
                  radioButtons("seleccion_estado", "Ver en el mapa:",
                               choices = list("GIDs Activos" = "act", "GIDs Inactivos" = "inact"))
                ),
                # Una tarjeta para el mapa
                box(
                  title = "Visor Geográfico", width = 9, maximizable = TRUE, status = "info",
                  leafletOutput("map", height = "600px")
                )
              )
      ),
      
      # Contenido de la pestaña HISTÓRICO
      tabItem(tabName = "hist",
              
              # Fila 1: Buscador (Arriba)
              fluidRow(
                box(
                  title = "Búsqueda de Contenedor", 
                  width = 12, # Ocupa todo el ancho
                  status = "primary", 
                  solidHeader = TRUE, # Le da un fondo de color al título de la caja
                  icon = icon("search"),
                  
                  textInput("busqueda_gid", "Ingrese el número de GID para consultar su historial:", 
                            placeholder = "Ej: 12345"),
                  helpText("Presione Enter para ver los resultados.")
                )
              ),
              
              # Fila 2: Tabla de Resultados (Debajo)
              fluidRow(
                box(
                  title = "Historial de Llenado", 
                  width = 12, # Ocupa todo el ancho
                  status = "success", 
                  solidHeader = TRUE,
                  icon = icon("list"),
                  
                  # Aquí va la tabla
                  DTOutput("tabla_historico")
                )
              )
      )
    )
  )
)

server <- function(input, output, session) {

  # --- Carga de datos reactiva -------------------------------------------
  # invalidateLater() hace que este reactive se re-ejecute automáticamente
  # cada INTERVALO_RECARGA_MS milisegundos, descargando los pines frescos
  # desde GitHub sin necesidad de reiniciar ni redesplegar la app.
  datos <- reactive({
    invalidateLater(INTERVALO_RECARGA_MS, session)
    list(
      activos           = preprocesar_datos(board %>% pin_read("GID_activos")),
      inactivos         = preprocesar_datos(board %>% pin_read("GID_inactivos")),
      historico_llenado = board %>% pin_read("historico_llenado_web")
    )
  })

  # Fecha máxima dinámica: se actualiza cuando datos() se recarga
  output$fecha_actualizacion <- renderText({
    fecha <- format(max(as.Date(datos()$historico_llenado$Fecha), na.rm = TRUE), "%d/%m/%Y")
    paste0(" Última actualización: ", fecha)
  })

  # --- Lógica del Mapa ---------------------------------------------------
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = lng_mvd, lat = lat_mvd, zoom = 12) %>%
      addCircleMarkers(
        data = datos()$activos, group = "activos",
        radius = 5, color = "blue", stroke = FALSE, fillOpacity = 0.7,
        popup = ~paste0("<b>ID:</b> ", GID, "<br><b>Dirección:</b> ", DIRECCION),
        label = ~as.character(GID)
      ) %>%
      addCircleMarkers(
        data = datos()$inactivos, group = "inactivos",
        radius = 5, color = "red", stroke = FALSE, fillOpacity = 0.7,
        popup = ~paste0("<b>ID:</b> ", GID, "<br><b>Fecha Hasta:</b> ", FECHA_HASTA),
        label = ~as.character(GID)
      ) %>%
      addSearchOSM(options = searchOptions(collapsed = TRUE)) %>% 
      addSearchFeatures(
        targetGroups = c("activos", "inactivos"),
        options = searchFeaturesOptions(propertyName = "label", zoom = 16, openPopup = TRUE)
      ) %>%
      hideGroup("inactivos")
  })
  
  observeEvent(input$seleccion_estado, {
    proxy <- leafletProxy("map")
    if (input$seleccion_estado == "act") {
      proxy %>% showGroup("activos") %>% hideGroup("inactivos")
    } else {
      proxy %>% showGroup("inactivos") %>% hideGroup("activos")
    }
  }, ignoreInit = TRUE)
  
  # --- Lógica del Histórico ---

  # Filtramos el dataframe reactivamente según el texto ingresado
  datos_filtrados <- reactive({
    req(input$busqueda_gid)

    datos()$historico_llenado %>%
      filter(as.character(gid) == input$busqueda_gid) %>%
      select(
        Fecha, Circuito, Posicion, Direccion, Levantado,
        Turno_levantado, Fecha_hora_pasaje, Id_viaje_GOL,
        Incidencia, Porcentaje_llenado, Condicion, contenedor_activo
      )
  })
  
  output$tabla_historico <- renderDT({
    
    # Ordenamos el dataframe reactivo de más reciente a más antiguo
    datos_ordenados <- datos_filtrados() %>%
      arrange(desc(Fecha)) 
    
    datatable(
      datos_ordenados, # Pasamos el dataframe ya ordenado
      colnames = c(
        "Fecha", "Circuito", "Posicion", "Dirección", "Levante", 
        "Turno", "Hora", "ID_Viaje_GOL", "Incidencia", 
        "% Llenado", "Condición", "Estado"
      ),
      options = list(
        pageLength = 15,
        language = list(url = '//cdn.datatables.net/plug-ins/1.10.11/i18n/Spanish.json'),
        scrollX = TRUE
      ),
      rownames = FALSE
    )
  })
}

shinyApp(ui, server)