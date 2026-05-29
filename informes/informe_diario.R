  library(here)
  library(dplyr)
  library(lubridate)
  library(readxl)
  library(tidyr)
  
  
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
    
    # 1. Cargar el registro de versiones y definir la fecha base de la plantilla
    ruta_versiones <- here("db", "planificados", "versiones_planificacion.rds")
    
    if (!file.exists(ruta_versiones)) {
      stop("No se encontró el archivo de versiones en db/planificados/versiones_planificacion.rds. Ejecuta la migración primero.")
    }
    
    versiones <- readRDS(ruta_versiones)
    base_date <- as.Date("2024-10-28")
    
    # 2. Obtener las fechas reales a partir del histórico de ubicaciones
    rango_fechas <- range(as.Date(historico_ubicaciones$Fecha), na.rm = TRUE)
    fecha_inicio <- rango_fechas[1]
    fecha_fin    <- rango_fechas[2]
    
    df_fechas <- data.frame(
      Fecha_Real = seq(fecha_inicio, fecha_fin, by = "days")
    )
    
    # 3. Asignar qué archivo RDS de plantilla le corresponde a cada fecha real
    df_fechas_versionadas <- df_fechas %>%
      rowwise() %>%
      mutate(
        Fichero_RDS = versiones$Fichero_RDS[Fecha_Real >= versiones$Fecha_Inicio & Fecha_Real <= versiones$Fecha_Fin][1]
      ) %>%
      ungroup()
    
    # 4. Cargar y cruzar vectorialmente cada plantilla RDS (cargando cada una una sola vez)
    lista_resultados <- lapply(unique(df_fechas_versionadas$Fichero_RDS), function(rds_path) {
      if (is.na(rds_path)) return(NULL)
      
      # Filtrar fechas para esta plantilla
      fechas_sub <- df_fechas_versionadas %>%
        filter(Fichero_RDS == rds_path)
      
      # Calcular la fecha en la plantilla de 42 días (Módulo 42)
      fechas_sub <- fechas_sub %>%
        mutate(
          diff_days = as.numeric(Fecha_Real - base_date),
          offset_template = diff_days %% 42,
          Fecha_Plantilla = base_date + offset_template
        )
      
      # Cargar la plantilla RDS correspondiente
      template <- readRDS(rds_path)
      
      # Cruzar vectorialmente
      res <- fechas_sub %>%
        left_join(template, by = c("Fecha_Plantilla" = "DIA"), relationship = "many-to-many") %>%
        mutate(
          Fecha = Fecha_Real,
          Dia   = format(Fecha_Real, "%A"),
          Id_turno = ID_TURNO,
          Municipio = MUNICIPIO,
          Circuito = CIRCUITO,
          Grupo = GRUPO
        ) %>%
        select(Fecha, Dia, Frecuencia, Periodo, Id_turno, Municipio, Circuito, Grupo)
      
      return(res)
    })
    
    planificacion_generada <- bind_rows(lista_resultados)
    
    # 5. Agrupar contenedores reales de la base de ubicaciones
    total_contenedores_im <- historico_ubicaciones %>%
      mutate(Estado = na_if(trimws(Estado), "")) %>%
      group_by(Fecha = as.Date(Fecha), Circuito = as.character(Circuito)) %>%
      summarise(
        Activos   = sum(is.na(Estado)),
        Inactivos = sum(!is.na(Estado)),
        .groups = "drop"
      )
    
    # 6. Cruzar la planificación calculada con los contenedores reales del histórico de ubicaciones
    planificacion_arreglada <- planificacion_generada %>%
      mutate(
        Fecha    = as.Date(Fecha),
        Circuito = as.character(Circuito)
      ) %>%
      left_join(total_contenedores_im, by = c("Fecha", "Circuito")) %>%
      mutate(
        Activos   = coalesce(Activos,   0L),
        Inactivos = coalesce(Inactivos, 0L)
      )
    
    # 7. Filtrar hasta la fecha máxima de las ubicaciones reales (según lógica original)
    fecha_maxima_contenedoresim <- max(total_contenedores_im$Fecha)
    planificacion_arreglada <- planificacion_arreglada %>%
      filter(Fecha <= fecha_maxima_contenedoresim)
    
    return(planificacion_arreglada)
  }
  
  planif <- funcion_obtener_planificados()
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


  funcion_df_nuevoinformediario <- function(df_llenado){
    
    # Directorio de destino para los archivos RDS calculados
    ruta_carpeta <- "vistas/informediario/data"
    
    # Archivo de control para validar si ya existen resúmenes guardados anteriormente
    archivo_control <- file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia.rds")
    
    # --- 0. ANÁLISIS DE INCREMENTALIDAD ---
    # Si los resúmenes calculados ya existen en disco, podemos validar si es necesario recalculación
    if (file.exists(archivo_control)) {
      
      # Cargar resúmenes anteriores del día para evaluar fechas
      resumen_pordia_im_guardado <- readRDS(archivo_control)
      
      # Obtener la última fecha procesada y la última fecha presente en el nuevo set de datos
      max_fecha_guardada <- max(as.Date(resumen_pordia_im_guardado$Fecha), na.rm = TRUE)
      max_fecha_nueva <- max(as.Date(df_llenado$Fecha), na.rm = TRUE)
      
      # CASO A: Los datos ya están actualizados hasta la última fecha disponible.
      # Evitamos todo cálculo y cargamos los RDS guardados en disco de forma instantánea.
      if (max_fecha_nueva <= max_fecha_guardada) {
        print("------------------------------------------------------")
        print(paste("INFO: Los resúmenes ya se encuentran actualizados al día:", max_fecha_guardada))
        print("Cargando base histórica acumulada directamente desde disco...")
        print("------------------------------------------------------")
        
        return(list(
          resumen_pordia_IM = readRDS(file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia.rds")),
          resumen_pordiaymunicipio_IM = readRDS(file.path(ruta_carpeta, "tabla_soloIM_resumen_pordiaymunicipio.rds")),
          resumen_pordia_municipio_turno_completoconceros_IM = readRDS(file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds")),
          
          resumen_pordia_FID = readRDS(file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia.rds")),
          resumen_pordiaymunicipio_FID = readRDS(file.path(ruta_carpeta, "tabla_soloFID_resumen_pordiaymunicipio.rds")),
          resumen_pordia_municipio_turno_completoconceros_FID = readRDS(file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds"))
        ))
      }
      
      # CASO B: Carga incremental. Identificamos los días que faltan y procesamos únicamente esos días.
      fechas_nuevas <- seq(max_fecha_guardada + 1, max_fecha_nueva, by = "days")
      
      print("------------------------------------------------------")
      print(paste("INICIANDO PROCESO INCREMENTAL: Informe Diario -", Sys.time()))
      print(paste("Actualizando únicamente los días nuevos faltantes:", paste(fechas_nuevas, collapse = ", ")))
      
      # Filtrar el set de datos inicial para procesar únicamente los días nuevos
      df_llenado_filtrado <- df_llenado %>% 
        filter(as.Date(Fecha) %in% fechas_nuevas)
      
    } else {
      # CASO C: Recalculación completa por primera vez (o porque se borraron los archivos)
      print("------------------------------------------------------")
      print(paste("INICIANDO PROCESO COMPLETO: Informe Diario -", Sys.time()))
      print("No se encontraron resúmenes anteriores en vistas/informediario/data. Procesando el histórico completo...")
      
      df_llenado_filtrado <- df_llenado
      fechas_nuevas <- NULL
    }
    
    # --- 1. PREPROCESAMIENTO COMÚN (Solo para los días a calcular) ---
    print("1. Procesando reglas de negocio (Visitado/Incidencias)...")
    
    # Detectar el nombre de la columna de incidencias
    inc_col <- if ("Incidencias" %in% names(df_llenado_filtrado)) "Incidencias" else "Incidencia"
    
    # Clasificación de registros entre Visitado y No visitado según las incidencias y levantes
    gol_visitayprogramado_completo_nuevo <- df_llenado_filtrado %>%
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
    
    # Obtener el mapeo general planificado
    planificados <- funcion_obtener_planificados()
    
    # Si estamos en flujo incremental, filtramos las plantillas planificadas a los días nuevos únicamente
    if (!is.null(fechas_nuevas)) {
      planificados <- planificados %>% 
        filter(as.Date(Fecha) %in% fechas_nuevas)
    }
    
    # Agrupar planificados diarios por municipio
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
    
    # Agrupar planificados diarios por municipio y turno
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
      # Paso clave: Completar la grilla por cada Fecha con ceros si no hay datos
      group_by(Fecha) %>%
      complete(
        Municipio = c("A", "B", "C", "CH", "D", "E", "F", "G"),
        Id_turno = c(1, 2, 3),
        fill = list(Activos = 0L) # Pone 0 si no existe el dato
      ) %>%
      ungroup() %>%
      # Generar etiquetas textuales para cruzar con los levantes reales
      mutate(
        Turno_Planificado = case_when(
          Id_turno == 1 ~ "Matutino",
          Id_turno == 2 ~ "Vespertino",
          Id_turno == 3 ~ "Nocturno",
          TRUE ~ "Otro"
        )
      )
    
    # --- 3. FUNCIÓN AUXILIAR DE ESCENARIOS ---
    
    # Agregamos argumento 'nombre_escenario' para el print
    generar_resumenes <- function(data_input, nombre_escenario, usar_planificados = TRUE) {
      
      print(paste("   -> Generando resumen para:", nombre_escenario))
      
      # A) Agrupación base por Fecha, Municipio y Turno Levantado
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
      
      # B) Cruzamiento con los datos de Planificación
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
      
      # C) Formato regional de fechas
      old <- Sys.getlocale("LC_TIME")
      try(Sys.setlocale("LC_TIME","es_UY.UTF-8"), silent = TRUE)
      
      df_resumen2 <- df_resumen2 %>%
        mutate(
          Fecha = as.Date(Fecha),
          Dia   = format(Fecha, "%A")
        ) %>%
        relocate(Dia, .after = Fecha)
      
      try(Sys.setlocale("LC_TIME", old), silent = TRUE)
      
      # D) Resumen Agrupado por Día
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
      
  
      # E) Resumen Agrupado por Día y Municipio
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
      
      # F) Resumen Agrupado por Día, Turnos y Municipio
      df_resumen_agrupado_pordia_ymunicipio_turno <- df_resumen2 %>% 
        rename(Turno = Turno_levantado) %>% 
        select(-any_of("Id_turno")) %>% 
        relocate(Turno, .before = Municipio) 
      
      # G) Resumen por Día, Municipio y Turno (con grilla completa rellenada con ceros)
      turnos_ref <- c("Matutino", "Vespertino", "Nocturno")
      df_resumen_agrupado_pordia_ymunicipio_turno_completoconceros <- df_resumen2 %>% 
        rename(Turno = Turno_levantado) %>% 
        select(-any_of("Id_turno")) %>% 
        group_by(Fecha) %>% 
        complete(
          Municipio = municipios, 
          Turno = turnos_ref,
          fill = list(
            Planificados = 0, Programado = 0, Visitados = 0, 
            No_visitados = 0, Vaciados = 0, No_Vaciados = 0
          )
        ) %>% 
        ungroup() %>% 
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
    
    # --- 4. EJECUCIÓN DE LOS ESCENARIOS ---
    print("3. Calculando escenarios...")
    
    # Escenario IM
    df_im <- gol_visitayprogramado_completo_nuevo %>% 
      filter(trimws(Oficina) == "IM")
    
    res_im <- generar_resumenes(
      data_input = df_im, 
      nombre_escenario = "IM (Oficina = IM)", 
      usar_planificados = TRUE
    )
    
    # Escenario Fideicomiso
    df_fid <- gol_visitayprogramado_completo_nuevo %>% 
      filter(trimws(Oficina) == "Fideicomiso")
    
    res_fid <- generar_resumenes(
      data_input = df_fid, 
      nombre_escenario = "FIDEICOMISO (Oficina = Fid., Sin Planif.)", 
      usar_planificados = FALSE
    )
    
    # Limpiar df generados en el escenario para Fideicomiso
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
    
    
    # --- 5. GUARDADO O UNIÓN DE RESÚMENES EN RDS ---
    if (!is.null(fechas_nuevas)) {
      print("4. Combinando nuevos datos con históricos de forma incremental...")
      
      # Función auxiliar para unir resúmenes cargados con las filas nuevas
      combinar_resumen <- function(nombre_archivo, nuevas_filas, ordenar_por = "Fecha") {
        ruta_archivo <- file.path(ruta_carpeta, nombre_archivo)
        df_anterior <- readRDS(ruta_archivo)
        
        # Filtrar duplicados accidentales y acoplar filas calculadas
        df_combinado <- df_anterior %>%
          filter(!as.Date(Fecha) %in% fechas_nuevas) %>%
          bind_rows(nuevas_filas)
        
        # Re-ordenar el conjunto consolidado
        if (ordenar_por == "Fecha") {
          df_combinado <- df_combinado %>% arrange(desc(Fecha))
        } else if (ordenar_por == "Fecha_Municipio") {
          df_combinado <- df_combinado %>% arrange(desc(Fecha), Municipio)
        } else if (ordenar_por == "Fecha_Municipio_Turno") {
          df_combinado <- df_combinado %>% 
            arrange(desc(Fecha), factor(Municipio, levels = municipios), Turno)
        }
        
        saveRDS(df_combinado, ruta_archivo)
        return(df_combinado)
      }
      
      # Consolidación incremental IM
      final_resumen_pordia_IM <- combinar_resumen("tabla_soloIM_resumen_pordia.rds", res_im$resumen_pordia, "Fecha")
      final_resumen_pordiaymunicipio_IM <- combinar_resumen("tabla_soloIM_resumen_pordiaymunicipio.rds", res_im$resumen_pordiaymunicipio, "Fecha_Municipio")
      final_resumen_pordia_municipio_turno_completoconceros_IM <- combinar_resumen("tabla_soloIM_resumen_pordia_municipio_turno_completo.rds", res_im$resumen_pordia_municipio_turno_completoconceros, "Fecha_Municipio_Turno")
      
      # Consolidación incremental Fideicomiso
      final_resumen_pordia_FID <- combinar_resumen("tabla_soloFID_resumen_pordia.rds", res_fid$resumen_pordia, "Fecha")
      final_resumen_pordiaymunicipio_FID <- combinar_resumen("tabla_soloFID_resumen_pordiaymunicipio.rds", res_fid$resumen_pordiaymunicipio, "Fecha_Municipio")
      final_resumen_pordia_municipio_turno_completoconceros_FID <- combinar_resumen("tabla_soloFID_resumen_pordia_municipio_turno_completo.rds", res_fid$resumen_pordia_municipio_turno_completoconceros, "Fecha_Municipio_Turno")
      
    } else {
      # Proceso inicial: Guardar base completa por primera vez
      print("5. Guardando resúmenes completos en archivos RDS...")
      
      if (!dir.exists(ruta_carpeta)) {
        dir.create(ruta_carpeta, recursive = TRUE)
      }
      
      # Guardar IM
      saveRDS(res_im$resumen_pordia,      file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia.rds"))
      saveRDS(res_im$resumen_pordiaymunicipio,       file.path(ruta_carpeta, "tabla_soloIM_resumen_pordiaymunicipio.rds"))
      saveRDS(res_im$resumen_pordia_municipio_turno_completoconceros,       file.path(ruta_carpeta, "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds"))
      
      # Guardar Fideicomiso
      saveRDS(res_fid$resumen_pordia,      file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia.rds"))
      saveRDS(res_fid$resumen_pordiaymunicipio,       file.path(ruta_carpeta, "tabla_soloFID_resumen_pordiaymunicipio.rds"))
      saveRDS(res_fid$resumen_pordia_municipio_turno_completoconceros,       file.path(ruta_carpeta, "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds"))
      
      final_resumen_pordia_IM <- res_im$resumen_pordia
      final_resumen_pordiaymunicipio_IM <- res_im$resumen_pordiaymunicipio
      final_resumen_pordia_municipio_turno_completoconceros_IM <- res_im$resumen_pordia_municipio_turno_completoconceros
      
      final_resumen_pordia_FID <- res_fid$resumen_pordia
      final_resumen_pordiaymunicipio_FID <- res_fid$resumen_pordiaymunicipio
      final_resumen_pordia_municipio_turno_completoconceros_FID <- res_fid$resumen_pordia_municipio_turno_completoconceros
      
      print("Archivos guardados en la carpeta /data")
    }
    
    print("6. Consolidando lista final de retorno.")
    print(paste("FIN DEL PROCESO -", Sys.time()))
    print("------------------------------------------------------")
    
    return(list(
      resumen_pordia_IM = final_resumen_pordia_IM,
      resumen_pordiaymunicipio_IM = final_resumen_pordiaymunicipio_IM,
      resumen_pordia_municipio_turno_completoconceros_IM = final_resumen_pordia_municipio_turno_completoconceros_IM,
      
      resumen_pordia_FID = final_resumen_pordia_FID,
      resumen_pordiaymunicipio_FID = final_resumen_pordiaymunicipio_FID,
      resumen_pordia_municipio_turno_completoconceros_FID = final_resumen_pordia_municipio_turno_completoconceros_FID
    ))
  }
  
  ver <- funcion_df_nuevoinformediario(historico_llenado)
  
  ver$resumen_pordia_IM
  ver$resumen_pordiaymunicipio_IM
  #tabla_im <- ver$resumen_por_dia_y_municipio_im
  
