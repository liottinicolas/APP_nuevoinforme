########################
# SECCIÓN 0: CARGA DE CONFIGURACIÓN
########################

# Cargar archivo de configuración
tryCatch({
  source("config.R")
}, error = function(e) {
  stop("Error al cargar archivo de configuración: ", e$message)
})

########################
# SECCIÓN 1: SISTEMA DE LOGGING
########################

# Cargar archivo de logging
tryCatch({
  source("logging.R")
}, error = function(e) {
  stop("Error al cargar archivo de logging: ", e$message)
})

########################
# SECCIÓN 2: CARGA DE DEPENDENCIAS
########################

# Función para cargar archivos con manejo de errores
cargar_archivo <- function(ruta_archivo) {
  tryCatch({
    source(ruta_archivo)
    escribir_log("INFO", paste("Archivo cargado con éxito:", ruta_archivo))
  }, error = function(e) {
    manejar_error(e, paste("al cargar", ruta_archivo))
  })
}

# Cargo paquetes y funciones básicas
cargar_archivo("global.R")
Fecha_inicio_informe <- as.Date("2025-03-03")

ruta_proyecto <- here()

## Cargo el historico ubicaciones.
ruta_base <- file.path("scripts/db", "10393_ubicaciones")
ruta_RDS_datos <- file.path(ruta_proyecto, ruta_base, paste0("historico_", "ubicaciones", ".rds"))
ubicaciones <- readRDS(ruta_RDS_datos)
ubicaciones <- ubicaciones %>% 
  filter(Fecha >= "2025-03-03")

funcion_obtener_planificados <- function(){
  
  planificacion <- read_excel(
    "scripts/visitados/planificacion.xlsx",
    #"planificacion.xlsx",
    sheet = "historico",
    range = cell_cols("A:L"))
  
  total_contenedores_im <- ubicaciones |>
    mutate(Estado = na_if(trimws(Estado), "")) |>   # trata "" como NA
    group_by(Fecha, Circuito) |>
    summarise(
      Activos   = sum(is.na(Estado)),
      Inactivos = sum(!is.na(Estado)),
      .groups = "drop"
    ) |>
    arrange(Fecha, Circuito)
  
  
  ## Filtro a partir de la fecha los planificados y le quito los valores que allí tienen.
  planificacion_arreglada <- planificacion %>% 
    select(DIA,NOMBREDIA,Frecuencia,Periodo,ID_TURNO,MUNICIPIO,CIRCUITO,GRUPO) %>% 
    rename(Fecha = DIA,
           Dia = NOMBREDIA,
           Id_turno = ID_TURNO,
           Municipio = MUNICIPIO,
           Circuito = CIRCUITO,
           Grupo = GRUPO) %>% 
    filter(Fecha >= Fecha_inicio_informe)
  
  fecha_maxima_planificacion <- max(planificacion_arreglada$Fecha)
  
  
  # 1) Asegurar una única fila por (Fecha, Circuito) en los totales
  tot_key <- total_contenedores_im %>%
    mutate(
      Fecha    = as.Date(Fecha),
      Circuito = as.character(Circuito)
    ) %>%
    group_by(Fecha, Circuito) %>%
    summarise(
      Activos   = sum(Activos,   na.rm = TRUE),
      Inactivos = sum(Inactivos, na.rm = TRUE),
      .groups = "drop"
    )
  
  # Agrego planificados.
  planificacion_arreglada <- planificacion_arreglada %>%
    mutate(
      Fecha    = as.Date(Fecha),
      Circuito = as.character(Circuito)
    ) %>%
    left_join(tot_key, by = c("Fecha", "Circuito")) %>%
    mutate(
      Activos   = coalesce(Activos,   0L),
      Inactivos = coalesce(Inactivos, 0L)
    )
  
  fecha_maxima_contenedoresim <- max(total_contenedores_im$Fecha)
  
  # # fecha máxima en contenedores_im
  # f_max <- total_contenedores_im %>%
  #   mutate(Fecha = as.Date(Fecha)) %>%
  #   summarise(f = max(Fecha, na.rm = TRUE)) %>%
  #   pull(f)
  
  # filtrar planificacion_arreglada2 a esa fecha
  planificacion_arreglada <- planificacion_arreglada %>%
    filter(Fecha <= fecha_maxima_contenedoresim)
  
  return (planificacion_arreglada)
  
}

### Previa | Vectores de motivos de visita y no visita. ----

# Vectores de caracteres
motivos_con_visita <- c(
  "Medidas gremiales",
  "Habilitado tarde (Mantenimiento)",
  "No Levantado por Feria",
  "Sobrepeso",
  "Auto",
  "Calle Cerrada",
  "Tapa Bloqueda",
  "Persona en el Interior del Cont.",
  "Sin ticket de cantera",
  "Contenedor Roto (choque, desfonde, etc.)",
  "Fuego",
  "Contenedor No Está",
  "Contenedor Fuera de Alcance",
  "Contenedor Volcado",
  "Contenedor Cruzado",
  "Buzonera Girada",
  "Otros"
)

motivos_sin_visita <- c(
  "Rotura con retorno a circuito",
  "Rotura sin retorno a circuito",
  "Horas permiso auxiliar",
  "Horas permiso chofer",
  "Horas permiso aux y chof",
  "Camion a Lavadero",
  "Demora en cantera",
  "Viaje suspendido",
  "Capacidad del Camion y/o Tiempo"
)

# Opcional: lista nombrada
motivos <- list(
  con_visita = motivos_con_visita,
  sin_visita = motivos_sin_visita
)

# Opcional: data.frame útil para joins/validaciones
motivos_df <- rbind(
  data.frame(tipo = "Visitado", motivo = motivos_con_visita,  stringsAsFactors = FALSE),
  data.frame(tipo = "No visitado", motivo = motivos_sin_visita, stringsAsFactors = FALSE)
)

#########




## Cargo el historico llenado.
ruta_base <- file.path("scripts/db", "GOL_reportes")
ruta_RDS_datos <- file.path(ruta_proyecto, ruta_base, paste0("historico_", "llenadoGol", ".rds"))

gol_visitayprogramado <- readRDS(ruta_RDS_datos)

gol_visitayprogramado_completo <- gol_visitayprogramado %>%
  mutate(
    Oficina = ifelse(
      grepl("^B_0?[1-7](\\b|$)", Circuito_corto),
      "Fideicomiso", "IM"
    )
  ) %>% 
  arrange(desc(Fecha)) %>% 
  filter(Fecha >= "2025-03-03")

# df_llenado <- gol_visitayprogramado_completo
funcion_df_nuevoinformediario_sincap <- function(df_llenado){
  
  # Usa "Incidencias" si existe, si no "Incidencia"
  inc_col <- if ("Incidencias" %in% names(df_llenado)) "Incidencias" else "Incidencia"
  
  gol_visitayprogramado_completo_nuevo <- df_llenado %>%
    mutate(
      Visitado = case_when(
        Levantado == "S" ~ "Visitado",
        is.na(Levantado) ~ "No visitado",
        Levantado == "N" & .data[[inc_col]] %in% motivos_con_visita ~ "Visitado",
        Levantado == "N" ~ "No visitado",
        TRUE ~ NA_character_
      )
    ) %>% 
    filter(Oficina == "IM")
  
  # universo fijo de municipios
  municipios <- c("A","B","C","CH","D","E","F","G")
  
  df_resumen <- gol_visitayprogramado_completo_nuevo %>%
    mutate(
      Fecha = as.Date(Fecha),
      Municipio = toupper(trimws(Municipio))
    ) %>%
    group_by(Fecha, Municipio) %>%
    summarise(
      Programado   = n(),
      Visitados    = sum(Visitado == "Visitado",    na.rm = TRUE),
      No_visitados = sum(Visitado == "No visitado", na.rm = TRUE),
      Vaciados     = sum(Levantado == "S",          na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(No_Vaciados = Visitados - Vaciados) %>%
    group_by(Fecha) %>%
    # garantiza que existan siempre los 8 municipios por fecha
    complete(
      Municipio = municipios,
      fill = list(
        Programado = 0,
        Visitados = 0,
        No_visitados = 0,
        Vaciados = 0,
        No_Vaciados = 0
      )
    ) %>%
    ungroup() %>%
    # evita negativos por inconsistencias
    mutate(No_Vaciados = pmax(0, No_Vaciados)) %>%
    arrange(Fecha, factor(Municipio, levels = municipios))
  
    planificados <- funcion_obtener_planificados()
    
    planificados_final <- planificados %>%
      mutate(
        Fecha = as.Date(Fecha),
        Activos = coalesce(as.integer(Activos), 0L),
        Inactivos = coalesce(as.integer(Inactivos), 0L)
      ) %>%
      group_by(Fecha, Municipio) %>%
      summarise(
        Activos = sum(Activos, na.rm = TRUE),
        Inactivos = sum(Inactivos, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(Planificados = Activos + Inactivos) %>% 
      arrange(Fecha, Municipio)
    
    # Tomo solo la columna Planificados desde res_por_fecha_mpio
    planif_key <- planificados_final %>%
      transmute(
        Fecha = as.Date(Fecha),
        Municipio = as.character(Municipio),
        Activos = as.integer(Activos)
      )
    
    df_resumen2 <- df_resumen %>%
      mutate(
        Fecha = as.Date(Fecha),
        Municipio = as.character(Municipio)
      ) %>%
      left_join(planif_key, by = c("Fecha","Municipio")) %>%
      relocate(Activos, .after = Municipio) %>% 
      rename(Planificados = Activos)
    
    df_resumen2 <- df_resumen2 %>% 
      mutate(Planificados = coalesce(Planificados, 0L)) %>% 
      arrange(desc(Fecha),Municipio)
    
    old <- Sys.getlocale("LC_TIME")
    try(Sys.setlocale("LC_TIME","es_UY.UTF-8"), silent = TRUE)
    
    df_resumen2 <- df_resumen2 %>%
      mutate(
        Fecha = as.Date(Fecha),
        Dia   = format(Fecha, "%A")
      ) %>%
      relocate(Dia, .after = Fecha)
    
    try(Sys.setlocale("LC_TIME", old), silent = TRUE)
    
    ## Agrupados
    
    df_resumen_agrupado_pordia <- df_resumen2 %>%
      group_by(Fecha) %>%
      summarise(
        Dia           = first(Dia),
        Planificados  = sum(as.numeric(Planificados),  na.rm = TRUE),
        Programado    = sum(as.numeric(Programado),    na.rm = TRUE),
        Visitados     = sum(as.numeric(Visitados),     na.rm = TRUE),
        No_visitados  = sum(as.numeric(No_visitados),  na.rm = TRUE),
        Vaciados      = sum(as.numeric(Vaciados),      na.rm = TRUE),
        No_Vaciados   = sum(as.numeric(No_Vaciados),   na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(Fecha)
  
  
  return(list(
    resumen_por_dia_y_municipio = df_resumen2,
    resumen_por_dia = df_resumen_agrupado_pordia
  ))
  
  
}

 informe_final <- funcion_df_nuevoinformediario_sincap(gol_visitayprogramado_completo)
 resumen_dia_y_municipio <- informe_final$resumen_por_dia_y_municipio
 resumen_dia <- informe_final$resumen_por_dia
 
 
 hoy_posiciones <- historico_ubicaciones %>% 
   filter(Fecha == "2026-02-05")
 
 hoy_levantes <- prueba
 
### Agrupado por semana ---- 
 
 # df <- resumen_dia
funcion_agrupar_datos_por_semana <- function(df){
  
  # Elegí qué métricas promediar y graficar
  metricas <- c("Planificados","Programado","Visitados","No_visitados","Vaciados","No_Vaciados")
  cols_prom <- paste0(metricas, "_prom_dia")
  
  semana_resumen <- df %>%
    mutate(
      Fecha  = as.Date(Fecha),
      Semana = floor_date(Fecha, unit = "week", week_start = 1)  # lunes a domingo
    ) %>%
    group_by(Semana) %>%
    summarise(
      dias_presentes = n_distinct(Fecha),
      across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE), .names = "{.col}_sum"),
      across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE) / dias_presentes, .names = "{.col}_prom_dia"),
      .groups = "drop"
    ) %>%
    arrange(Semana)

  
  
  semana_resumen2 <- df %>%
    mutate(
      Fecha = as.Date(Fecha),
      Semana_inicio = floor_date(Fecha, unit = "week", week_start = 1)
    ) %>%
    group_by(Semana_inicio) %>%
    summarise(
      Semana_fin     = max(Fecha),
      dias_presentes = n_distinct(Fecha),
      across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE), .names = "{.col}_sum"),
      across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE) / dias_presentes, .names = "{.col}_prom_dia"),
      .groups = "drop"
    ) %>%
    arrange(Semana_inicio)
  
  return (semana_resumen2)
  
  
}
 

 resumen_semanal <- funcion_agrupar_datos_por_semana(resumen_dia)
 
##################### Lo más pedido.
 
 ## Selecciono los lunes
 
 df_lunes <- resumen_dia  %>% 
   filter(Dia == "lunes")
 
 
 
 
#### pongo todo en excel
 
 # Tu data frame
 resumen_dia_y_municipio <- resumen_dia_y_municipio %>%  # ejemplo
   arrange(Fecha)
 
 # 1) Crear libro y hoja "DB"
 wb <- createWorkbook()
 addWorksheet(wb, "DB")
 addWorksheet(wb, "Info_Por_dia")
 addWorksheet(wb, "Info_lunes")
 addWorksheet(wb, "Resumen_semanal")
 
 # 2) Escribir como Tabla de Excel con estilo
 writeDataTable(
   wb, sheet = "DB", x = resumen_dia_y_municipio,
   tableName   = "Tabla_DB",
   withFilter  = TRUE,
   tableStyle  = "TableStyleLight1"  # elegí cualquier estilo válido
 )
 
 # 2) Escribir como Tabla de Excel con estilo
 writeDataTable(
   wb, sheet = "Info_Por_dia", x = resumen_dia,
   tableName   = "Tabla_PORDIA",
   withFilter  = TRUE,
   tableStyle  = "TableStyleLight1"  # elegí cualquier estilo válido
 )
 
 # 2) Escribir como Tabla de Excel con estilo
 writeDataTable(
   wb, sheet = "Info_lunes", x = df_lunes,
   tableName   = "Tabla_Lunes",
   withFilter  = TRUE,
   tableStyle  = "TableStyleLight1"  # elegí cualquier estilo válido
 )
 
 # 2) Escribir como Tabla de Excel con estilo
 writeDataTable(
   wb, sheet = "Resumen_semanal", x = resumen_semanal,
   tableName   = "Tabla_resumen_semanal",
   withFilter  = TRUE,
   tableStyle  = "TableStyleLight1"  # elegí cualquier estilo válido
 )
 
 # 3) Mejoras opcionales
 setColWidths(wb, "DB", cols = 1:ncol(resumen_dia_y_municipio), widths = "auto")   # ancho auto
 freezePane(wb, "DB", firstActiveRow = 2)                     # congela encabezado
 setColWidths(wb, "Info_Por_dia", cols = 1:ncol(resumen_dia), widths = "auto")   # ancho auto
 freezePane(wb, "Info_Por_dia", firstActiveRow = 2)                     # congela encabezado
 setColWidths(wb, "Info_lunes", cols = 1:ncol(df_lunes), widths = "auto")   # ancho auto
 freezePane(wb, "Info_lunes", firstActiveRow = 2)                     # congela encabezado
 setColWidths(wb, "Resumen_semanal", cols = 1:ncol(resumen_semanal), widths = "auto")   # ancho auto
 freezePane(wb, "Resumen_semanal", firstActiveRow = 2)                     # congela encabezado
 
 # 4) Guardar
 saveWorkbook(wb, "salida.xlsx", overwrite = TRUE)
 
 
 # 
 # 
 # 
 # library(dplyr)
 # library(lubridate)
 # library(highcharter)
 # library(tidyr)
 # library(DT)
 # library(htmlwidgets)
 # library(htmltools)
 # 
 # # ====== Datos de ejemplo (ya los tenés) ======
 # df <- resumen_dia_y_municipio %>% mutate(Fecha = as.Date(Fecha))
 # 
 # # ====== Gráfico diario ======
 # df_long <- df %>%
 #   select(Fecha, Planificados, Programado, Visitados, Vaciados) %>%
 #   pivot_longer(-Fecha, names_to = "metrica", values_to = "valor")
 # 
 # hc_diario <- hchart(
 #   df_long, "line",
 #   hcaes(x = Fecha, y = valor, group = metrica)
 # ) %>%
 #   hc_title(text = "Series diarias") %>%
 #   hc_xAxis(type = "datetime") %>%
 #   hc_exporting(enabled = TRUE) %>%
 #   hc_add_theme(hc_theme_smpl())
 # 
 # # ====== Resumen semanal (promedios por días presentes, lun-dom) ======
 # metricas <- c("Planificados","Programado","Visitados","Vaciados")
 # 
 # semana_resumen <- df %>%
 #   mutate(
 #     Semana_inicio = floor_date(Fecha, "week", week_start = 1),
 #     Semana_fin    = Semana_inicio + days(6)
 #   ) %>%
 #   group_by(Semana_inicio, Semana_fin) %>%
 #   summarise(
 #     dias_presentes = n_distinct(Fecha),
 #     across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE) / dias_presentes,
 #            .names = "{.col}_prom"),
 #     .groups = "drop"
 #   ) %>%
 #   arrange(Semana_inicio)
 # 
 # sem_long <- semana_resumen %>%
 #   select(Semana_inicio, ends_with("_prom")) %>%
 #   pivot_longer(-Semana_inicio, names_to = "metrica", values_to = "promedio") %>%
 #   mutate(metrica = sub("_prom$", "", metrica))
 # 
 # hc_semanal <- hchart(
 #   sem_long, "line",
 #   hcaes(x = Semana_inicio, y = promedio, group = metrica)
 # ) %>%
 #   hc_title(text = "Promedios diarios por semana") %>%
 #   hc_xAxis(type = "datetime") %>%
 #   hc_exporting(enabled = TRUE) %>%
 #   hc_add_theme(hc_theme_smpl())
 # 
 # # ====== Tablas interactivas (DT) ======
 # num_cols_df  <- intersect(names(df), metricas)
 # num_cols_sem <- grep("_prom$", names(semana_resumen), value = TRUE)
 # 
 # tbl_diario <- datatable(
 #   df,
 #   extensions = "Buttons",
 #   options = list(
 #     pageLength = 15, autoWidth = TRUE, dom = "Bfrtip",
 #     buttons = c("copy","csv","excel","pdf","print")
 #   ),
 #   rownames = FALSE, filter = "top"
 # ) %>%
 #   formatRound(columns = num_cols_df, digits = 0)
 # 
 # tbl_semanal <- datatable(
 #   semana_resumen,
 #   extensions = "Buttons",
 #   options = list(
 #     pageLength = 15, autoWidth = TRUE, dom = "Bfrtip",
 #     buttons = c("copy","csv","excel","pdf","print")
 #   ),
 #   rownames = FALSE, filter = "top"
 # ) %>%
 #   formatRound(columns = num_cols_sem, digits = 2)
 # 
 # # ====== Exportar todo a un HTML único ======
 # ui <- tagList(
 #   tags$h2("Series diarias"),
 #   hc_diario,
 #   tags$h3("Tabla diaria"),
 #   tbl_diario,
 #   tags$hr(),
 #   tags$h2("Promedios semanales"),
 #   hc_semanal,
 #   tags$h3("Tabla semanal"),
 #   tbl_semanal
 # )
 # 
 # htmltools::save_html(ui, file = "dashboard_interactivo.html",
 #                      background = "white", libdir = "libs")
 # 
 # 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

# 
# ### Graficas
# 
# library(ggplot2)
# library(scales)
# 
# df <- df_lunes_agrupado
# 
# # Eje X fecha, Y levantados (Vaciados)
# p <- ggplot(df, aes(x = as.Date(Fecha), y = Vaciados)) +
#   geom_line(linewidth = 0.9) +
#   geom_point(size = 1.8) +
#   labs(x = "Fecha", y = "Levantados", title = "Levantados por fecha") +
#   scale_x_date(date_breaks = "7 days", date_labels = "%d-%b") +
#   theme_minimal(base_size = 12)
# 
# library(plotly)
# library(htmlwidgets)
# 
# p_html <- ggplotly(p, tooltip = c("x","y"))
# saveWidget(as_widget(p_html), "levantados_por_fecha.html", selfcontained = TRUE)
# 
# ##
# 
# # Guardar para web
# ggsave("levantados_por_fecha.png", p, width = 1200, height = 600, units = "px", dpi = 120)
# ggsave("levantados_por_fecha.svg", p, width = 1200/96, height = 600/96, units = "in", dpi = 96)
# 
# 
# 
# 



library(dplyr)
library(lubridate)

# Datos diarios por fecha (ej.: df_resumen2_lunes_por_fecha)
# Columnas de métricas a promediar
metricas <- c("Planificados","Programado","Visitados","No_visitados","Vaciados","No_Vaciados")

semana_resumen <- df_resumen2 %>%
  mutate(
    Fecha  = as.Date(Fecha),
    Semana = floor_date(Fecha, unit = "week", week_start = 1)  # lunes a domingo
  ) %>%
  group_by(Semana) %>%
  summarise(
    dias_presentes = n_distinct(Fecha),
    across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE), .names = "{.col}_sum"),
    across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE) / dias_presentes, .names = "{.col}_prom_dia"),
    .groups = "drop"
  ) %>%
  arrange(Semana)



semana_resumen <- df_resumen2 %>%
  mutate(
    Fecha = as.Date(Fecha),
    Semana_inicio = floor_date(Fecha, unit = "week", week_start = 1)
  ) %>%
  group_by(Semana_inicio) %>%
  summarise(
    Semana_fin     = max(Fecha),
    dias_presentes = n_distinct(Fecha),
    across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE), .names = "{.col}_sum"),
    across(all_of(metricas), ~ sum(as.numeric(.), na.rm = TRUE) / dias_presentes, .names = "{.col}_prom_dia"),
    .groups = "drop"
  ) %>%
  arrange(Semana_inicio)


# 
# 
# 
# # Asumo que ya tenés 'semana_resumen' con columnas:
# # Semana_inicio, Semana_fin, dias_presentes, y *_prom_dia
# 
# 
# # Elegí qué métricas promediar y graficar
# metricas <- c("Planificados","Programado","Visitados","No_visitados","Vaciados","No_Vaciados")
# cols_prom <- paste0(metricas, "_prom_dia")
# 
# # Etiqueta semana "YYYY-MM-DD → YYYY-MM-DD"
# semana_plot <- semana_resumen %>%
#   mutate(
#     Semana_inicio = as.Date(Semana_inicio),
#     Semana_fin    = as.Date(Semana_fin),
#     Semana_label  = paste0(format(Semana_inicio, "%Y-%m-%d"),
#                            " \u2192 ",
#                            format(Semana_fin, "%Y-%m-%d"))
#   ) %>%
#   select(Semana_inicio, Semana_fin, Semana_label, dias_presentes, all_of(cols_prom)) %>%
#   pivot_longer(all_of(cols_prom),
#                names_to = "metrica",
#                values_to = "promedio") %>%
#   mutate(metrica = gsub("_prom_dia$", "", metrica))
# 
# # -------- SVG estático web-friendly --------
# p <- ggplot(semana_plot,
#             aes(x = Semana_inicio, y = promedio, group = metrica)) +
#   geom_line(linewidth = 0.9) +
#   geom_point(size = 1.8) +
#   labs(
#     title = "Promedios diarios por semana",
#     x = "Semana (inicio lunes)",
#     y = "Promedio diario",
#     caption = "Promedio = suma de la semana / días presentes"
#   ) +
#   scale_x_date(date_breaks = "1 week", date_labels = "%d-%b") +
#   facet_wrap(~ metrica, scales = "free_y", ncol = 2) +
#   theme_minimal(base_size = 12)
# 
# # Exportá SVG y PNG
# ggsave("promedios_semanales.svg", p, width = 1200/96, height = 800/96, units = "in", dpi = 96)
# ggsave("promedios_semanales.png", p, width = 1200, height = 800, units = "px", dpi = 120)
# 
# # -------- HTML interactivo autónomo --------
# p_html <- ggplotly(p, tooltip = c("x","y")) %>%
#   style(hovertemplate = paste(
#     "Semana inicio: %{x|%Y-%m-%d}<br>",
#     "Promedio: %{y:.2f}<extra></extra>"
#   ))
# 
# saveWidget(as_widget(p_html), "promedios_semanales.html", selfcontained = TRUE)

# df_llenado <- gol_visitayprogramado_completo
# funcion_df_nuevoinformediario_sincap_porturnos <- function(df_llenado){
#   
#   # Usa "Incidencias" si existe, si no "Incidencia"
#   inc_col <- if ("Incidencias" %in% names(df_llenado)) "Incidencias" else "Incidencia"
#   
#   gol_visitayprogramado_completo_nuevo <- df_llenado %>%
#     mutate(
#       Visitado = case_when(
#         Levantado == "S" ~ "Visitado",
#         is.na(Levantado) ~ "No visitado",
#         Levantado == "N" & .data[[inc_col]] %in% motivos_con_visita ~ "Visitado",
#         Levantado == "N" ~ "No visitado",
#         TRUE ~ NA_character_
#       )
#     ) %>% 
#     filter(Oficina == "IM")
#   
#   # universo fijo de municipios
#   municipios <- c("A","B","C","CH","D","E","F","G")
#   
#   df_resumen_conturno <- gol_visitayprogramado_completo_nuevo %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Municipio = toupper(trimws(Municipio))
#     ) %>%
#     group_by(Fecha, Municipio,Turno_levantado) %>%
#     summarise(
#       Programado   = n(),
#       Visitados    = sum(Visitado == "Visitado",    na.rm = TRUE),
#       No_visitados = sum(Visitado == "No visitado", na.rm = TRUE),
#       Vaciados     = sum(Levantado == "S",          na.rm = TRUE),
#       .groups = "drop"
#     ) %>%
#     mutate(No_Vaciados = Visitados - Vaciados) %>%
#     group_by(Fecha) %>%
#     # garantiza que existan siempre los 8 municipios por fecha
#     complete(
#       Municipio = municipios,
#       fill = list(
#         Programado = 0,
#         Visitados = 0,
#         No_visitados = 0,
#         Vaciados = 0,
#         No_Vaciados = 0
#       )
#     ) %>%
#     ungroup() %>%
#     # evita negativos por inconsistencias
#     mutate(No_Vaciados = pmax(0, No_Vaciados)) %>%
#     arrange(Fecha, factor(Municipio, levels = municipios))
#   
#   planificados <- funcion_obtener_planificados()
#   
#   
#   planificados_final_porturno <- planificados %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Activos = coalesce(as.integer(Activos), 0L),
#       Inactivos = coalesce(as.integer(Inactivos), 0L)
#     ) %>%
#     group_by(Fecha, Municipio,Id_turno) %>%
#     summarise(
#       Activos = sum(Activos, na.rm = TRUE),
#       Inactivos = sum(Inactivos, na.rm = TRUE),
#       .groups = "drop"
#     ) %>%
#     mutate(Planificados = Activos + Inactivos) %>% 
#     arrange(Fecha, Municipio) %>% 
#     mutate(
#       # 1. Creamos la columna con los nombres correspondientes
#       Turno_planificado = case_when(
#         Id_turno == 1 ~ "Matutino",
#         Id_turno == 2 ~ "Vespertino",
#         Id_turno == 3 ~ "Nocturno",
#         TRUE ~ NA_character_  # Para manejar valores inesperados
#       ),
#       # 2. La convertimos en factor con el orden específico
#       Turno_planificado = factor(
#         Turno_planificado, 
#         levels = c("Matutino", "Vespertino", "Nocturno")
#       )
#     )
#   
#   # Tomo solo la columna Planificados desde res_por_fecha_mpio
#   planif_key <- planificados_final_porturno %>%
#     transmute(
#       Fecha = as.Date(Fecha),
#       Municipio = as.character(Municipio),
#       Activos = as.integer(Activos),
#       Turno_planificado = as.factor(Turno_planificado)
#     )
#   
#   df_resumen2_porturno <- df_resumen_conturno %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Municipio = as.character(Municipio)
#     ) %>%
#     # Unimos especificando qué columna de la izquierda coincide con la de la derecha
#     left_join(
#       planif_key, 
#       by = c("Fecha", "Municipio", "Turno_levantado" = "Turno_planificado")
#     ) %>%
#     relocate(Activos, .after = Municipio) %>% 
#     rename(Planificados = Activos)
#   
#   df_resumen2_porturno <- df_resumen2_porturno %>% 
#     mutate(Planificados = coalesce(Planificados, 0L)) %>% 
#     arrange(desc(Fecha),Municipio)
#   
#   
#   df_resumen2_porturno <- df_resumen2_porturno %>%
#     # 1. Eliminamos filas donde el turno sea NA para que complete() no las repita
#     filter(!is.na(Turno_levantado)) %>%
#     
#     # 2. Aseguramos que sea factor con niveles fijos
#     mutate(Turno_levantado = factor(Turno_levantado, 
#                                     levels = c("Matutino", "Vespertino", "Nocturno"))) %>%
#     
#     # 3. Completamos la estructura
#     complete(
#       nesting(Fecha, Municipio), 
#       Turno_levantado, 
#       fill = list(
#         Planificados = 0,
#         Programado = 0,
#         Visitados = 0,
#         No_visitados = 0,
#         Vaciados = 0,
#         No_Vaciados = 0
#       )
#     )
#   
#   
#   old <- Sys.getlocale("LC_TIME")
#   try(Sys.setlocale("LC_TIME","es_UY.UTF-8"), silent = TRUE)
#   
#   df_resumen2_porturno <- df_resumen2_porturno %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Dia   = format(Fecha, "%A")
#     ) %>%
#     relocate(Dia, .after = Fecha)
#   
#   df_llenado
#   
#   
#   
#   return(df_resumen2_porturno)
#   
# }

funcion_df_nuevoinformediario_porturnos <- function(df_llenado) {
  
  # 1. Preparación inicial y cálculo de columna "Visitado" (Común a todos)
  inc_col <- if ("Incidencias" %in% names(df_llenado)) "Incidencias" else "Incidencia"
  
  df_procesado_base <- df_llenado %>%
    mutate(
      Visitado = case_when(
        Levantado == "S" ~ "Visitado",
        is.na(Levantado) ~ "No visitado",
        Levantado == "N" & .data[[inc_col]] %in% motivos_con_visita ~ "Visitado",
        Levantado == "N" ~ "No visitado",
        TRUE ~ NA_character_
      ),
      Fecha = as.Date(Fecha),
      Municipio = toupper(trimws(Municipio))
    )
  
  # 2. Obtener Planificados (Común)
  planificados <- funcion_obtener_planificados() %>%
    mutate(
      Fecha = as.Date(Fecha),
      Activos = coalesce(as.integer(Activos), 0L),
      Turno_planificado = factor(
        case_when(Id_turno == 1 ~ "Matutino", Id_turno == 2 ~ "Vespertino", Id_turno == 3 ~ "Nocturno", TRUE ~ NA_character_),
        levels = c("Matutino", "Vespertino", "Nocturno")
      )
    ) %>%
    group_by(Fecha, Municipio, Turno_planificado) %>%
    summarise(Planificados = sum(Activos, na.rm = TRUE), .groups = "drop")
  
  # --- FUNCIÓN INTERNA PARA EVITAR REPETIR CÓDIGO ---
  procesar_filtro <- function(df_filtrado) {
    municipios <- c("A", "B", "C", "CH", "D", "E", "F", "G")
    
    resumen <- df_filtrado %>%
      group_by(Fecha, Municipio, Turno_levantado) %>%
      summarise(
        Programado   = n(),
        Visitados    = sum(Visitado == "Visitado",    na.rm = TRUE),
        No_visitados = sum(Visitado == "No visitado", na.rm = TRUE),
        Vaciados     = sum(Levantado == "S",          na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(No_Vaciados = pmax(0, Visitados - Vaciados)) %>%
      # Unir con planificados
      left_join(planificados, by = c("Fecha", "Municipio", "Turno_levantado" = "Turno_planificado")) %>%
      mutate(Planificados = coalesce(Planificados, 0)) %>%
      # Completar estructura de Municipios y Turnos
      filter(!is.na(Turno_levantado)) %>%
      mutate(Turno_levantado = factor(Turno_levantado, levels = c("Matutino", "Vespertino", "Nocturno"))) %>%
      complete(
        nesting(Fecha, Municipio), 
        Turno_levantado, 
        fill = list(Planificados = 0, Programado = 0, Visitados = 0, No_visitados = 0, Vaciados = 0, No_Vaciados = 0)
      ) %>%
      # Agregar Día de la semana
      mutate(Dia = format(Fecha, "%A")) %>%
      relocate(Dia, .after = Fecha) %>%
      relocate(Planificados, .after = Turno_levantado) %>%
      arrange(desc(Fecha), Municipio, Turno_levantado)
    
    return(resumen)
  }
  
  # --- APLICAR FILTROS Y GENERAR LISTA ---
  
  # Solo IM
  df_im <- df_procesado_base %>% filter(Oficina == "IM") %>% procesar_filtro()
  
  # Solo Fideicomiso
  df_fideicomiso <- df_procesado_base %>% filter(Oficina == "FIDEICOMISO") %>% procesar_filtro()
  
  # Todas las oficinas (Sin filtro de oficina)
  df_todas <- df_procesado_base %>% procesar_filtro()
  
  return(list(
    solo_im = df_im,
    solo_fideicomiso = df_fideicomiso,
    todas_oficinas = df_todas
  ))
}

#####

# funcion_contar_viajes_por_diayturno <- function(df_llenado){
#   
#   df_llenado_nuevo <- df_llenado %>% 
#     filter(Oficina == "IM") %>% 
#     filter(Fecha > "2026-01-01") %>% 
#     filter(Levantado == "S")
#   
#   df_gol_contenedores <- df_llenado_nuevo %>%
#     group_by(Fecha,Turno_levantado,Id_viaje_GOL) %>%
#     summarise(Contenedores = n(), .groups = "drop")
#   
#   df_gol_camiones <- df_llenado_nuevo %>% 
#     group_by(Fecha,Turno_levantado) %>% 
#     summarise(Camiones = n_distinct(Id_viaje_GOL))
#   
#   return(df_gol_camiones)
#   
# }


funcion_contar_viajes_por_diayturno <- function(df_llenado) {
  
  # 1. Filtros comunes para todos los reportes
  df_base <- df_llenado %>% 
    filter(Fecha > "2026-01-01") %>% 
    filter(Levantado == "S")
  
  # --- 2. Reporte Solo IM ---
  df_im <- df_base %>% 
    filter(Oficina == "IM") %>% 
    group_by(Fecha, Turno_levantado) %>% 
    summarise(Camiones = n_distinct(Id_viaje_GOL), .groups = "drop")
  
  # --- 3. Reporte Solo Fideicomiso ---
  # Asegúrate de que "FIDEICOMISO" sea el nombre exacto en tu columna Oficina
  df_fideicomiso <- df_base %>% 
    filter(Oficina == "Fideicomiso") %>% 
    group_by(Fecha, Turno_levantado) %>% 
    summarise(Camiones = n_distinct(Id_viaje_GOL), .groups = "drop")
  
  # --- 4. Reporte General (Todas las oficinas) ---
  df_todas <- df_base %>% 
    group_by(Fecha, Turno_levantado) %>% 
    summarise(Camiones = n_distinct(Id_viaje_GOL), .groups = "drop")
  
  # Retornar los tres en la lista
  return(list(
    solo_im = df_im,
    solo_fideicomiso = df_fideicomiso,
    todas_oficinas = df_todas
  ))
}

total_viajes <- funcion_contar_viajes_por_diayturno(gol_visitayprogramado_completo)

viajes_porcamion_soloim <- total_viajes$solo_im
viajes_porcamion_solofideicomiso <- total_viajes$solo_fideicomiso
viajes_porcamion_imyfideicomiso <- total_viajes$todas_oficinas

### ACA EL CRITERIO ES QUE SE TOMA 1er turno dia anterior, matutino y vespertino del día siguiente.
total_viajesporcamionsoloim_criterioadrian <- viajes_porcamion_soloim %>%
  mutate(
    # 1. Aseguramos que Fecha sea formato Date
    Fecha = as.Date(Fecha),
    
    # 2. Si el turno es Nocturno, sumamos 1 día
    Fecha = if_else(Turno_levantado == "Nocturno", Fecha + days(1), Fecha),
    
    # 3. Actualizamos la columna Dia basándonos en la nueva Fecha
    # label = TRUE devuelve el nombre (lunes, martes...), abbr = FALSE el nombre completo
    Dia = wday(Fecha, label = TRUE, abbr = FALSE)
  ) %>%
  # Opcional: convertir Dia a caracteres simples si no lo quieres como factor ordenado
  mutate(Dia = as.character(Dia))

ruta_destino <- file.path("scripts", "visitados", "total_viajesporcamionsoloim_criterioadrian.rds")
saveRDS(total_viajesporcamionsoloim_criterioadrian, ruta_destino)


### ACA EL CRITERIO ES QUE SE TOMA 1er turno dia anterior, matutino y vespertino del día siguiente.
total_viajesporcamionimyfideicomiso_criterioadrian <- viajes_porcamion_imyfideicomiso %>%
  mutate(
    # 1. Aseguramos que Fecha sea formato Date
    Fecha = as.Date(Fecha),
    
    # 2. Si el turno es Nocturno, sumamos 1 día
    Fecha = if_else(Turno_levantado == "Nocturno", Fecha + days(1), Fecha),
    
    # 3. Actualizamos la columna Dia basándonos en la nueva Fecha
    # label = TRUE devuelve el nombre (lunes, martes...), abbr = FALSE el nombre completo
    Dia = wday(Fecha, label = TRUE, abbr = FALSE)
  ) %>%
  # Opcional: convertir Dia a caracteres simples si no lo quieres como factor ordenado
  mutate(Dia = as.character(Dia))

ruta_destino <- file.path("scripts", "visitados", "viajespordiayturno_imyfideicomiso.rds_criterioadrian.rds")
saveRDS(total_viajesporcamionimyfideicomiso_criterioadrian, ruta_destino)

####

informediarionuevo_total <- funcion_df_nuevoinformediario_porturnos(gol_visitayprogramado_completo)
informediarionuevo_total_soloim <- informediarionuevo_total$solo_im
informediarionuevo_total_solofideicomiso <- informediarionuevo_total$solo_fideicomiso
informediarionuevo_total_imyfideicomiso <- informediarionuevo_total$todas_oficinas

# filtro a partir de enero 2026
informediarionuevo_total_soloim_2026 <- informediarionuevo_total_soloim %>% 
  filter(Fecha > "2026-01-01")
informediarionuevo_total_imyfideicomiso_2026 <- informediarionuevo_total_imyfideicomiso %>% 
  filter(Fecha > "2026-01-01")

informediarionuevo_total_soloim_criterioadrian <- informediarionuevo_total_soloim_2026 %>%
  mutate(
    # 1. Aseguramos que Fecha sea formato Date
    Fecha = as.Date(Fecha),
    
    # 2. Si el turno es Nocturno, sumamos 1 día
    Fecha = if_else(Turno_levantado == "Nocturno", Fecha + days(1), Fecha),
    
    # 3. Actualizamos la columna Dia basándonos en la nueva Fecha
    # label = TRUE devuelve el nombre (lunes, martes...), abbr = FALSE el nombre completo
    Dia = wday(Fecha, label = TRUE, abbr = FALSE)
  ) %>%
  # Opcional: convertir Dia a caracteres simples si no lo quieres como factor ordenado
  mutate(Dia = as.character(Dia))

 ruta_destino <- file.path("scripts", "visitados", "informediarionuevo_total_soloim_criterioadrian.rds")
 saveRDS(informediarionuevo_total_soloim_criterioadrian, ruta_destino)

informediarionuevo_total_imyfideicomiso_criterioadrian <- informediarionuevo_total_imyfideicomiso_2026 %>%
  mutate(
    # 1. Aseguramos que Fecha sea formato Date
    Fecha = as.Date(Fecha),
    
    # 2. Si el turno es Nocturno, sumamos 1 día
    Fecha = if_else(Turno_levantado == "Nocturno", Fecha + days(1), Fecha),
    
    # 3. Actualizamos la columna Dia basándonos en la nueva Fecha
    # label = TRUE devuelve el nombre (lunes, martes...), abbr = FALSE el nombre completo
    Dia = wday(Fecha, label = TRUE, abbr = FALSE)
  ) %>%
  # Opcional: convertir Dia a caracteres simples si no lo quieres como factor ordenado
  mutate(Dia = as.character(Dia))

ruta_destino <- file.path("scripts", "visitados", "informediarionuevo_total_imyfideicomiso_criterioadrian.rds")
saveRDS(informediarionuevo_total_imyfideicomiso_criterioadrian, ruta_destino)


# 2. Cargar la librería
library(writexl)

# 3. Exportar el data frame
# "df" es el nombre de tu objeto en R y "mi_reporte.xlsx" el nombre del archivo
# write.xlsx(prueba_adrian, file = "datos_vaciados_camiones.xlsx", sheetName = "vaciados")




# Creamos una lista con los data frames y los nombres de las hojas
hojas_a_guardar <- list(
  "vaciados_im" = informediarionuevo_total_soloim_criterioadrian,
  "vaciados_imyfideicomiso" = informediarionuevo_total_imyfideicomiso_criterioadrian,
  "resumen_circuitos_im" = total_viajesporcamionsoloim_criterioadrian,
  "resumen_im_y_fideicomiso" = total_viajesporcamionimyfideicomiso_criterioadrian
)


# ruta_destino <- file.path("scripts", "visitados", "viajespordiayturno_imyfideicomiso.rds_criterioadrian.rds")
# saveRDS(total_viajesporcamionimyfideicomiso_criterioadrian, ruta_destino)
# Esto crea un solo Excel con dos pestañas
ruta_destino <- file.path("scripts", "visitados", "datos_vaciados_camiones.xlsx")
write.xlsx(hojas_a_guardar, file = ruta_destino)




######

promedios_mensuales_concap <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
# 1. Contamos cuántas filas (incidencias) hay en cada día
count(Fecha, name = "total_del_dia") %>%
  # 2. Agrupamos esos totales por mes
  group_by(Mes = floor_date(Fecha, "month")) %>%
  # 3. Calculamos el promedio de esos totales diarios
  summarise(promedio_diario_mensual = mean(total_del_dia, na.rm = TRUE))

promedios_mensuales_concap_porturnos <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
  # PASO 1: Contamos cuántas filas hay en cada combinación de día y turno
  # Esto genera una columna 'n' con el total de ese día/turno
  count(Fecha, Turno_levantado) %>%
  
  # PASO 2: Ahora sí, agrupamos por Mes y Turno al mismo tiempo
  # floor_date convierte "2026-01-15" en "2026-01-01"
  group_by(Mes = floor_date(Fecha, "month"), Turno_levantado) %>%
  
  # PASO 3: Calculamos el promedio de esos conteos diarios
  summarise(
    promedio_diario_mensual = mean(n, na.rm = TRUE),
    total_filas_mes = sum(n), # Opcional: total de filas en todo el mes
    .groups = "drop"
  )

promedios_mensuales_sincap <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
  filter(Oficina == "IM") %>% 
  # 1. Contamos cuántas filas (incidencias) hay en cada día
  count(Fecha, name = "total_del_dia") %>%
  # 2. Agrupamos esos totales por mes
  group_by(Mes = floor_date(Fecha, "month")) %>%
  # 3. Calculamos el promedio de esos totales diarios
  summarise(promedio_diario_mensual = mean(total_del_dia, na.rm = TRUE))

promedios_mensuales_sincap_porturnos <- gol_visitayprogramado_completo %>%
  filter(Levantado == "S") %>%
  filter(Oficina == "IM") %>% 
  # PASO 1: Contamos cuántas filas hay en cada combinación de día y turno
  # Esto genera una columna 'n' con el total de ese día/turno
  count(Fecha, Turno_levantado) %>%
  
  # PASO 2: Ahora sí, agrupamos por Mes y Turno al mismo tiempo
  # floor_date convierte "2026-01-15" en "2026-01-01"
  group_by(Mes = floor_date(Fecha, "month"), Turno_levantado) %>%
  
  # PASO 3: Calculamos el promedio de esos conteos diarios
  summarise(
    promedio_diario_mensual = mean(n, na.rm = TRUE),
    total_filas_mes = sum(n), # Opcional: total de filas en todo el mes
    .groups = "drop"
  )


### Ahora agrupar por viaje por turno

ver <- gol_visitayprogramado_completo %>% 
  filter(Levantado == "S") %>% 
  filter(Oficina == "IM") %>% 
  group_by(Fecha,Turno_levantado,Id_viaje_GOL) %>% 
  summarise(total = n()) %>% 
  filter(Fecha > "2026-01-01")




ubicaciones <- historico_ubicaciones %>% 
  filter(Fecha == "2026-02-01")

dfr <- historico_DFR_ubicaciones %>% 
  filter(Fecha == "2026-02-01")








resumen_cambios_reales <- historico_DFR_ubicaciones %>%
  # Seleccionamos las columnas que definen un cambio real
  distinct(gid, Circuito, Posicion, Estado, Direccion_dfr, .keep_all = FALSE) %>%
  group_by(gid) %>%
  summarise(cambios_detectados = n() - 1)
