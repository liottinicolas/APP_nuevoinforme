
# ruta_RDS_archivos_procesados <- rutas_ubicaciones$ruta_RDS_archivos_procesados
actualizar_planillas_RDS <- function(
    ruta_funciones,
    ruta_carpeta_archivos,
    ruta_RDS_datos,
    ruta_RDS_archivos_procesados) {
  
  # 1. Cargar funciones auxiliares
  if (nzchar(ruta_funciones) && file.exists(ruta_funciones)) {
    source(ruta_funciones)
  }
  
  nombre_consulta <- basename(ruta_carpeta_archivos)
  
  # 2. Cargar historial de archivos ya procesados
  archivos_procesados <- if (file.exists(ruta_RDS_archivos_procesados)) {
    readRDS(ruta_RDS_archivos_procesados)
  } else {
    character(0)
  } 
  
  # 3. Escaneo de archivos nuevos
  lista_archivos <- dir_ls(ruta_carpeta_archivos, glob = "*.csv", recurse = TRUE)
  ruta_relativa <- path_rel(lista_archivos, start = here()) %>% path_tidy()
  archivos_nuevos_rel <- setdiff(ruta_relativa, archivos_procesados)
  
  if (length(archivos_nuevos_rel) > 0) {
    message("Procesando ", length(archivos_nuevos_rel), " archivos nuevos para: ", nombre_consulta)
    
    rutas_completas_nuevas <- here(archivos_nuevos_rel)
    resultado_proceso <- NULL
    
    # 4. Ejecución según módulo (ajustado para recibir lista de archivos)
    if (nombre_consulta == "10393_ubicaciones") {
      resultado_proceso <- funcion_actualizar_ubicaciones_10393(rutas_completas_nuevas, archivos_nuevos_rel)
    } 
    
    # Nota: Si tienes GOL_reportes, deberías ajustarlo para que devuelva la misma estructura de lista
    if (nombre_consulta == "GOL_reportes") {
       resultado_proceso <- funcion_actualizar_llenadoGOL(rutas_completas_nuevas, archivos_nuevos_rel)
    }
    
    # 5. Guardar cambios si hubo éxitos
    if (!is.null(resultado_proceso) && length(resultado_proceso$archivos_ok) > 0) {
      
      # Unir datos nuevos al histórico
      historico <- if (file.exists(ruta_RDS_datos)) readRDS(ruta_RDS_datos) else NULL
      
      historico <- bind_rows(historico, resultado_proceso$datos) %>% 
        distinct()
      
      # historico <- historico_ubicaciones %>%
      #   mutate(
      #     Oficina = ifelse(grepl("^B.*_0?[1-7]$", Circuito), "Fideicomiso", "IM"))

      #ruta_RDS_datos <- rutas_ubicaciones$ruta_RDS_datos
      saveRDS(historico, file = ruta_RDS_datos)
      # Actualizar lista de procesados SOLO con los que no dieron error
      archivos_procesados <- c(archivos_procesados, resultado_proceso$archivos_ok)
      saveRDS(archivos_procesados, file = ruta_RDS_archivos_procesados)

      
      message("✅ Éxito: Se incorporaron ", length(resultado_proceso$archivos_ok), " archivos.")
    } else {
      message("⚠️ No se pudo procesar ningún archivo nuevo (posibles errores de formato o fecha).")
    }
    
  } else {
    message("☕ No hay archivos nuevos para ", nombre_consulta)
  }
  
  # 6. Retornar el histórico actualizado para uso inmediato
  final_df <- if (file.exists(ruta_RDS_datos)) readRDS(ruta_RDS_datos) else NULL
  if (!is.null(final_df)) {
    final_df <- final_df %>% arrange(desc(Fecha))
  }
  
  return(final_df)
}


# 1. Cargamos el entorno y las funciones de configuración
# (Asegúrate de haber corrido las funciones que definimos antes)
preparar_entorno() 

# 2. Obtenemos las rutas del módulo específico
rutas_llenado <- cargar_configuracion_modulo("GOL_reportes")

# 3. Ejecutamos la actualización (ahora con 4 argumentos, sin ruta_proyecto)
historico_llenado <- actualizar_planillas_RDS(
  ruta_funciones                = rutas_llenado$ruta_funciones, 
  ruta_carpeta_archivos         = rutas_llenado$ruta_carpeta_archivos, 
  ruta_RDS_datos                = rutas_llenado$ruta_RDS_datos,
  ruta_RDS_archivos_procesados  = rutas_llenado$ruta_RDS_archivos_procesados
)

## 2. Datos de ubicaciones ----
rutas_ubicaciones <- cargar_configuracion_modulo("10393_ubicaciones")
# Definir globalmente la variable para esta sección
historico_ubicaciones <- actualizar_planillas_RDS(
  ruta_funciones                = rutas_ubicaciones$ruta_funciones, 
  ruta_carpeta_archivos         = rutas_ubicaciones$ruta_carpeta_archivos, 
  ruta_RDS_datos                = rutas_ubicaciones$ruta_RDS_datos,
  ruta_RDS_archivos_procesados  = rutas_ubicaciones$ruta_RDS_archivos_procesados
)



# Limpieza de datos


funciones_a_borrar <- c("actualizar_planillas_RDS", "cargar_archivo", 
                        "cargar_configuracion_modulo", "funcion_actualizar_llenadoGOL", 
                        "funcion_actualizar_ubicaciones_10393", "preparar_entorno")

rm(list = funciones_a_borrar[funciones_a_borrar %in% ls()])

rm(rutas_llenado)
rm(rutas_ubicaciones)
rm(funciones_a_borrar)