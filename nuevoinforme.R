# ==============================================================================
# nuevoinforme.R
# Script principal. Ejecutar manualmente para actualizar datos y generar todos
# los informes del sistema (DFR, GOL/Postgres, informes R, informes Python
# y sincronización de la app Shiny).
# ==============================================================================


# ── 1. SETUP: funciones y definiciones ────────────────────────────────────────
# Cargar primero las funciones para que estén disponibles en los pasos siguientes.

source("global.R")
source("funciones_utiles.R")          # Funciones auxiliares compartidas

source("funciones_descarga_consulta10393ubicaciones.R") # Funcion para descargar por DIA las ubicaciones.
source("funciones_descarga_reportesGOL.R")                 # Funcion para descargar reportes de levantes.
source("cargaDeDatos.R")              # Carga de datos base del proyecto

source("informes/informe_diario.R")   # Define generar_reporte_dia() y afines
source("informes/informecamiones.R")  # Define generar_reporte_pdf_camiones...()


# ── 2. ACTUALIZAR DATOS EXTERNOS ──────────────────────────────────────────────

# Capas geoespaciales del DFR descargadas desde el WFS y guardadas como RDS local
source("db/DFR/conexionDFR.R")
actualizar_capas_wfs(base_dir = "db/DFR")

# Circuitos de contenedores GOL (API limpieza-gestion-operativa): guarda en
# db/GOL_reportes/historico_circuitos_gol.rds una versión nueva de cada
# circuito solo cuando cambió su "periodo". Si falla, no corta el informe.
source("db/GOL_reportes/funciones_db_circuitosGOL.R")
tryCatch(
  actualizar_historico_circuitos_gol(),
  error = function(e) warning("Historico circuitos GOL fallo: ", conditionMessage(e))
)



# Uso de referencia (carga local de capas ya descargadas):
# lista_sf <- cargar_capas_local(base_dir = "db/DFR", formato = "RDS")
# posiciones_dfr_viejos <- lista_sf[["dfr_C_DF_POSICIONES_RECORRIDO:HISTORICO"]]
# posiciones_dfr_actuales <- lista_sf[["dfr_E_DF_POSICIONES:RECORRIDO"]]
# zonas <- lista_sf[["dfr_E_DF_ZONA:RECORRIDO"]]

# Datos operativos desde PostgreSQL (llenado GOL, ubicaciones, etc.)
# source("db/POSTGRES/conexionPOSTGRES.R")

# UNA POR CIRCUITO: recalcula el historico de ubicaciones enriquecido
# (PERIODO, ultimo levante, UNA) a partir de lo que se acaba de actualizar
# arriba (historico_ubicaciones, historico_llenadoGol y las capas del DFR).
# Corre en procesos de R aparte (ver UNA_POR_CIRCUITO/scripts/UNA_por_circuito.r)
# para no competir por memoria con el resto de este script, y por defecto en
# modo incremental (solo procesa los dias nuevos). Si falla, no corta el
# resto del informe diario.
.wd_antes_de_una <- getwd()
tryCatch(
  source("UNA_POR_CIRCUITO/scripts/UNA_por_circuito.r"),
  error = function(e) warning("UNA_POR_CIRCUITO fallo: ", conditionMessage(e)),
  finally = setwd(.wd_antes_de_una)  # el script interno hace su propio setwd()
)


# ── 3. GENERAR INFORMES EN R ──────────────────────────────────────────────────

# Informe diario de llenado (fecha = NULL usa el día de hoy)
# inf_deldia <- generar_reporte_dia("2026-02-17", historico_ubicaciones, historico_llenado)  # uso con fecha específica
# inf_deldia <- generar_reporte_dia(NULL, historico_ubicaciones, historico_llenado)

# Informe PDF diario IM
# generar_reporte_pdf_informediario(fecha = "2026-02-17", instalar_librerias = FALSE)  # uso con fecha específica
# generar_reporte_pdf_informediario(fecha = NULL, instalar_librerias = FALSE)

# Informe PDF camiones y levantes IMF/FID (fecha = NULL usa el día de hoy)
generar_reporte_pdf_camionesylevantesIMFID(fecha = "2026-02-17", instalar_librerias = FALSE)  # uso con fecha específica
  generar_reporte_pdf_camionesylevantesIMFID(fecha = NULL, instalar_librerias = TRUE)


# ── 4. GENERAR INFORMES EN PYTHON ─────────────────────────────────────────────
# Usa el Python del entorno virtual de reticulate (se detecta automáticamente en cualquier PC)

  python_venv <- reticulate::virtualenv_python("r-reticulate")

# Corre un script de Python con el venv indicado, corta con stop() si falla
# (status != 0) y muestra la salida (stdout+stderr) en consola en cualquier caso.
ejecutar_python <- function(python_venv, script) {
  res <- system2(python_venv, args = script, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(res, "status")) && attr(res, "status") != 0) {
    stop(script, " fallo:\n", paste(res, collapse = "\n"))
  }
  cat(res, sep = "\n")
  invisible(res)
}

# Informe operativa (genera el PDF de la vista operativa)
ejecutar_python(python_venv, "vistas/informe_operativa/informeOP_generar_pdf.py")

# Vuelve a generar los mapas (CSV + capas/textos en QGIS) a partir del
# archivo_informe ya existente. Está separada en una función porque además de
# correr acá como parte del pipeline diario, hay que volver a llamarla sola
# (actualizar_mapas()) cada vez que alguien edite y guarde a mano el excel
# durante el día (por ejemplo al completar Disponibilidad a partir de un mail):
# ese guardado recalcula todo el libro y deja los mapas de QGIS con los valores
# de la corrida matutina. NO vuelve a correr actualizar_ayer.py: ese script
# avanza el "archivo madre" al día siguiente y no está pensado para correrse
# dos veces el mismo día.
actualizar_mapas <- function() {
  python_venv <- reticulate::virtualenv_python("r-reticulate")

  cat("Recordá cerrar QGIS Desktop antes de correr esto: los scripts\n")
  cat("qgis_mapa*.py necesitan escribir el .qgz y fallan si está abierto.\n\n")

  ejecutar_python(python_venv, "vistas/informediario/reportes/generar_mapas.py")

  ejecutar_python(python_venv, "scripts/qgis/qgis_mapaUNA.py")
  ejecutar_python(python_venv, "scripts/qgis/qgis_mapaAtraso.py")
  ejecutar_python(python_venv, "scripts/qgis/qgis_mapaRepetidos.py")
}

# Informe diario: primero actualiza los datos de ayer, luego genera los mapas
ejecutar_python(python_venv, "vistas/informediario/reportes/actualizar_ayer.py")
actualizar_mapas()

# ── 5. ACTUALIZAR APP SHINY ───────────────────────────────────────────────────

# Sube los pines de datos frescos a GitHub para que la app los lea sin necesidad de redeploy
source("vistas/App_informe_llenado/limpieza_datos.R")

# Solo ejecutar si hubo cambios en el código de la app (no en los datos):
  # rsconnect::deployApp("vistas/App_informe_llenado/")





# 
# 
# # 1. Vector mapeador con los nombres de los días ya normalizados (sin tildes)
# # wday(..., week_start = 1) devuelve: 1=Lunes, 2=Martes, ..., 7=Domingo
# dias_sin_tildes <- c("Lunes", "Martes", "Miercoles", "Jueves", "Viernes", "Sabado", "Domingo")
# 
# # 2. Aplicar filtros base, extraer orden cronológico y formatear la fecha de forma segura
# df_base <- gol_visitayprogramado_completo %>%
#   # Filtro: Fecha mayor o igual al domingo 24 de mayo de 2026
#   filter(Levantado == "S", Fecha >= "2026-05-24") %>%
#   mutate(
#     Fecha_Objeto = as.Date(Fecha),
#     # Obtenemos el número de día de la semana (1 a 7, empezando el Lunes)
#     Num_Dia_Semana = wday(Fecha_Objeto, week_start = 1),
#     # Mapeamos el número directamente al vector de texto plano seguro
#     Dia_Texto = dias_sin_tildes[Num_Dia_Semana],
#     # Armamos el formato final: "Miercoles 27"
#     Fecha_Formateada = paste0(Dia_Texto, " ", format(Fecha_Objeto, "%d"))
#   )
# 
# # --- 3. Generación de los 3 Dataframes Agrupados y Ordenados ---
# 
# # Pestaña 1: Agrupado por día con el total general de filas
# df_total_por_dia <- df_base %>%
#   group_by(Fecha_Objeto, Fecha = Fecha_Formateada) %>%
#   summarise(Total_Filas = n(), .groups = 'drop') %>%
#   arrange(Fecha_Objeto) %>%        # Orden cronológico garantizado por la fecha real
#   select(-Fecha_Objeto)            # Limpiamos la columna auxiliar
# 
# # Pestaña 2: Agrupado por día, cuando Oficina es "IM"
# df_im <- df_base %>%
#   filter(Oficina == "IM") %>%
#   group_by(Fecha_Objeto, Fecha = Fecha_Formateada) %>%
#   summarise(Total_Filas = n(), .groups = 'drop') %>%
#   arrange(Fecha_Objeto) %>%
#   select(-Fecha_Objeto)
# 
# # Pestaña 3: Agrupado por día, cuando Oficina es "Fideicomiso"
# df_fideicomiso <- df_base %>%
#   filter(Oficina == "Fideicomiso") %>%
#   group_by(Fecha_Objeto, Fecha = Fecha_Formateada) %>%
#   summarise(Total_Filas = n(), .groups = 'drop') %>%
#   arrange(Fecha_Objeto) %>%
#   select(-Fecha_Objeto)
# 
# 
# # --- 4. Exportación estructurada a Excel ---
# 
# lista_hojas <- list(
#   "Resumen Total General" = df_total_por_dia,
#   "Oficina IM" = df_im,
#   "Oficina Fideicomiso" = df_fideicomiso
# )
# 
# write.xlsx(
#   lista_hojas, 
#   file = "Resumen_GOL_Filtrado.xlsx", 
#   asTable = TRUE, 
#   tableStyle = "TableStyleMedium2"
# )
# 
# cat("¡Archivo 'Resumen_GOL_Filtrado.xlsx' generado con éxito, ordenado y sin tildes!\n")







