library(dplyr)
library(purrr)
library(readr)
library(tools)

funcion_actualizar_ubicaciones_10393 <- function(rutas_completas, rutas_relativas) {
  hoy <- Sys.Date()
  
  # Procesamos cada archivo y lo etiquetamos con su ruta relativa
  lista_resultados <- map(set_names(seq_along(rutas_completas), rutas_relativas), function(i) {
    full_path <- rutas_completas[i]
    rel_path <- rutas_relativas[i]
    
    tryCatch({
      # Validar fecha en el nombre del archivo
      fecha_nombre <- file_path_sans_ext(basename(full_path))
      fecha_dt <- as.Date(fecha_nombre)
      
      if (fecha_dt > hoy) {
        stop(paste("Fecha futura:", fecha_dt))
      }
      
      # Lectura de datos
      df <- read_delim(
        full_path, 
        delim = "\t", 
        escape_double = FALSE, 
        trim_ws = TRUE, 
        locale = locale(encoding = "ISO-8859-1"),
        show_col_types = FALSE
      )
      
      # Transformaciones iniciales
      df <- df %>%
        mutate(Fecha = fecha_dt) %>% 
        rename(gid = GID, Circuito = Recorrido) %>%
        mutate(gid = as.character(gid))
      
      return(df)
      
    }, error = function(e) {
      message("⚠️ Saltando archivo: ", rel_path, " | Motivo: ", e$message)
      return(NULL)
    })
  })
  
  # Filtrar los éxitos (quitar los NULL)
  lista_exitosa <- compact(lista_resultados)
  archivos_ok <- names(lista_exitosa)
  
  # Unir datos y aplicar filtros de limpieza finales
  datos_finales <- bind_rows(lista_exitosa)
  datos_finales <- datos_finales %>% 
    mutate(
      Oficina = ifelse(grepl("^B.*_0?[1-7]$", Circuito), "Fideicomiso", "IM"))
  
  
  datos_finales <- datos_finales %>% 
    mutate(Municipio = case_when(
      substring(Circuito,1,2) == "CH" ~ "CH",
      substring(Circuito,1,1) == "A" ~ "A",
      substring(Circuito,1,1) == "B" ~ "B",
      substring(Circuito,1,1) == "C" ~ "C",
      substring(Circuito,1,1) == "D" ~ "D",
      substring(Circuito,1,1) == "E" ~ "E",
      substring(Circuito,1,1) == "F" ~ "F",
      substring(Circuito,1,1) == "G" ~ "G")
    )
  
  datos_finales <- datos_finales %>%
    mutate(Circuito_corto = ifelse(
      # Si tiene 3 digitos
      substring(Circuito,nchar(Circuito)-3,nchar(Circuito)-3) == "_",
      #valor verdadero
      substring(Circuito,nchar(Circuito)-2,nchar(Circuito)),
      substring(Circuito,nchar(Circuito)-1,nchar(Circuito))
    )) %>%
    mutate(Circuito_corto = paste0(Municipio,"_",Circuito_corto))
  
  
  
  # if (nrow(datos_finales) > 0) {
  #   # Suponiendo que 'arreglar_direcciones' existe en tu entorno
  #   datos_finales <- arreglar_direcciones(datos_finales) %>% 
  #     distinct() %>%
  #     filter(!((is.na(Calle) | Calle == "") & (is.na(Numero) | Numero == "")))
  # }
  
  return(list(datos = datos_finales, archivos_ok = archivos_ok))
}

