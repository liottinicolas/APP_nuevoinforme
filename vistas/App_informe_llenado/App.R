library(shiny)
library(leaflet)
library(leaflet.extras)
library(sf)
library(pins)
library(dplyr)
library(DT)


# 1. CARGA Y PREPROCESAMIENTO DE DATOS
board <- board_folder("data")

preprocesar_datos <- function(df) {
  if (!inherits(df, "sf")) {
    df <- st_as_sf(df, wkt = "THE_GEOM", crs = 32721)
  }
  return(st_transform(df, 4326))
}

# Cargamos los pins
GID_activos       <- preprocesar_datos(board %>% pin_read("GID_activos"))
GID_inactivos     <- preprocesar_datos(board %>% pin_read("GID_inactivos"))
historico_llenado <- board %>% pin_read("historico_llenado")

lat_mvd <- -34.8636
lng_mvd <- -56.1679

ui <- fluidPage(
  
  titlePanel("Gestión de GIDs - Montevideo"),
  
  # Estructura de Pestañas
  tabsetPanel(
    # PESTAÑA 1: MAPA
    tabPanel("Mapa Interactivo",
             sidebarLayout(
               sidebarPanel(
                 radioButtons("seleccion_estado", "Ver en el mapa:",
                              choices = list("GIDs Activos" = "act", 
                                             "GIDs Inactivos" = "inact"),
                              selected = "act"),
                 hr(),
                 helpText("Usa la lupa en el mapa para buscar un GID específico.")
               ),
               mainPanel(
                 tags$style(type = "text/css", "#map {height: calc(100vh - 80px) !important;}"),
                 leafletOutput("map")
               )
             )
    ),
    
    # PESTAÑA 2: HISTÓRICO
    tabPanel("Histórico de Llenado",
             fluidRow(
               column(4, 
                      wellPanel(
                        textInput("busqueda_gid", "Ingrese GID para consultar:", value = ""),
                        helpText("Presione Enter o espere un momento para actualizar la tabla.")
                      )
               ),
               column(8,
                      h4("Registros de Llenado"),
                      DTOutput("tabla_historico")
               )
             )
    )
  )
)

server <- function(input, output, session) {
  
  # --- Lógica del Mapa ---
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = lng_mvd, lat = lat_mvd, zoom = 12) %>%
      addCircleMarkers(
        data = GID_activos, group = "activos",
        radius = 5, color = "blue", stroke = FALSE, fillOpacity = 0.7,
        popup = ~paste0("<b>ID:</b> ", GID, "<br><b>Dirección:</b> ", DIRECCION),
        label = ~as.character(GID)
      ) %>%
      addCircleMarkers(
        data = GID_inactivos, group = "inactivos",
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
    req(input$busqueda_gid) # Solo corre si hay algo escrito
    
    historico_llenado %>%
      # Convertimos a carácter para asegurar que la comparación funcione
      filter(as.character(gid) == input$busqueda_gid) %>%
      select(
        Fecha, Circuito, Posicion, Direccion, Levantado, 
        Turno_levantado, Fecha_hora_pasaje, Id_viaje_GOL, 
        Incidencia, Porcentaje_llenado, Condicion, contenedor_activo
      )
  })
  
  output$tabla_historico <- renderDT({
    datatable(
      datos_filtrados(),
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