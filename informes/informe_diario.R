library(here)
library(dplyr)
library(lubridate)
library(readxl)

# Esto construye la ruta desde la raíz de tu proyecto automáticamente
ruta_RDS_datos <- here("db", "10393_ubicaciones", "historico_ubicaciones.rds")

if (file.exists(ruta_RDS_datos)) {
  historico_ubicaciones <- readRDS(ruta_RDS_datos)
}

# Esto construye la ruta desde la raíz de tu proyecto automáticamente
ruta_RDS_datos <- here("db", "GOL_reportes", "historico_llenadoGol.rds")

if (file.exists(ruta_RDS_datos)) {
  historico_llenado <- readRDS(ruta_RDS_datos)
}

#########

funcion_obtener_planificados <- function(){
  
  planificacion <- read_excel(
    "informes/planificados/planificacion.xlsx",
    #"planificacion.xlsx",
    sheet = "historico",
    range = cell_cols("A:L"))
  
  total_contenedores_im <- historico_ubicaciones |>
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
            Grupo = GRUPO) # %>% 
    # filter(Fecha >= Fecha_inicio_informe)
  
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

# # df_llenado <- historico_llenado
# funcion_df_nuevoinformediario <- function(df_llenado){
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
#     )
#   
#   # universo fijo de municipios
#   municipios <- c("A","B","C","CH","D","E","F","G")
#   
#   df_resumen <- gol_visitayprogramado_completo_nuevo %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Municipio = toupper(trimws(Municipio))
#     ) %>%
#     group_by(Fecha, Municipio) %>%
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
#   planificados_final <- planificados %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Activos = coalesce(as.integer(Activos), 0L),
#       Inactivos = coalesce(as.integer(Inactivos), 0L)
#     ) %>%
#     group_by(Fecha, Municipio) %>%
#     summarise(
#       Activos = sum(Activos, na.rm = TRUE),
#       Inactivos = sum(Inactivos, na.rm = TRUE),
#       .groups = "drop"
#     ) %>%
#     mutate(Planificados = Activos + Inactivos) %>% 
#     arrange(Fecha, Municipio)
#   
#   # Tomo solo la columna Planificados desde res_por_fecha_mpio
#   planif_key <- planificados_final %>%
#     transmute(
#       Fecha = as.Date(Fecha),
#       Municipio = as.character(Municipio),
#       Activos = as.integer(Activos)
#     )
#   
#   df_resumen2 <- df_resumen %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Municipio = as.character(Municipio)
#     ) %>%
#     left_join(planif_key, by = c("Fecha","Municipio")) %>%
#     relocate(Activos, .after = Municipio) %>% 
#     rename(Planificados = Activos)
#   
#   df_resumen2 <- df_resumen2 %>% 
#     mutate(Planificados = coalesce(Planificados, 0L)) %>% 
#     arrange(desc(Fecha),Municipio)
#   
#   old <- Sys.getlocale("LC_TIME")
#   try(Sys.setlocale("LC_TIME","es_UY.UTF-8"), silent = TRUE)
#   
#   df_resumen2 <- df_resumen2 %>%
#     mutate(
#       Fecha = as.Date(Fecha),
#       Dia   = format(Fecha, "%A")
#     ) %>%
#     relocate(Dia, .after = Fecha)
#   
#   try(Sys.setlocale("LC_TIME", old), silent = TRUE)
#   
#   ## Agrupados
#   
#   df_resumen_agrupado_pordia <- df_resumen2 %>%
#     group_by(Fecha) %>%
#     summarise(
#       Dia           = first(Dia),
#       Planificados  = sum(as.numeric(Planificados),  na.rm = TRUE),
#       Programado    = sum(as.numeric(Programado),    na.rm = TRUE),
#       Visitados     = sum(as.numeric(Visitados),     na.rm = TRUE),
#       No_visitados  = sum(as.numeric(No_visitados),  na.rm = TRUE),
#       Vaciados      = sum(as.numeric(Vaciados),      na.rm = TRUE),
#       No_Vaciados   = sum(as.numeric(No_Vaciados),   na.rm = TRUE),
#       .groups = "drop"
#     ) %>%
#     arrange(Fecha)
#   
#   
#   return(list(
#     resumen_por_dia_y_municipio = df_resumen2,
#     resumen_por_dia = df_resumen_agrupado_pordia
#   ))
#   
#   
# }
# 
# 
# informe_final <- funcion_df_nuevoinformediario(historico_llenado)
# resumen_dia_y_municipio <- informe_final$resumen_por_dia_y_municipio
# resumen_dia <- informe_final$resumen_por_dia




# informe <- historico_ubicaciones %>% 
#   filter(Fecha == "2026-02-10")
# 
# 
# 
# # 1. Preparar los datos de llenado para el cruce
# llenado_reciente <- historico_llenado %>%
#   # Filtramos solo los que fueron levantados
#   filter(Levantado == "S") %>%
#   # Agrupamos por GID para encontrar el último evento de cada contenedor
#   group_by(gid) %>%
#   # Nos quedamos con la fila que tenga la Fecha_hora_pasaje más reciente
#   # (Usamos Fecha_hora_pasaje por ser más precisa que solo Fecha)
#   slice_max(Fecha_hora_pasaje, n = 1, with_ties = FALSE) %>%
#   ungroup() %>%
#   # Seleccionamos solo el ID y las columnas que queremos añadir
#   select(gid, Turno_levantado, Fecha_hora_pasaje, Id_viaje_GOL)
# 
# # 2. Anexar la información al dataframe de ubicaciones
# historico_ubicaciones_final <- informe %>%
#   left_join(llenado_reciente, by = "gid")
# 
# # Definimos la zona horaria de Uruguay
# tz_uy <- "America/Montevideo"
# 
# historico_ubicaciones_final <- historico_ubicaciones_final %>%
#   mutate(
#     # Forzamos a que el pasaje sea interpretado en hora de Uruguay
#     Fecha_hora_pasaje = force_tz(Fecha_hora_pasaje, tzone = tz_uy),
#     
#     # Creamos el corte asegurando que también sea hora de Uruguay
#     Fecha_Corte = as.POSIXct(paste(Fecha+1, "06:00:00"), tz = tz_uy),
#     
#     # Calculamos la diferencia
#     Diferencia_horas = as.numeric(difftime(Fecha_Corte, Fecha_hora_pasaje, units = "hours")),
#     Diferencia_horas = round(Diferencia_horas, 1)
#   )

# fecha_objetivo <- "2026-02-17"
generar_reporte_dia <- function(fecha_objetivo, historico_ubicaciones, historico_llenado) {
  
  # 1. Filtrar el informe por la fecha de entrada
  # (Aseguramos que fecha_objetivo sea Date para que Fecha+1 funcione)
  fecha_objetivo <- as.Date(fecha_objetivo)
  
  informe <- historico_ubicaciones %>% 
    filter(Fecha == fecha_objetivo)
  
  historico_llenado_filtrado <- historico_llenado %>% 
    filter(Fecha <= fecha_objetivo)
  
  # 2. Preparar los datos de llenado (el levante más reciente por GID)
  llenado_reciente <- historico_llenado_filtrado %>%
    filter(Levantado == "S") %>%
    group_by(gid) %>%
    slice_max(Fecha_hora_pasaje, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    # Incluimos Oficina para poder filtrar después
    select(gid, Turno_levantado, Fecha_hora_pasaje, Id_viaje_GOL, Oficina)
  
  # 3. Join y cálculos de tiempo
  tz_uy <- "America/Montevideo"
  
  resultado_global <- informe %>%
    left_join(llenado_reciente %>% select(-Oficina), by = "gid") %>%
    mutate(
      # Forzamos zona horaria
      Fecha_hora_pasaje = force_tz(Fecha_hora_pasaje, tzone = tz_uy),
      
      # Punto de corte: 06:00 AM del día siguiente al informe
      Fecha_Corte = as.POSIXct(paste(Fecha + 1, "06:00:00"), format = "%Y-%m-%d %H:%M:%S", tz = "America/Montevideo"),
      
      # Cálculo de horas transcurridas
      Diferencia_horas = as.numeric(difftime(Fecha_Corte, Fecha_hora_pasaje, units = "hours")),
      Diferencia_horas = round(Diferencia_horas, 1)
    )
  
  # 4. Generar las listas filtradas
  # Usamos any_of por si acaso el campo Oficina viniera de la tabla de ubicaciones en lugar de llenado
  solo_im <- resultado_global %>% filter(Oficina == "IM")
  solo_fideicomiso <- resultado_global %>% filter(Oficina == "Fideicomiso")
  
  # Retorno de las 3 listas (dataframes)
  return(list(
    global = resultado_global,
    im = solo_im,
    fideicomiso = solo_fideicomiso
  ))
}


# df_llenado <- historico_llenado
funcion_df_nuevoinformediario <- function(df_llenado){
  
  print("------------------------------------------------------")
  print(paste("INICIANDO PROCESO: Informe Diario -", Sys.time()))
  
  # --- 1. PREPROCESAMIENTO COMÚN ---
  print("1. Procesando reglas de negocio (Visitado/Incidencias)...")
  
  # Usa "Incidencias" si existe, si no "Incidencia"
  inc_col <- if ("Incidencias" %in% names(df_llenado)) "Incidencias" else "Incidencia"
  
  # Calculamos la columna 'Visitado'
  gol_visitayprogramado_completo_nuevo <- df_llenado %>%
    mutate(
      Visitado = case_when(
        Levantado == "S" ~ "Visitado",
        is.na(Levantado) ~ "No visitado",
        Levantado == "N" & .data[[inc_col]] %in% motivos_con_visita ~ "Visitado",
        Levantado == "N" ~ "No visitado",
        TRUE ~ NA_character_
      )
    )
  
  municipios <- c("A","B","C","CH","D","E","F","G")
  
  # --- 2. PREPARAR PLANIFICADOS ---
  print("2. Obteniendo y estructurando datos de 'Planificados'...")
  
  planificados <- funcion_obtener_planificados()
  
  planificados_final_pordia <- planificados %>%
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
  
  planif_pordia_key <- planificados_final_pordia %>%
    transmute(
      Fecha = as.Date(Fecha),
      Municipio = as.character(Municipio),
      Activos = as.integer(Activos)) 
  
  
  ### por turno
  
  planificados_final_pordiayturno <- planificados %>%
    mutate(
      Fecha = as.Date(Fecha),
      Activos = coalesce(as.integer(Activos), 0L),
      Inactivos = coalesce(as.integer(Inactivos), 0L)
    ) %>%
    group_by(Fecha, Municipio, Id_turno) %>%
    summarise(
      Activos = sum(Activos, na.rm = TRUE),
      Inactivos = sum(Inactivos, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(Planificados = Activos + Inactivos) %>% 
    arrange(Fecha, Municipio)
  
  planif_pordiayturno_key <- planificados_final_pordiayturno %>%
    transmute(
      Fecha = as.Date(Fecha),
      Municipio = as.character(Municipio),
      Id_turno = as.numeric(Id_turno),
      Activos = as.integer(Activos)
    ) %>%
    # Paso clave: Completar la grilla por cada Fecha
    group_by(Fecha) %>%
    complete(
      Municipio = c("A", "B", "C", "CH", "D", "E", "F", "G"),
      Id_turno = c(1, 2, 3),
      fill = list(Activos = 0L) # Pone 0 si no existe el dato
    ) %>%
    ungroup() %>%
    # Ahora creamos las etiquetas de texto sobre la grilla completa
    mutate(
      Turno_Planificado = case_when(
        Id_turno == 1 ~ "Matutino",
        Id_turno == 2 ~ "Vespertino",
        Id_turno == 3 ~ "Nocturno",
        TRUE ~ "Otro"
      )
    )
  
  # --- 3. FUNCIÓN INTERNA CON PRINTS ---
  
  # Agregamos argumento 'nombre_escenario' para el print
  # data_input <- df_im %>% 
      #filter(Oficina == "IM")
  generar_resumenes <- function(data_input, nombre_escenario, usar_planificados = TRUE) {
    
    print(paste("   -> Generando resumen para:", nombre_escenario))
    
    # A) Agrupación base
    df_resumen <- data_input %>%
      mutate(
        Fecha = as.Date(Fecha),
        Municipio = toupper(trimws(Municipio))
      ) %>%
      group_by(Fecha, Municipio, Turno_levantado) %>%
      summarise(
        Programado   = n(),
        Visitados    = sum(Visitado == "Visitado",    na.rm = TRUE),
        No_visitados = sum(Visitado == "No visitado", na.rm = TRUE),
        Vaciados     = sum(Levantado == "S",          na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(No_Vaciados = Visitados - Vaciados) %>%
      group_by(Fecha) %>%
      complete(
        Municipio = municipios,
        fill = list(
          Programado = 0, Visitados = 0, No_visitados = 0, 
          Vaciados = 0, No_Vaciados = 0
        )
      ) %>%
      ungroup() %>%
      mutate(No_Vaciados = pmax(0, No_Vaciados)) %>%
      arrange(Fecha, factor(Municipio, levels = municipios))
    
    # B) Lógica Condicional Planificados
    if (usar_planificados) {
      df_resumen2 <- df_resumen %>%
        mutate(Fecha = as.Date(Fecha), Municipio = as.character(Municipio)) %>%
        left_join(planif_pordiayturno_key, by = c("Fecha","Municipio","Turno_levantado" = "Turno_Planificado")) %>%
        relocate(Activos, .after = Municipio) %>% 
        rename(Planificados = Activos) %>% 
        mutate(Planificados = coalesce(Planificados, 0L)) %>% 
        arrange(desc(Fecha), Municipio)
    } else {
      df_resumen2 <- df_resumen %>%
        arrange(desc(Fecha), Municipio)
    }
    
    # C) Formato de fechas
    old <- Sys.getlocale("LC_TIME")
    try(Sys.setlocale("LC_TIME","es_UY.UTF-8"), silent = TRUE)
    
    df_resumen2 <- df_resumen2 %>%
      mutate(
        Fecha = as.Date(Fecha),
        Dia   = format(Fecha, "%A")
      ) %>%
      relocate(Dia, .after = Fecha)
    
    try(Sys.setlocale("LC_TIME", old), silent = TRUE)
    
    # D) Agrupado por día
    if (usar_planificados) {
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
        arrange(desc(Fecha))
    } else {
      df_resumen_agrupado_pordia <- df_resumen2 %>%
        group_by(Fecha) %>%
        summarise(
          Dia           = first(Dia),
          Programado    = sum(as.numeric(Programado),    na.rm = TRUE),
          Visitados     = sum(as.numeric(Visitados),     na.rm = TRUE),
          No_visitados  = sum(as.numeric(No_visitados),  na.rm = TRUE),
          Vaciados      = sum(as.numeric(Vaciados),      na.rm = TRUE),
          No_Vaciados   = sum(as.numeric(No_Vaciados),   na.rm = TRUE),
          .groups = "drop"
        ) %>%
        arrange(desc(Fecha))
    }
    

    # D) Agrupado por dia y turno
    if (usar_planificados) {
      df_resumen_agrupado_pordia_ymun <- df_resumen2 %>%
        group_by(Fecha,Municipio) %>%
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
        arrange(desc(Fecha))
    } else {
      df_resumen_agrupado_pordia_ymun <- df_resumen2 %>%
        group_by(Fecha,Municipio) %>%
        summarise(
          Dia           = first(Dia),
          Programado    = sum(as.numeric(Programado),    na.rm = TRUE),
          Visitados     = sum(as.numeric(Visitados),     na.rm = TRUE),
          No_visitados  = sum(as.numeric(No_visitados),  na.rm = TRUE),
          Vaciados      = sum(as.numeric(Vaciados),      na.rm = TRUE),
          No_Vaciados   = sum(as.numeric(No_Vaciados),   na.rm = TRUE),
          .groups = "drop"
        ) %>%
        arrange(desc(Fecha))
    }
    
    ###3 Aca si no hay recolección y no esta planificado no se muestra
    # D) Agrupado por dia, turnos y municipio
    df_resumen_agrupado_pordia_ymunicipio_turno <- df_resumen2 %>% 
      rename(Turno = Turno_levantado) %>% 
      select(-any_of("Id_turno")) %>% 
      relocate(Turno, .before = Municipio) 
    
    ### Aca sí se muestra si es 0 0 0 0 0, como inf diario
    # Definimos los vectores de referencia
    municipios <- c("A", "B", "C", "CH", "D", "E", "F", "G")
    turnos_ref <- c("Matutino", "Vespertino", "Nocturno")
    
    df_resumen_agrupado_pordia_ymunicipio_turno_completoconceros <- df_resumen2 %>% 
      rename(Turno = Turno_levantado) %>% 
      select(-any_of("Id_turno")) %>% 
      # Forzamos la completitud de la grilla
      group_by(Fecha) %>% 
      complete(
        Municipio = municipios, 
        Turno = turnos_ref,
        fill = list(
          Planificados = 0,
          Programado = 0,
          Visitados = 0,
          No_visitados = 0,
          Vaciados = 0,
          No_Vaciados = 0
        )
      ) %>% 
      ungroup() %>% 
      # Recuperamos el día de la semana si se perdió en el complete
      mutate(Dia = format(Fecha, "%A")) %>% 
      relocate(Turno, .before = Municipio) %>%   
      arrange(desc(Fecha), factor(Municipio, levels = municipios), Turno)
    
    
    return(list(
      resumen_pordia = df_resumen_agrupado_pordia,
      resumen_pordiaymunicipio = df_resumen_agrupado_pordia_ymun,
      resumen_pordia_municipio_turno = df_resumen_agrupado_pordia_ymunicipio_turno,
      resumen_pordia_municipio_turno_completoconceros = df_resumen_agrupado_pordia_ymunicipio_turno_completoconceros
    ))
  }
  
  # --- 4. EJECUCIÓN DE LOS 3 ESCENARIOS ---
  
  print("3. Calculando escenarios...")
  
  # # A) General
  # res_general <- generar_resumenes(
  #   data_input = gol_visitayprogramado_completo_nuevo, 
  #   nombre_escenario = "GENERAL (Completo)", 
  #   usar_planificados = TRUE
  # )
  
  # B) Solo IM
  df_im <- gol_visitayprogramado_completo_nuevo %>% 
    filter(trimws(Oficina) == "IM")
  
  res_im <- generar_resumenes(
    data_input = df_im, 
    nombre_escenario = "IM (Oficina = IM)", 
    usar_planificados = TRUE
  )
  
  # C) Solo Fideicomiso
  df_fid <- gol_visitayprogramado_completo_nuevo %>% 
    filter(trimws(Oficina) == "Fideicomiso")
  
  res_fid <- generar_resumenes(
    data_input = df_fid, 
    nombre_escenario = "FIDEICOMISO (Oficina = Fid., Sin Planif.)", 
    usar_planificados = FALSE
  )
  
  # Limpiar df generados en el escenario para eliminar Munic y Turnos rellenados erróneamente con complete()
  res_fid$resumen_pordia <- res_fid$resumen_pordia # Este es un total por dia, normalmente no tiene Munic ni Turno.
  
  if ("Municipio" %in% names(res_fid$resumen_pordiaymunicipio)) {
     res_fid$resumen_pordiaymunicipio <- res_fid$resumen_pordiaymunicipio %>% 
       filter(toupper(trimws(Municipio)) == "B")
  }
  
  if ("Municipio" %in% names(res_fid$resumen_pordia_municipio_turno_completoconceros)) {
     res_fid$resumen_pordia_municipio_turno_completoconceros <- res_fid$resumen_pordia_municipio_turno_completoconceros %>% 
       filter(
          toupper(trimws(Municipio)) == "B",
          trimws(Turno) %in% c("Matutino", "Nocturno")
       )
  }
  
  
  
  # --- 5. GUARDADO DE DATOS ---
  print("5. Guardando archivos RDS...")
  
  # 1. Definimos la ruta relativa hacia la carpeta de destino
  ruta_carpeta <- "vistas/informediario/data"
  
  # 2. Creamos la carpeta si no existe (recursive = TRUE es clave)
  if (!dir.exists(ruta_carpeta)) {
    dir.create(ruta_carpeta, recursive = TRUE)
  }
  
  # 3. Guardamos usando 'file.path' para que la ruta sea válida
  # GENERAL
  # saveRDS(res_general$res_mpio, file.path(ruta_carpeta, "tabla_IMyFID_porturnos.rds"))
  # saveRDS(res_general$res_dia,  file.path(ruta_carpeta, "tabla_IMyFID_pordias.rds"))
  
  # IM
  
  saveRDS(res_im$resumen_pordia,      file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia.rds"))
  saveRDS(res_im$resumen_pordiaymunicipio,       file.path(ruta_carpeta, "tabla_soloIM_resumen_pordiaymunicipio.rds"))
  saveRDS(res_im$resumen_pordia_municipio_turno_completoconceros,       file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds"))
  
  # FIDEICOMISO
  
  saveRDS(res_fid$resumen_pordia,      file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia.rds"))
  saveRDS(res_fid$resumen_pordiaymunicipio,       file.path(ruta_carpeta, "tabla_soloFID_resumen_pordiaymunicipio.rds"))
  saveRDS(res_fid$resumen_pordia_municipio_turno_completoconceros,       file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds"))
  
  print("Archivos guardados en la carpeta /data")
  
  
  print("6. Consolidando lista final de retorno.")
  print(paste("FIN DEL PROCESO -", Sys.time()))
  print("------------------------------------------------------")
  
  return(list(
    # resumen_por_dia_y_municipio_general = res_general$res_mpio,
    # resumen_por_dia_general             = res_general$res_dia,
    
    resumen_pordia_IM = res_im$resumen_pordia,
    resumen_pordiaymunicipio_IM = res_im$resumen_pordiaymunicipio,
    resumen_pordia_municipio_turno_completoconceros_IM = res_im$resumen_pordia_municipio_turno_completoconceros,
    
    resumen_pordia_FID = res_fid$resumen_pordia,
    resumen_pordiaymunicipio_FID = res_fid$resumen_pordiaymunicipio,
    resumen_pordia_municipio_turno_completoconceros_FID = res_fid$resumen_pordia_municipio_turno_completoconceros
    
    # resumen_por_dia_y_municipio_fid     = res_fid$res_mpio,
    # resumen_por_dia_fid                 = res_fid$res_dia
  ))
}

ver <- funcion_df_nuevoinformediario(historico_llenado)

ver$resumen_pordia_IM
ver$resumen_pordiaymunicipio_IM
#tabla_im <- ver$resumen_por_dia_y_municipio_im

