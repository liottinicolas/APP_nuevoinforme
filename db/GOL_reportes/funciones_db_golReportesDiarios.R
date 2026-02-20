funcion_actualizar_llenadoGOL <- function(rutas_completas, rutas_relativas) {
  
  # --- Función auxiliar interna ---
  modificar_the_geom_solo_llenadoGOL <- function(df) {
    if(!"the_geom" %in% colnames(df)) {
      return(df) # Si no está, devolvemos el df sin error para no romper el flujo
    }
    df <- df %>%
      mutate(the_geom = gsub("POINT \\(\\s+", "POINT (", gsub(",\\s*", " ", the_geom)))
    return(df)
  }
  
  # 1. Mapeo y Lectura con captura de errores
  lista_resultados <- map(set_names(seq_along(rutas_completas), rutas_relativas), function(i) {
    full_path <- rutas_completas[i]
    rel_path  <- rutas_relativas[i]
    
    tryCatch({
      # Leemos el CSV
      llenado_nuevo <- read_delim(
        file = full_path,
        delim = ",",
        locale = locale(encoding = "UTF-8"),
        trim_ws = TRUE,
        show_col_types = FALSE
      )
      return(llenado_nuevo)
      
    }, error = function(e) {
      message("⚠️ Error leyendo archivo GOL: ", rel_path, " | ", e$message)
      return(NULL)
    })
  })
  
  # 2. Filtrar archivos que se leyeron correctamente
  lista_exitosa <- compact(lista_resultados)
  archivos_ok <- names(lista_exitosa)
  
  # Si no hay datos nuevos, retornar estructura vacía
  if (length(lista_exitosa) == 0) {
    return(list(datos = NULL, archivos_ok = character(0)))
  }
  
  # 3. Procesamiento Global de los datos unidos
  llenado_nuevo <- bind_rows(lista_exitosa) %>% distinct()
  
  # Transformaciones de formato
  # Nota: %A depende del locale del sistema para el nombre del día
  llenado_nuevo$dia_viaje <- as.Date(llenado_nuevo$dia_viaje, format = "%A/%m/%d")
  llenado_nuevo$fecha_pasaje <- as.POSIXct(llenado_nuevo$fecha_pasaje, format = "%d-%m-%Y %H:%M:%S")
  llenado_nuevo$contenedor_gid <- as.character(llenado_nuevo$contenedor_gid)
  
  # Limpieza de strings y lógica de circuitos
  llenado_nuevo <- llenado_nuevo %>%
    mutate(
      condiciones_contenedor = condiciones_contenedor %>%
        str_replace_all("\\s*,\\s*", ";") %>%
        str_replace_all("\\s*;\\s*", ";") %>%
        str_replace_all(";{2,}", ";") %>%
        str_trim(),
      cod_recorrido = circuito %>%
        str_trim() %>%
        str_replace("^(CH|[A-G])_", "\\1_DU_RM_CL_"),
      Municipio = circuito %>%
        str_trim() %>%
        str_to_upper() %>%
        str_extract("^(CH|[A-G])")
    )
  
  # Selección y orden de columnas
  orden <- c("dia_viaje","cod_recorrido","posicion","ubicacion","levantado","turno","fecha_pasaje",
             "motivo_no_levante","porcentaje_llenado","numero_caja","contenedor_activo","id_viaje",
             "the_geom","contenedor_gid","condiciones_contenedor","Municipio","circuito","prioridad")
  
  llenado_nuevo <- dplyr::select(llenado_nuevo, any_of(orden))
  
  # Aplicar corrección de geometría
  llenado_nuevo <- modificar_the_geom_solo_llenadoGOL(llenado_nuevo)
  
  # Lógica de Oficina e IM
  llenado_nuevo <- llenado_nuevo %>% 
    mutate(
      Oficina = ifelse(grepl("^B_0?[1-7](\\b|$)", circuito), "Fideicomiso", "IM"),
      turno = factor(turno, levels = c("Matutino", "Vespertino", "Nocturno"))
    ) %>%
    arrange(desc(dia_viaje), cod_recorrido, posicion, desc(turno))
  
  # Renombrar columnas finales
  llenado_nuevo <- llenado_nuevo %>%
    rename(
      Fecha = dia_viaje,
      Circuito = cod_recorrido,
      Posicion = posicion,
      Direccion = ubicacion,
      Levantado = levantado,
      Turno_levantado = turno,
      Fecha_hora_pasaje = fecha_pasaje,
      Incidencia = motivo_no_levante,
      Porcentaje_llenado = porcentaje_llenado,
      Numero_caja = numero_caja,
      contenedor_activo = contenedor_activo,
      Id_viaje_GOL = id_viaje,
      gid = contenedor_gid,
      Condicion = condiciones_contenedor,
      Circuito_corto = circuito
    ) %>% 
    select(-any_of("prioridad"))
  
  # 4. Retornar lista compatible
  return(list(datos = llenado_nuevo, archivos_ok = archivos_ok))
}