library(httr2)
library(jsonlite)

obtener_posiciones <- function(matricula, desde, hasta, grupo = "sisconve", stops_only = FALSE) {
  
  base_url <- "https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones"
  
  req <- request(base_url) %>%
    req_url_query(
      matricula = matricula,
      fechaDesde = desde,
      fechaHasta = hasta,
      grupo = grupo,
      showStopsOnly = tolower(as.character(stops_only))
    )
  
  # Realizar la petición
  resp <- req_perform(req)
  
  # Parsear el JSON a un Data Frame
  datos <- resp %>% resp_body_json(simplifyVector = TRUE)
  
  return(datos)
}

# Valor (clave) Descripción
 # sisconve - Vehículos propios de la IM
 # waste - Transportistas de residuos privados
 # crane - Grúas
 # hired - Vehículos de alquiler

# Ejemplo de uso:
df_posiciones <- obtener_posiciones("SIM3024", "2026-04-10T13:49:11", "2026-04-14T13:49:11")