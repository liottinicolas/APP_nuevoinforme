# ==============================================================================
# cargaDeDatos.R
# Procesa los archivos CSV nuevos de cada módulo y los incorpora al histórico
# RDS correspondiente, evitando reprocesar archivos ya incorporados.
#
# Flujo general:
#   1. preparar_entorno()           → carga paquetes necesarios
#   2. cargar_configuracion_modulo() → resuelve las rutas del módulo
#   3. actualizar_planillas_RDS()   → detecta archivos nuevos y actualiza el RDS
#
# Al finalizar, las variables de histórico quedan en el entorno global:
#   historico_llenado     → datos de llenado GOL (GOL_reportes)
#   historico_ubicaciones → datos de ubicaciones de camiones (10393_ubicaciones)
#
# Las funciones auxiliares se eliminan del entorno al final (sección "Limpieza").
# ==============================================================================


# ── Función principal: actualizar_planillas_RDS ───────────────────────────────

# Detecta archivos CSV nuevos en una carpeta de módulo, los procesa usando
# la función específica del módulo, y actualiza el RDS histórico acumulado.
# Lleva registro de qué archivos ya fueron procesados para no duplicar datos.
#
# El diseño es incremental: solo procesa lo que es nuevo respecto al último run.
# Si un archivo falla, se registra el error pero no se bloquea el resto.
#
# Parámetros:
#   ruta_funciones            - ruta al .R con las funciones específicas del módulo
#                               (ej: funciones_db_llenadoGol.R)
#   ruta_carpeta_archivos     - carpeta con los CSV a procesar (ej: archivos/GOL_reportes/)
#   ruta_RDS_datos            - RDS donde se acumula el histórico (ej: historico_llenadoGol.rds)
#   ruta_RDS_archivos_procesados - RDS con la lista de rutas de archivos ya procesados
#
# Retorna:
#   data.frame con el histórico completo ordenado por Fecha desc, o NULL si no hay datos.
#
# Uso:
#   rutas <- cargar_configuracion_modulo("GOL_reportes")
#   historico_llenado <- actualizar_planillas_RDS(
#     rutas$ruta_funciones, rutas$ruta_carpeta_archivos,
#     rutas$ruta_RDS_datos, rutas$ruta_RDS_archivos_procesados
#   )

# ruta_RDS_archivos_procesados <- rutas_ubicaciones$ruta_RDS_archivos_procesados
actualizar_planillas_RDS <- function(
    ruta_funciones,
    ruta_carpeta_archivos,
    ruta_RDS_datos,
    ruta_RDS_archivos_procesados) {

  # 1. Cargar las funciones específicas del módulo (ej: funcion_actualizar_llenadoGOL)
  #    nzchar() verifica que la ruta no sea string vacío antes de intentar el source
  if (nzchar(ruta_funciones) && file.exists(ruta_funciones)) {
    source(ruta_funciones)
  }

  # El nombre de la carpeta de archivos identifica el módulo (ej: "GOL_reportes")
  nombre_consulta <- basename(ruta_carpeta_archivos)

  # 2. Cargar el registro de archivos ya procesados.
  #    Si el RDS no existe aún (primera ejecución), se usa un vector vacío.
  archivos_procesados <- if (file.exists(ruta_RDS_archivos_procesados)) {
    readRDS(ruta_RDS_archivos_procesados)
  } else {
    character(0)
  }

  # 3. Escanear la carpeta buscando todos los CSV (incluyendo subcarpetas).
  #    Se usan rutas relativas a la raíz del proyecto para que el registro
  #    de archivos_procesados sea portable entre máquinas.
  lista_archivos   <- dir_ls(ruta_carpeta_archivos, glob = "*.csv", recurse = TRUE)
  ruta_relativa    <- path_rel(lista_archivos, start = here()) %>% path_tidy()
  archivos_nuevos_rel <- setdiff(ruta_relativa, archivos_procesados)  # solo los que no procesamos aún

  if (length(archivos_nuevos_rel) > 0) {
    message("Procesando ", length(archivos_nuevos_rel), " archivos nuevos para: ", nombre_consulta)

    rutas_completas_nuevas <- here(archivos_nuevos_rel)

    # Acumuladores para el resultado combinado de todos los archivos
    datos_acumulados  <- NULL   # data.frame con filas de todos los archivos OK
    archivos_ok_total <- c()    # rutas relativas de los que salieron bien
    archivos_error    <- c()    # rutas relativas de los que fallaron (para el log)

    # 4. Procesar cada archivo individualmente.
    #    Primero se valida el nombre, después el contenido con tryCatch.
    #    Los archivos inválidos o con errores NO se registran en archivos_procesados
    #    y se reintentarán automáticamente en la próxima ejecución.
    for (i in seq_along(archivos_nuevos_rel)) {
      archivo_rel <- archivos_nuevos_rel[i]
      archivo_abs <- rutas_completas_nuevas[i]
      nombre_archivo <- basename(archivo_rel)  # ej: "2026-04-22.csv"

      # ── Validación 1: nombre con formato YYYY-MM-DD.csv ──────────────────────
      patron_nombre <- "^\\d{4}-\\d{2}-\\d{2}\\.csv$"
      if (!grepl(patron_nombre, nombre_archivo)) {
        archivos_error <- c(archivos_error, archivo_rel)
        message("⚠️ Nombre de archivo no válido: ", nombre_archivo)
        message("   Se esperaba el formato: YYYY-MM-DD.csv (ej: 2026-04-22.csv)")
        message("   El archivo fue ignorado.")
        next  # saltar al siguiente archivo sin procesar este
      }

      # ── Validación 2: la fecha del nombre no puede ser posterior a hoy ────────
      fecha_archivo <- tryCatch(
        as.Date(sub("\\.csv$", "", nombre_archivo)),  # extrae la parte de fecha
        error = function(e) NA
      )
      if (is.na(fecha_archivo) || fecha_archivo > Sys.Date()) {
        archivos_error <- c(archivos_error, archivo_rel)
        message("⚠️ Fecha futura o inválida en el nombre: ", nombre_archivo)
        message("   La fecha del archivo (", format(fecha_archivo, "%d/%m/%Y"),
                ") es posterior a hoy (", format(Sys.Date(), "%d/%m/%Y"), ").")
        message("   El archivo fue ignorado.")
        next
      }

      # ── Procesamiento del contenido con tryCatch ──────────────────────────────
      tryCatch({

        # Llamar al procesador del módulo con un solo archivo a la vez
        resultado_i <- if (nombre_consulta == "10393_ubicaciones") {
          funcion_actualizar_ubicaciones_10393(archivo_abs, archivo_rel)
        } else if (nombre_consulta == "GOL_reportes") {
          funcion_actualizar_llenadoGOL(archivo_abs, archivo_rel)
        } else {
          stop("Módulo desconocido: ", nombre_consulta)
        }

        # Acumular datos y marcar el archivo como exitoso
        datos_acumulados  <- bind_rows(datos_acumulados, resultado_i$datos)
        archivos_ok_total <- c(archivos_ok_total, resultado_i$archivos_ok)

      }, error = function(e) {
        # El contenido del archivo falló — registrar y seguir con el próximo
        archivos_error <<- c(archivos_error, archivo_rel)
        message("⚠️ Error al procesar el contenido de: ", nombre_archivo)
        message("   Error: ", e$message)
      })
    }


    # Resumen post-loop
    if (length(archivos_error) > 0) {
      message("❌ ", length(archivos_error), " archivo(s) no pudieron procesarse y serán reintentados la próxima vez.")
    }

    # Construir el resultado_proceso con la misma estructura que antes
    resultado_proceso <- if (length(archivos_ok_total) > 0) {
      list(datos = datos_acumulados, archivos_ok = archivos_ok_total)
    } else {
      NULL
    }


    # 5. Si hubo archivos procesados exitosamente, actualizar el histórico RDS
    if (!is.null(resultado_proceso) && length(resultado_proceso$archivos_ok) > 0) {

      # Leer el histórico acumulado anterior (NULL si es la primera vez)
      historico <- if (file.exists(ruta_RDS_datos)) readRDS(ruta_RDS_datos) else NULL

      # Extraer los datos nuevos del resultado
      datos_nuevos <- resultado_proceso$datos

      # Unir histórico anterior con los datos nuevos y eliminar duplicados exactos.
      # distinct() es la red de seguridad ante procesamientos accidentales dobles.
      historico <- bind_rows(historico, datos_nuevos) %>%
        distinct()

      # Guardar el histórico actualizado
      saveRDS(historico, file = ruta_RDS_datos)

      # Actualizar el registro de archivos procesados (solo los exitosos)
      # Así si un archivo falló, se reintentará en la próxima ejecución
      archivos_procesados <- c(archivos_procesados, resultado_proceso$archivos_ok)
      saveRDS(archivos_procesados, file = ruta_RDS_archivos_procesados)

      message("✅ Éxito: Se incorporaron ", length(resultado_proceso$archivos_ok), " archivos.")
    } else {
      message("⚠️ No se pudo procesar ningún archivo nuevo (posibles errores de formato o fecha).")
    }

  } else {
    message("☕ No hay archivos nuevos para ", nombre_consulta)
  }

  # 6. Leer y retornar el histórico final desde disco (fuente de verdad).
  #    Se ordena de más reciente a más antiguo para facilitar inspección.
  final_df <- if (file.exists(ruta_RDS_datos)) readRDS(ruta_RDS_datos) else NULL
  if (!is.null(final_df)) {
    final_df <- final_df %>% arrange(desc(Fecha))
  }

  return(final_df)
}


# ── Ejecución: carga y actualización de módulos ───────────────────────────────

# Paso 1: preparar el entorno R (paquetes, zona horaria, opciones)
preparar_entorno()

# Paso 2: Módulo GOL_reportes — histórico de llenado de contenedores
# Detecta CSVs nuevos en archivos/GOL_reportes/ y los incorpora a historico_llenadoGol.rds
rutas_llenado <- cargar_configuracion_modulo("GOL_reportes")

historico_llenado <- actualizar_planillas_RDS(
  ruta_funciones                = rutas_llenado$ruta_funciones,
  ruta_carpeta_archivos         = rutas_llenado$ruta_carpeta_archivos,
  ruta_RDS_datos                = rutas_llenado$ruta_RDS_datos,
  ruta_RDS_archivos_procesados  = rutas_llenado$ruta_RDS_archivos_procesados
)

# Paso 3: Módulo 10393_ubicaciones — histórico de ubicaciones de camiones
# Detecta CSVs nuevos en archivos/10393_ubicaciones/ y los incorpora a historico_ubicaciones.rds
rutas_ubicaciones <- cargar_configuracion_modulo("10393_ubicaciones")

historico_ubicaciones <- actualizar_planillas_RDS(
  ruta_funciones                = rutas_ubicaciones$ruta_funciones,
  ruta_carpeta_archivos         = rutas_ubicaciones$ruta_carpeta_archivos,
  ruta_RDS_datos                = rutas_ubicaciones$ruta_RDS_datos,
  ruta_RDS_archivos_procesados  = rutas_ubicaciones$ruta_RDS_archivos_procesados
)


# ── Limpieza del entorno ───────────────────────────────────────────────────────
# Se eliminan del entorno global las funciones auxiliares y variables de rutas
# que ya cumplieron su propósito. Solo quedan historico_llenado e historico_ubicaciones,
# que son los datos que necesitan los módulos de informes.

funciones_a_borrar <- c("actualizar_planillas_RDS", "cargar_archivo",
                        "cargar_configuracion_modulo", "funcion_actualizar_llenadoGOL",
                        "funcion_actualizar_ubicaciones_10393", "preparar_entorno")

rm(list = funciones_a_borrar[funciones_a_borrar %in% ls()])

rm(rutas_llenado)
rm(rutas_ubicaciones)
rm(funciones_a_borrar)