
# Forma 1 - Pública ----

library(sf)
library(dplyr)

# Definimos el DSN (la ruta al servidor)
dsn <- "WFS:https://montevideo.gub.uy/app/geoserver/ows?service=WFS&version=1.2.0"
capas_disponibles_dsn <- st_layers(dsn)

# FUNCIÓN: cargar_capa_mvd
# Parámetros:
#   - nombre_capa: El texto exacto de la columna 'layer_name'
#   - transformar_gps: Si es TRUE (por defecto), lo pasa a coordenadas GPS (Lat/Long)
cargar_capa_mvd <- function(nombre_capa, transformar_gps = TRUE) {
  
  message(paste("Intentando descargar la capa:", nombre_capa, "..."))
  
  # Usamos tryCatch para capturar errores si la capa no existe o falla la red
  capa <- tryCatch({
    temp <- st_read(dsn, layer = nombre_capa, quiet = TRUE)
    
    if (transformar_gps) {
      temp <- st_transform(temp, 4326) # 4326 es el estándar de GPS (WGS84)
    }
    
    message("✅ ¡Carga exitosa!")
    return(temp)
    
  }, error = function(e) {
    message("❌ Error al cargar la capa. Verifica el nombre o la conexión.")
    print(e)
    return(NULL)
  })
  
  return(capa)
}



# GUÍA DE CAPAS DISPONIBLES EN EL SERVIDOR WFS - INTENDENCIA DE MONTEVIDEO


# --- 1. DIVISIONES ADMINISTRATIVAS (Ideales para agrupar datos) ---
# 14: mapstore-tematicas:zon_v_sig_barrios        -> Los 62 barrios oficiales.
# 99: mapstore-tematicas:zon_v_sig_municipios      -> Límites de Municipios (A al G).
# 27: mapstore-tematicas:zon_v_sig_comunales       -> Zonas de los Centros Comunales (CCZ).
# 36: mapstore-tematicas:zon_cpost                 -> Códigos Postales.
# 49: mapstore-tematicas:zon_d_electorales         -> Distritos electorales.

# --- 2. RESIDUOS Y LIMPIEZA (Relacionado directamente con tu análisis) ---
# 31: mapstore-tematicas:ssmm_contenedores_domiciliarios -> Ubicación de contenedores de basura.
# 160: mapstore-tematicas:ssmm_v_re_zona_tercerizada_vigente -> Zonas donde la limpieza la hace un privado.
# 32: mapstore-tematicas:ma_v_ep_residuos_decaux    -> Puntos de residuos de gran tamaño / específicos.
# 161: gol_publico:intradomiciliario_circuito       -> Circuitos de recolección interna.

# --- 3. INFRAESTRUCTURA VIAL Y ACERAS ---
# 51: mapstore-base:cb_v_sig_vias                  -> Todas las calles y caminos de MVD.
# 2:  mapstore-base:cb_v_sig_aceras                -> Dibujo de las veredas (polígonos).
# 12: mapstore-base:cb_avenidasCerca               -> Avenidas principales (visualización).
# 65: mapstore-tematicas:vyt_v_mdg_vias_sentido    -> Sentido de circulación de las calles.
# 150: mapstore-tematicas:acc_veredas_accesibles   -> Estado de accesibilidad de las veredas.

# --- 4. ARBOLADO Y ESPACIOS PÚBLICOS ---
# 7:  mapstore-tematicas:ssmm_v_sig_arboles        -> Censo de todos los árboles (muy pesada).
# 54: mapstore-base:cb_v_sig_espacios_publicos     -> Parques, plazas y áreas verdes.
# 159: mapstore-tematicas:syc_espaciosPerrosSueltos -> Zonas permitidas para mascotas.
# 64: mapstore-tematicas:syc_V_SF_FERIAS_GEOM      -> Ubicación y área de las ferias vecinales.

# --- 5. TRANSPORTE PÚBLICO Y MOVILIDAD ---
# 112: mapstore-tematicas:vyt_v_uptu_ubic_paradas_con_horarios -> Paradas de ómnibus.
# 15: mapstore-tematicas:vyt_v_bi_bicicircuitos_activos -> Ciclovías y bicisendas.
# 111: mapstore-tematicas:vyt_paradas_taxi          -> Puntos de parada de taxis.
# 137: mapstore-tematicas:vyt_v_int_semaforos       -> Ubicación de todos los semáforos.

# --- 6. CATASTRO Y EDIFICACIÓN ---
# 94: mapstore-tematicas:ic_v_mdg_manzanas         -> Manzanas catastrales.
# 22: mapstore-tematicas:ot_v_mdg_parcelas_cat_suelo -> Padrones/terrenos (muy pesada).
# 105: mapstore-base:cb_v_mdg_accesos_puerta        -> Numeración de puertas (direcciones exactas).
# 5:  citim_no_descargable:ot_citim_vis_alturas_0326 -> Alturas permitidas para edificar.

# --- 7. SOCIAL Y SALUD ---
# 10: mapstore-tematicas:hyv_v_ai_asentamientos_sig -> Polígonos de asentamientos.
# 11: mapeo_social:ms_at_sit_calle                 -> Puntos de atención a personas en calle.
# 100: mapeo_social:ms_in_movilsalud               -> Ubicación de policlínicas móviles.
# 107: mapstore-tematicas:abc_v_dds_ollasymerenderos_internet -> Ollas populares y merenderos.

# --- 8. PATRIMONIO Y CULTURA ---
# 97: mapstore-tematicas:ot_v_pat_mhn_bienespatrimoniales -> Monumentos Históricos Nacionales.
# 69: citim:ot_citim_v_citim_pat_gpp_apcentro      -> Grado de protección de edificios en el Centro.

# --- 9. OTROS SERVICIOS ---
# 89: mapstore-tematicas:ssmm_v_utap_luminaria     -> Todas las luces de la calle (puntos).
# 132: mapstore-tematicas:ssmm_ss_captaciones      -> Red de saneamiento (bocas de tormenta).


## Cargo
nombre_capaver <- cargar_capa_mvd("mapstore-tematicas:vyt_v_mdg_vias_sentido")
# Dibujo
plot(st_geometry(nombre_capaver))


# Forma 2 - Más interna y manual ----

library(httr)
library(xml2)
library(dplyr)
library(sf)
library(purrr) # Para iterar de forma limpia

# 1. CONEXIÓN Y OBTENCIÓN DE CAPAS
wfs_url <- "http://geoserver.montevideo.gub.uy/geoserver/wfs"

message("⏳ Conectando al servidor de Montevideo...")
cap <- GET(wfs_url, query = list(service="WFS", version="2.0.0", request="GetCapabilities"))
stop_for_status(cap)

doc <- read_xml(content(cap, "text", encoding="UTF-8"))
fts <- xml_find_all(doc, ".//*[local-name()='FeatureType']")

# 2. CREACIÓN DEL CATÁLOGO EXTENDIDO
# Iteramos sobre cada 'FeatureType' para extraer todos sus metadatos
layers <- fts %>%
  map_df(~{
    # Extraemos los Keywords y los pegamos en un solo texto separado por comas
    keywords_node <- xml_find_all(.x, ".//*[local-name()='Keyword']")
    keywords_text <- paste(xml_text(keywords_node), collapse = ", ")
    
    # Construimos el tibble fila por fila
    tibble(
      Name           = xml_text(xml_find_first(.x, ".//*[local-name()='Name']")),
      Title          = xml_text(xml_find_first(.x, ".//*[local-name()='Title']")),
      Abstract       = xml_text(xml_find_first(.x, ".//*[local-name()='Abstract']")),
      Keywords       = keywords_text,
      DefaultCRS     = xml_text(xml_find_first(.x, ".//*[local-name()='DefaultCRS']")),
      # Límites geográficos (Bounding Box)
      LowerCorner    = xml_text(xml_find_first(.x, ".//*[local-name()='LowerCorner']")),
      UpperCorner    = xml_text(xml_find_first(.x, ".//*[local-name()='UpperCorner']")),
      # Formatos de salida soportados
      OutputFormats  = paste(xml_text(xml_find_all(.x, ".//*[local-name()='Format']")), collapse = ", ")
    )
  })

# --- ESTO ES LO QUE PEDISTE PARA VER LAS CAPAS ---
# Abre una ventana interactiva en RStudio para buscar y filtrar fácilmente
View(layers) 

# Abstract: Es la descripción detallada. Aquí es donde realmente te enteras de qué trata la capa (por ejemplo, si los datos de "pacientes" son de un programa específico o de toda la red).
# 
# Keywords: Etiquetas que te ayudan a filtrar (ej: "salud", "transporte", "cartografía").
# 
# DefaultCRS: Te dice en qué sistema de coordenadas vienen los datos originalmente (muy importante para que no te queden los contenedores en medio del océano en el mapa).
# 
# LowerCorner / UpperCorner: Te dan las coordenadas mínimas y máximas. Sirven para saber si la capa cubre todo Montevideo o solo una zona pequeña.
# 
# OutputFormats: Te confirma si la capa se puede bajar como JSON, GML, Shapefile, etc.


# 3. FUNCIÓN PARA CARGAR LA CAPA (POR NOMBRE TÉCNICO)
# 1. Definimos la URL base
url_base_wfs <- "http://geoserver.montevideo.gub.uy/geoserver/wfs"

# 2. Creamos la función usando tu lógica de GET
descargar_capa_mvd <- function(nombre_tecnico, limite = NULL) {
  
  message(paste("⏳ Solicitando JSON de:", nombre_tecnico, "..."))
  
  # Parámetros calcados de tu ejemplo que funciona
  query_params <- list(
    service = "WFS",
    version = "1.0.0",
    request = "GetFeature",
    typeName = nombre_tecnico,
    srsname = "EPSG:32721",
    outputFormat = "application/json"
  )
  
  # Si quieres probar con pocos datos primero, puedes pasar un límite
  if (!is.null(limite)) {
    query_params$maxFeatures <- limite
  }
  
  # Ejecutar la consulta
  respuesta <- GET(url_base_wfs, query = query_params)
  
  # Validar si el servidor respondió bien
  if (status_code(respuesta) != 200) {
    stop("❌ Error en el servidor. Código: ", status_code(respuesta))
  }
  
  # Convertir el contenido JSON directamente a un objeto espacial (sf)
  message("📦 Procesando datos...")
  capa_sf <- st_read(content(respuesta, "text", encoding = "UTF-8"), quiet = TRUE)
  
  message("✅ ¡Listo! Capa cargada.")
  return(capa_sf)
}

# --- EJEMPLO DE USO ---
# Una vez que viste el nombre en el View(layers), lo usas aquí:
mi_capa <- descargar_capa_mvd("gol:intradomiciliario_circuito")