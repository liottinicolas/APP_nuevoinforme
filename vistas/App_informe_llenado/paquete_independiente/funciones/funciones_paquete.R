# ==============================================================================
# funciones_paquete.R
# Funciones que usa actualizar_y_publicar.R. No hace falta abrir este archivo.
#
# Son copias reducidas de las del proyecto APP_nuevoinforme:
#   - procesar_csv_gol()        <- db/GOL_reportes/funciones_db_golReportesDiarios.R
#   - descargar_capas_dfr()     <- db/DFR/conexionDFR.R (cargar_capas_wfs)
#   - recortar_historico()      <- vistas/App_informe_llenado/limpieza_datos.R
# Si cambian allá, cambiarlas acá también.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(sf)
  library(pins)
})

# Columnas del histórico que usa la app (mismas que limpieza_datos.R).
COLUMNAS_HISTORICO <- c(
  "gid", "Fecha", "Fecha_hora_pasaje", "Municipio", "Oficina", "Circuito_corto",
  "Posicion", "Direccion", "Levantado", "Turno_levantado", "Id_viaje_GOL",
  "Incidencia", "Porcentaje_llenado", "Condicion", "contenedor_activo"
)

# ── Credenciales ─────────────────────────────────────────────────────────────
# Se piden una sola vez por corrida y se usan para la intranet y el GeoServer.
# No se guardan en ningún archivo.
pedir_credenciales <- function() {
  if (!requireNamespace("rstudioapi", quietly = TRUE) || !rstudioapi::isAvailable()) {
    stop("Este script se corre desde RStudio (pide usuario y contraseña en una ventana).")
  }
  usuario <- rstudioapi::showPrompt("Acceso IMM", "Usuario de la IMM (ej: im1234567)", default = "")
  contrasena <- rstudioapi::askForPassword("Contraseña de la IMM")
  if (is.null(usuario) || is.null(contrasena) || usuario == "" || contrasena == "") {
    stop("Se necesitan usuario y contraseña de la IMM. Volvé a correr el script.")
  }
  list(usuario = usuario, contrasena = contrasena)
}

# ── Python ───────────────────────────────────────────────────────────────────
# Busca un Python que tenga Playwright: primero el entorno r-reticulate (si
# existe en esta PC), después el lanzador "py" de Windows y por último "python".
buscar_python <- function() {
  candidatos <- c(
    Sys.getenv("PYTHON_PAQUETE"),
    file.path(Sys.getenv("USERPROFILE"), ".virtualenvs", "r-reticulate", "Scripts", "python.exe"),
    Sys.which("py"),
    Sys.which("python")
  )
  candidatos <- candidatos[nzchar(candidatos) & file.exists(candidatos)]
  for (py in candidatos) {
    ok <- suppressWarnings(system2(py, c("-c", shQuote("import playwright")),
                                   stdout = FALSE, stderr = FALSE))
    if (identical(ok, 0L)) return(py)
  }
  stop(
    "No encontré Python con Playwright. Seguí la sección 1 del LEEME.md ",
    "(instalar Python y Playwright) y volvé a correr."
  )
}

# ── Paso 1: descargar los CSV de levantes (GOL) ──────────────────────────────
# Descarga un CSV por día, desde el día siguiente al último que hay en el
# histórico hasta ayer. Si un día falla, corta ahí (sin dejar huecos): lo que ya
# se descargó se usa igual y la próxima corrida sigue desde ese día.
descargar_csv_gol <- function(historico, cred, dir_descargas = "descargas") {
  ultima <- max(as.Date(historico$Fecha), na.rm = TRUE)
  if (ultima + 1 > Sys.Date() - 1) {
    message("✅ El histórico ya llega hasta ayer (", format(ultima, "%d/%m/%Y"), "). Nada para descargar.")
    return(invisible(character(0)))
  }
  fechas <- seq(ultima + 1, Sys.Date() - 1, by = "day")
  message("📅 Último día en el histórico: ", format(ultima, "%d/%m/%Y"),
          ". Días a descargar: ", length(fechas))

  python <- buscar_python()
  script <- file.path(dir_descargas, "descargar_datos_reportesGOL.py")

  # Las credenciales van por variables de entorno (no por línea de comandos).
  Sys.setenv(APEX_USUARIO = cred$usuario, APEX_CONTRASENA = cred$contrasena)
  on.exit(Sys.unsetenv(c("APEX_USUARIO", "APEX_CONTRASENA")), add = TRUE)

  descargadas <- character(0)
  for (f in as.character(fechas)) {
    message("📥 Descargando levantes del ", f, " ...")
    status <- system2(python, args = c(shQuote(script), f))
    if (!identical(status, 0L)) {
      warning("Falló la descarga del ", f, ". Se sigue con lo que ya se descargó. ",
              "Ver capturas en ", file.path(dir_descargas, "capturas"), call. = FALSE)
      break
    }
    descargadas <- c(descargadas, f)
  }
  invisible(descargadas)
}

# ── Paso 2: sumar los CSV nuevos al histórico ────────────────────────────────
# Lee un CSV de levantes y lo deja con las columnas del histórico.
# Copia de funcion_actualizar_llenadoGOL() (proyecto APP_nuevoinforme).
procesar_csv_gol <- function(ruta) {
  df <- read_delim(ruta, delim = ",", locale = locale(encoding = "UTF-8"),
                   trim_ws = TRUE, show_col_types = FALSE) %>% distinct()

  df$dia_viaje <- as.Date(df$dia_viaje, format = "%A/%m/%d")
  df$fecha_pasaje <- as.POSIXct(df$fecha_pasaje, format = "%d-%m-%Y %H:%M:%S")
  df$contenedor_gid <- as.character(df$contenedor_gid)

  df %>%
    mutate(
      condiciones_contenedor = condiciones_contenedor %>%
        str_replace_all("\\s*,\\s*", ";") %>%
        str_replace_all("\\s*;\\s*", ";") %>%
        str_replace_all(";{2,}", ";") %>%
        str_trim(),
      Municipio = circuito %>% str_trim() %>% str_to_upper() %>% str_extract("^(CH|[A-G])"),
      Oficina = ifelse(grepl("^B_0?[1-7](\\b|$)", circuito), "Fideicomiso", "IM"),
      turno = factor(turno, levels = c("Matutino", "Vespertino", "Nocturno"))
    ) %>%
    rename(
      Fecha = dia_viaje,
      Posicion = posicion,
      Direccion = ubicacion,
      Levantado = levantado,
      Turno_levantado = turno,
      Fecha_hora_pasaje = fecha_pasaje,
      Incidencia = motivo_no_levante,
      Porcentaje_llenado = porcentaje_llenado,
      Id_viaje_GOL = id_viaje,
      gid = contenedor_gid,
      Condicion = condiciones_contenedor,
      Circuito_corto = circuito
    ) %>%
    select(any_of(COLUMNAS_HISTORICO))
}

# Días de historial que se PUBLICAN (mismo corte que limpieza_datos.R). Más
# días hacen que la app se quede sin memoria en shinyapps.io (1 GB).
# En datos/ se guarda el historial completo: lo usa la app cuando se abre en
# esta PC con shiny::runApp("app").
DIAS_PUBLICADOS <- 122  # 4 meses

# Deja solo las columnas que usa la app, sin filas repetidas (todas las fechas).
seleccionar_columnas <- function(historico) {
  historico %>%
    select(any_of(COLUMNAS_HISTORICO)) %>%
    distinct()
}

# Deja solo los últimos DIAS_PUBLICADOS días y las columnas que usa la app.
recortar_historico <- function(historico) {
  historico %>%
    filter(as.Date(Fecha) >= (Sys.Date() - DIAS_PUBLICADOS)) %>%
    seleccionar_columnas()
}

# Suma al histórico todos los CSV de descargas/ que todavía no se procesaron.
actualizar_historico <- function(dir_datos = "datos", dir_descargas = "descargas") {
  ruta_hist <- file.path(dir_datos, "historico_llenado.rds")
  ruta_proc <- file.path(dir_datos, "csv_procesados.rds")

  historico  <- readRDS(ruta_hist)
  procesados <- if (file.exists(ruta_proc)) readRDS(ruta_proc) else character(0)

  csv <- list.files(file.path(dir_descargas, "GOL_reportes"),
                    pattern = "^\\d{4}-\\d{2}-\\d{2}\\.csv$", recursive = TRUE, full.names = TRUE)
  nuevos <- csv[!basename(csv) %in% procesados]
  if (length(nuevos) == 0) {
    message("☕ No hay CSV nuevos para sumar.")
    return(invisible(historico))
  }

  ok <- character(0)
  for (ruta in nuevos) {
    datos <- tryCatch(procesar_csv_gol(ruta), error = function(e) {
      warning("No se pudo leer ", basename(ruta), ": ", conditionMessage(e), call. = FALSE)
      NULL
    })
    if (is.null(datos)) next
    historico <- bind_rows(historico, datos)
    ok <- c(ok, basename(ruta))
  }

  historico <- seleccionar_columnas(historico)  # completo: se recorta al publicar
  saveRDS(historico, ruta_hist)
  saveRDS(c(procesados, ok), ruta_proc)
  message("✅ Se sumaron ", length(ok), " CSV. El histórico llega hasta el ",
          format(max(as.Date(historico$Fecha), na.rm = TRUE), "%d/%m/%Y"), ".")
  invisible(historico)
}

# ── Paso 3: contenedores activos e inactivos (GeoServer, capas DFR) ─────────
# Descarga solo las dos capas que usa la app. Si alguna falla o viene vacía,
# se deja la versión anterior.
descargar_capas_dfr <- function(cred, dir_datos = "datos",
                                url_base = "https://geoserver-ed.imm.gub.uy/geoserver/wfs") {
  capas <- c(
    GID_activos   = "dfr_E_DF_POSICIONES_RECORRIDO",
    GID_inactivos = "dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO"
  )

  resp <- httr::GET(
    url_base, httr::authenticate(cred$usuario, cred$contrasena),
    query = list(service = "WFS", version = "1.0.0", request = "GetCapabilities"),
    httr::timeout(60)
  )
  if (httr::status_code(resp) == 401) stop("GeoServer: usuario o contraseña incorrectos (401).")
  httr::stop_for_status(resp)
  doc <- xml2::read_xml(httr::content(resp, as = "text", encoding = "UTF-8"))
  nombres <- xml2::xml_text(xml2::xml_find_all(
    doc, "//*[local-name()='FeatureType']/*[local-name()='Name']"
  ))

  for (pin in names(capas)) {
    nombre <- nombres[gsub("[:/]", "_", nombres) == capas[[pin]]]
    if (length(nombre) != 1) {
      warning("No encontré la capa ", capas[[pin]], " en el GeoServer. Se deja la anterior.", call. = FALSE)
      next
    }
    message("  Descargando ", nombre, " ...")
    dsn <- paste0(
      "WFS:https://",
      URLencode(cred$usuario, reserved = TRUE), ":",
      URLencode(cred$contrasena, reserved = TRUE),
      "@geoserver-ed.imm.gub.uy/geoserver/wfs?",
      "service=WFS&version=1.0.0&request=GetFeature&typename=", nombre,
      "&srsname=EPSG:32721&outputFormat=application/json"
    )
    capa <- tryCatch(sf::st_read(dsn = dsn, quiet = TRUE), error = function(e) {
      warning("Error descargando ", nombre, ": ", conditionMessage(e), ". Se deja la anterior.", call. = FALSE)
      NULL
    })
    if (is.null(capa) || nrow(capa) == 0) next
    saveRDS(capa, file.path(dir_datos, paste0(pin, ".rds")))
    message("  ✅ ", pin, ": ", nrow(capa), " contenedores.")
  }
}

# ── Paso 4: preparar los datos para la app ──────────────────────────────────
# Escribe los 4 datos en app/data/, que es de donde los lee la app cuando esa
# carpeta existe (ver App.R). Se publican junto con la app.
escribir_datos_app <- function(dir_datos = "datos", dir_app = "app") {
  ruta_board <- file.path(dir_app, "data")
  unlink(ruta_board, recursive = TRUE, force = TRUE)
  if (dir.exists(ruta_board)) {
    stop("No se pudo borrar ", ruta_board, ". Cerrá la app si está abierta y volvé a correr.")
  }
  board <- pins::board_folder(ruta_board, versioned = FALSE)
  leer <- function(nombre) readRDS(file.path(dir_datos, paste0(nombre, ".rds")))

  pin_write(board, leer("GID_activos"),   "GID_activos",   type = "rds")
  pin_write(board, leer("GID_inactivos"), "GID_inactivos", type = "rds")
  pin_write(board, recortar_historico(leer("historico_llenado")), "historico_llenado_web", type = "rds")
  pin_write(board, leer("circuitos_periodo"), "circuitos_periodo", type = "rds")
  message("✅ Datos listos en ", ruta_board)
}
