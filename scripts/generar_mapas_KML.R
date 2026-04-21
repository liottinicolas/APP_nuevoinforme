generar_reportes_limpieza <- function(df, 
                                      fecha_inicio, 
                                      fecha_fin, 
                                      municipio, 
                                      top_n = 50, 
                                      archivo_excel = "Reporte_Puntos_Criticos_IM.xlsx", 
                                      archivo_kml = "puntos_criticos_circuito_posicion.kml") {
  
  # 1. Cargar librerías necesarias dentro de la función
  require(dplyr)
  require(openxlsx)
  require(sf)
  
  # 2. Filtrado de datos usando los parámetros
  ver <- df %>% 
    filter(Fecha >= fecha_inicio) %>%
    filter(Fecha <= fecha_fin) %>%
    filter(Municipio == municipio) %>% 
    filter(Condicion %in% c("Basura Afuera", "Escombro", "Poda"))
  
  # Validación de seguridad: detener si no hay datos
  if(nrow(ver) == 0) {
    stop("No se encontraron registros para los filtros especificados.")
  }
  
  # 3. Agrupación y conteo
  df_conteo <- ver %>%
    group_by(gid) %>%
    summarise(
      Denuncias = n(),
      Circuito_corto = first(Circuito_corto),
      Posicion = first(Posicion),
      Direccion = first(Direccion),
      the_geom = first(the_geom)
    ) %>%
    arrange(desc(Denuncias)) %>% 
    rename(Circuito = Circuito_corto)
  
  # 4. Aislar los "Top N" (por defecto 50)
  peores_n <- df_conteo %>% 
    head(top_n)
  
  # ==========================================
  # SECCIÓN EXCEL
  # ==========================================
  df_conteo_imprimir <- peores_n %>% 
    select(Direccion, Circuito, Posicion, Denuncias, gid)
  
  wb <- createWorkbook()
  addWorksheet(wb, "Reporte_Limpieza")
  
  writeDataTable(wb, sheet = "Reporte_Limpieza", x = df_conteo_imprimir, 
                 startCol = 1, startRow = 1, 
                 tableStyle = "TableStyleMedium2",
                 withFilter = TRUE)
  
  setColWidths(wb, sheet = "Reporte_Limpieza", cols = 1:ncol(df_conteo_imprimir), widths = "auto")
  saveWorkbook(wb, archivo_excel, overwrite = TRUE)
  
  # ==========================================
  # SECCIÓN KML
  # ==========================================
  df_sf <- st_as_sf(peores_n, wkt = "the_geom", crs = 32721) 
  
  df_kml <- st_transform(df_sf, crs = 4326) %>%
    mutate(
      Name = paste(Circuito, Posicion, sep = " - "),
      Description = as.character(Direccion),
      gid_attr = as.character(gid) 
    ) %>%
    select(Name, Description, gid = gid_attr, Circuito, Posicion, Denuncias)
  
  # Usamos quiet = TRUE para que no llene la consola de mensajes al guardar
  st_write(df_kml, archivo_kml, driver = "KML", delete_dsn = TRUE, quiet = TRUE)
  
  # Mensaje de éxito en la consola
  message(sprintf("¡Listo! Se exportaron los %s peores puntos a Excel y KML.", top_n))
  
  # (Opcional) Devolvemos el dataframe resumido de forma invisible por si lo quieres guardar en una variable
  invisible(peores_n)
}

## LLAMADA

# # Ejecución estándar (con tus parámetros originales)
# generar_reportes_limpieza(
#   df = historico_llenado,
#   fecha_inicio = "2026-01-15",
#   fecha_fin = "2026-02-28",
#   municipio = "B"
# )
# 
# # Ejemplo: Reporte del Municipio CH, solo los 20 peores, con nombres personalizados
# generar_reportes_limpieza(
#   df = historico_llenado,
#   fecha_inicio = "2026-03-01",
#   fecha_fin = "2026-03-31",
#   municipio = "CH",
#   top_n = 20,
#   archivo_excel = "Reporte_Marzo_CH.xlsx",
#   archivo_kml = "Puntos_CH_Marzo.kml"
# )