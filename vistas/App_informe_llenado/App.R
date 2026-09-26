library(shiny)
library(bslib)
library(htmltools)
library(leaflet)
library(leaflet.extras)
library(sf)
library(pins)
library(dplyr)
library(DT)
library(jsonlite)
library(httr)

# --- DETECCIÓN DE ENTORNO Y CARGA DE DATOS ---
# En local: lee desde la carpeta "data/" (generada por limpieza_datos.R)
# En Shiny: lee directamente desde GitHub raw (sin necesidad de PAT si el repo es público)
#
# Los datos se publican en un repo de GitHub aparte (APP_nuevoinforme-data),
# no en este repo de código (ver vistas/App_informe_llenado/limpieza_datos.R).
REPO_DATOS <- "liottinicolas/APP_nuevoinforme-data"
url_github <- paste0("https://raw.githubusercontent.com/", REPO_DATOS, "/master/data/")

# Función de preprocesamiento (se define una vez al inicio, no depende de los datos)
preprocesar_datos <- function(df) {
  if (!inherits(df, "sf")) {
    df <- st_as_sf(df, wkt = "THE_GEOM", crs = 32721)
  }
  return(st_transform(df, 4326))
}

# --- INDICADORES ---
# Umbrales de la pestaña Circuitos y de la capa de color del mapa
DIAS_INDICADORES_MAPA    <- 30    # ventana de la capa de color del mapa
UMBRAL_ATRASO            <- 1.5   # días reales / planificados a partir del cual un circuito está atrasado
UMBRAL_SATURACION        <- 0.8   # contenedor crítico: lleno en al menos este % de sus levantes
UMBRAL_BASURA_AFUERA     <- 0.5   # contenedor crítico: "Basura Afuera" en al menos este % de sus levantes
MIN_LEVANTES_CRITICO     <- 5     # levantes mínimos en el período para calificar un contenedor
CONDICIONES_CONTENEDOR   <- c("Basura Afuera", "Requiere Limpieza", "Requiere Mantenimiento",
                              "Fuera de Lugar", "Dos Ciclos", "Escombro", "Poda")

# Garantiza Municipio y Oficina en el histórico. Los pines generados antes de
# que limpieza_datos.R incluyera esas columnas no las traen: se completan desde
# circuitos_periodo o, en su defecto, del prefijo del circuito (A_103 -> A).
completar_historico <- function(df, circuitos) {
  df$Fecha <- as.Date(df$Fecha)
  if (!is.null(circuitos)) {
    ref <- distinct(circuitos, Circuito_corto, .keep_all = TRUE)
    idx <- match(df$Circuito_corto, ref$Circuito_corto)
    if (!"Municipio" %in% names(df)) df$Municipio <- ref$Municipio[idx]
    if (!"Oficina" %in% names(df))   df$Oficina   <- ref$Oficina[idx]
  }
  if (!"Municipio" %in% names(df)) df$Municipio <- NA_character_
  if (!"Oficina" %in% names(df))   df$Oficina   <- NA_character_
  sin_mun <- is.na(df$Municipio)
  df$Municipio[sin_mun] <- sub("_.*$", "", df$Circuito_corto[sin_mun])
  df
}

# Días entre levantes consecutivos de cada contenedor (un levante por día).
# Cada intervalo se asigna al circuito del levante que lo cierra.
dias_entre_levantes <- function(df) {
  df %>%
    filter(Levantado %in% "S") %>%
    distinct(gid, Fecha, .keep_all = TRUE) %>%
    arrange(gid, Fecha) %>%
    group_by(gid) %>%
    mutate(dias = as.numeric(Fecha - lag(Fecha))) %>%
    ungroup() %>%
    filter(!is.na(dias)) %>%
    select(gid, Circuito_corto, Municipio, dias)
}

# Tasas de un grupo de registros. Se usa dentro de summarise().
# El llenado se mide solo en los levantes: los "N" pueden venir con 0 % cuando
# el camión no llegó a revisar el contenedor, y eso no es un llenado observado.
resumir_registros <- function(.data) {
  .data %>%
    summarise(
      programados = n(),
      levantes    = sum(Levantado %in% "S"),
      p_levantado = levantes / programados,
      p_incidencia = sum(Levantado %in% "N") / programados,
      p_no_paso   = sum(is.na(Levantado)) / programados,
      llenado     = if (levantes > 0) mean(Porcentaje_llenado[Levantado %in% "S"], na.rm = TRUE) else NA_real_,
      saturacion  = if (levantes > 0) mean(Porcentaje_llenado[Levantado %in% "S"] == 100, na.rm = TRUE) else NA_real_,
      .groups = "drop"
    )
}

# Indicadores por contenedor en los últimos `dias` días con datos (capa del mapa)
indicadores_por_gid <- function(df, dias) {
  hasta <- max(df$Fecha, na.rm = TRUE)
  df %>%
    filter(Fecha > hasta - dias) %>%
    group_by(gid) %>%
    resumir_registros()
}

indicadores_por_circuito <- function(df, circuitos) {
  frecuencia <- dias_entre_levantes(df) %>%
    group_by(Circuito_corto) %>%
    summarise(frecuencia_real = mean(dias), .groups = "drop")

  res <- df %>%
    group_by(Municipio, Circuito_corto) %>%
    resumir_registros() %>%
    left_join(frecuencia, by = "Circuito_corto")

  if (!is.null(circuitos)) {
    plan <- circuitos %>%
      distinct(Circuito_corto, .keep_all = TRUE) %>%
      select(Circuito_corto, Oficina, Dias_recoleccion, Turno, Periodo)
    res <- left_join(res, plan, by = "Circuito_corto")
  } else {
    res <- mutate(res, Oficina = NA_character_, Dias_recoleccion = NA_character_,
                  Turno = NA_character_, Periodo = NA_real_)
  }
  res %>% mutate(atraso = frecuencia_real / Periodo)
}

indicadores_por_municipio <- function(df, por_circuito) {
  frecuencia <- dias_entre_levantes(df) %>%
    group_by(Municipio) %>%
    summarise(frecuencia_real = mean(dias), .groups = "drop")
  atrasados <- por_circuito %>%
    group_by(Municipio) %>%
    summarise(
      circuitos = n(),
      # Sin plan publicado no se puede saber: vacío en vez de 0
      atrasados = if (all(is.na(atraso))) NA_integer_ else sum(atraso > UMBRAL_ATRASO, na.rm = TRUE),
      .groups = "drop"
    )
  df %>%
    group_by(Municipio) %>%
    resumir_registros() %>%
    left_join(frecuencia, by = "Municipio") %>%
    left_join(atrasados, by = "Municipio")
}

# Contenedores que casi siempre están llenos o con basura afuera
contenedores_criticos <- function(df) {
  ultimo <- df %>%
    arrange(desc(Fecha)) %>%
    distinct(gid, .keep_all = TRUE) %>%
    select(gid, Municipio, Circuito_corto, Direccion)
  basura <- df %>%
    filter(Levantado %in% "S") %>%
    group_by(gid) %>%
    summarise(p_basura = mean(grepl("Basura Afuera", Condicion, fixed = TRUE)), .groups = "drop")

  df %>%
    group_by(gid) %>%
    resumir_registros() %>%
    left_join(basura, by = "gid") %>%
    filter(
      levantes >= MIN_LEVANTES_CRITICO,
      saturacion >= UMBRAL_SATURACION | p_basura >= UMBRAL_BASURA_AFUERA
    ) %>%
    left_join(ultimo, by = "gid") %>%
    arrange(desc(saturacion), desc(p_basura))
}

# Inicialización de la placa de datos (global)
if (dir.exists("data")) {
  global_board <- pins::board_folder("data", versioned = FALSE)
} else {
  # board_url() con una única URL base lee el manifest (_pins.yaml, generado
  # por write_board_manifest() en limpieza_datos.R) para resolver la
  # subcarpeta de versión vigente de cada pin. Una URL fija por pin no
  # funciona porque esa subcarpeta cambia de hash en cada corrida.
  global_board <- pins::board_url(url_github)
}

# Intervalo de recarga automática (10 minutos * 60 segundos * 1000 milisegundos)
INTERVALO_RECARGA_MS <- 10 * 60 * 1000

# Carga de datos compartida y optimizada mediante reactivePoll.
# Se evalúa en el inicio de la app y luego busca actualizaciones cada 10 minutos.
# checkFunc utiliza la API ligera de GitHub (con un timeout corto) en producción,
# lo que evita recargas y cálculos innecesarios del st_transform si los datos no cambiaron.
datos_compartidos <- reactivePoll(
  intervalMillis = INTERVALO_RECARGA_MS,
  session = NULL,
  checkFunc = function() {
    if (dir.exists("data")) {
      files <- list.files("data", recursive = TRUE, full.names = TRUE)
      if (length(files) > 0) {
        return(max(file.info(files)$mtime, na.rm = TRUE))
      }
      return(Sys.time())
    } else {
      # Comprobación ligera del último commit en GitHub
      tryCatch({
        url_commit <- paste0("https://api.github.com/repos/", REPO_DATOS, "/commits/master")
        req <- httr::GET(
          url_commit,
          httr::timeout(3),
          httr::user_agent("ShinyApp-Nicolas")
        )
        if (httr::status_code(req) == 200) {
          content <- httr::content(req, as = "text", encoding = "UTF-8")
          commit_data <- jsonlite::fromJSON(content)
          return(commit_data$sha)
        }
      }, error = function(e) {
        # Fallback si no hay conexión o API límite
        return(floor(as.numeric(Sys.time()) / 3600))
      })
      return(floor(as.numeric(Sys.time()) / 3600))
    }
  },
  valueFunc = function() {
    message("🔄 [Carga Global] Descargando y preprocesando datos (pins + st_transform)...")

    if (dir.exists("data")) {
      current_board <- global_board
    } else {
      current_board <- pins::board_url(url_github)
    }

    # circuitos_periodo es opcional: si todavía no se publicó el pin, la app
    # funciona igual, solo sin la frecuencia planificada de cada circuito.
    circuitos <- tryCatch(
      pin_read(current_board, "circuitos_periodo"),
      error = function(e) {
        message("⚠️ No se pudo leer el pin circuitos_periodo: ", conditionMessage(e))
        NULL
      }
    )
    historico <- completar_historico(pin_read(current_board, "historico_llenado_web"), circuitos)

    list(
      activos           = preprocesar_datos(pin_read(current_board, "GID_activos")),
      inactivos         = preprocesar_datos(pin_read(current_board, "GID_inactivos")),
      historico_llenado = historico,
      circuitos         = circuitos,
      indicadores_mapa  = indicadores_por_gid(historico, DIAS_INDICADORES_MAPA)
    )
  }
)

lat_mvd <- -34.8636
lng_mvd <- -56.1679

# --- PALETA ---
# Cada color significa lo mismo en el mapa, la línea de tiempo, el resumen y la tabla.
COL_TINTA        <- "#1D2A28"
COL_LEVANTADO    <- "#2E6A4E"  # el camión levantó / contenedor activo
COL_INCIDENCIA   <- "#B63A3A"  # pasó pero no levantó (Levantado = "N")
COL_SIN_REGISTRO <- "#8C9592"  # programado, el camión no pasó (Levantado = NA)
COL_LLENO        <- "#D9A21F"  # llenado al 100%

# Capa de color del mapa: cada rampa se ancla en el color de su significado
# (ámbar = lleno, gris = el camión no pasó). Cortes en % de 0 a 100.
CORTES_MAPA <- c(0, 20, 40, 60, 80, 100)
RAMPA_SATURACION <- c("#F4E7C2", "#E9C96E", "#D9A21F", "#A87400", "#6B4A00")
RAMPA_NO_PASO    <- c("#E4E7E6", "#BAC1BE", "#8C9592", "#5E6A67", "#2F3836")
COL_SIN_DATOS    <- "#FFFFFF"

MESES_ES <- c("Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
              "Agosto", "Setiembre", "Octubre", "Noviembre", "Diciembre")

# Hasta cuántos días la línea de tiempo muestra la fecha de cada barra (≈ 3 meses)
DIAS_MAX_EJE_DIARIO <- 100

# --- HELPERS DE FORMATO ---
fmt_num <- function(x, digitos = 1) {
  format(round(x, digitos), decimal.mark = ",", big.mark = ".", nsmall = 0, trim = TRUE)
}
fmt_fecha <- function(x) format(as.Date(x), "%d/%m/%Y")
# Proporción (0-1) como porcentaje; vectorizado, NA -> "Sin datos"
fmt_pct <- function(x) ifelse(is.na(x), "Sin datos", paste0(fmt_num(100 * x, 0), "%"))
fmt_pct_levantes <- function(x, n) {
  ifelse(is.na(x) | n == 0, "Sin levantes", paste0(fmt_pct(x), " de ", n, " levantes"))
}
esc <- function(x) htmlEscape(ifelse(is.na(x), "", as.character(x)))

# Popup de un contenedor en el mapa (vectorizado sobre las filas de df)
popup_contenedor <- function(df, activo) {
  fila <- function(etiqueta, valor) {
    paste0("<dt>", etiqueta, "</dt><dd>", esc(valor), "</dd>")
  }
  direccion <- if ("DIRECCION" %in% names(df)) df$DIRECCION else NA
  detalle <- if (activo) {
    paste0(
      fila("Dirección", direccion),
      fila("Circuito", df$COD_RECORRIDO),
      fila("Posición", df$POSICION),
      fila("En servicio desde", fmt_fecha(df$FECHA_DESDE)),
      if ("saturacion" %in% names(df)) {
        paste0(
          fila(paste0("Lleno (", DIAS_INDICADORES_MAPA, " días)"), fmt_pct_levantes(df$saturacion, df$levantes)),
          fila(paste0("No pasó (", DIAS_INDICADORES_MAPA, " días)"), fmt_pct(df$p_no_paso))
        )
      } else ""
    )
  } else {
    paste0(
      if (!all(is.na(direccion))) fila("Dirección", direccion) else "",
      fila("Último circuito", df$COD_RECORRIDO),
      fila("Retirado el", fmt_fecha(df$FECHA_HASTA))
    )
  }
  gid <- esc(df$GID)
  paste0(
    "<div class='pop'>",
    "<div class='pop-cabecera'><span class='pop-gid'>GID ", gid, "</span>",
    "<span class='estado ", if (activo) "estado-activo'>Activo" else "estado-inactivo'>Inactivo", "</span></div>",
    "<dl>", detalle, "</dl>",
    "<button class='btn btn-sm btn-primary pop-btn' ",
    "onclick='Shiny.setInputValue(\"ver_historial_gid\", \"", gid, "\", {priority: \"event\"})'>",
    "Ver historial</button>",
    "</div>"
  )
}

# Línea de tiempo: una columna por día del rango. Altura = % de llenado,
# color = qué pasó ese día. Días sin barra = no estaba programado.
linea_tiempo <- function(df, desde, hasta) {
  dias <- seq(desde, hasta, by = "day")

  por_dia <- df %>%
    mutate(
      dia = as.Date(Fecha),
      # Solo los levantes miden llenado (un "N" puede venir con 0 % sin que nadie lo haya visto)
      pct = ifelse(Levantado %in% "S", suppressWarnings(as.numeric(Porcentaje_llenado)), NA_real_)
    ) %>%
    group_by(dia) %>%
    summarise(
      estado = case_when(
        any(Levantado == "S", na.rm = TRUE) ~ "levantado",
        any(Levantado == "N", na.rm = TRUE) ~ "incidencia",
        TRUE                                ~ "nopaso"
      ),
      pct = if (all(is.na(pct))) NA_real_ else max(pct, na.rm = TRUE),
      turno = paste(unique(na.omit(Turno_levantado[Turno_levantado != ""])), collapse = ", "),
      incidencia = paste(unique(na.omit(Incidencia[Incidencia != ""])), collapse = ", "),
      .groups = "drop"
    )

  texto_estado <- c(
    levantado  = "Levantado",
    incidencia = "No levantado, con incidencia",
    nopaso     = "El camión no pasó"
  )

  idx <- match(dias, por_dia$dia)
  barras <- lapply(seq_along(dias), function(i) {
    fecha_txt <- fmt_fecha(dias[i])
    if (is.na(idx[i])) {
      return(div(class = "dia dia-vacio", title = paste0(fecha_txt, "\nNo estaba programado")))
    }
    d <- por_dia[idx[i], ]
    sin_dato <- is.na(d$pct)
    tooltip <- paste0(
      fecha_txt, "\n", texto_estado[[d$estado]],
      if (!sin_dato) paste0("\nLlenado: ", fmt_num(d$pct, 0), "%") else "\nSin dato de llenado",
      if (nzchar(d$turno)) paste0("\nTurno: ", d$turno) else "",
      if (nzchar(d$incidencia)) paste0("\nIncidencia: ", d$incidencia) else ""
    )
    div(
      class = paste(
        "dia", paste0("dia-", d$estado),
        if (sin_dato) "dia-sin-dato",
        if (!sin_dato && d$pct >= 100) "dia-lleno"
      ),
      title = tooltip,
      div(
        class = "barra",
        style = sprintf("height:%s%%; --i:%d", if (sin_dato) 100 else max(d$pct, 3), i)
      )
    )
  })

  # Eje de fechas: hasta ~3 meses, la fecha de cada día en vertical (dd/mm/aa);
  # en períodos más largos, el nombre del mes en horizontal al inicio de cada mes.
  modo_diario <- length(dias) <= DIAS_MAX_EJE_DIARIO
  etiquetas <- if (modo_diario) {
    lapply(seq_along(dias), function(i) {
      span(style = sprintf("grid-column:%d", i), format(dias[i], "%d/%m/%y"))
    })
  } else {
    # El primer día del rango también lleva etiqueta, salvo que el mes
    # siguiente empiece enseguida (se pisarían).
    pos_meses <- which(format(dias, "%d") == "01")
    if (length(pos_meses) == 0 || pos_meses[1] > 10) pos_meses <- c(1, pos_meses)
    # Cada etiqueta ocupa las columnas de su mes; si el mes tiene pocos días
    # dentro del período, el nombre se abrevia para que no se corte.
    fin <- c(pos_meses[-1], length(dias) + 1)
    lapply(seq_along(pos_meses), function(k) {
      p <- pos_meses[k]
      mes <- MESES_ES[as.integer(format(dias[p], "%m"))]
      if (fin[k] - p < 25) mes <- paste0(substr(mes, 1, 3), ".")
      span(style = sprintf("grid-column:%d / %d", p, fin[k]), paste(mes, format(dias[p], "%Y")))
    })
  }

  div(
    class = "lt-scroll",
    div(
      class = paste("linea-tiempo", if (modo_diario) "lt-diario"),
      style = sprintf("--dias:%d", length(dias)),
      div(class = "lt-barras", barras),
      div(class = "lt-meses", etiquetas)
    )
  )
}

leyenda_linea_tiempo <- tags$ul(
  class = "leyenda",
  tags$li(span(class = "muestra muestra-levantado"), "Levantado"),
  tags$li(span(class = "muestra muestra-incidencia"), "No levantado, con incidencia"),
  tags$li(span(class = "muestra muestra-nopaso"), "El camión no pasó"),
  tags$li(span(class = "muestra muestra-lleno"), "Lleno (100%)"),
  tags$li(span(class = "muestra muestra-vacio"), "Sin barra: no estaba programado")
)

# --- TEMA ---
tema <- bs_theme(
  version = 5,
  preset = "bootstrap",
  bg = "#F6F7F5",
  fg = COL_TINTA,
  primary = COL_LEVANTADO,
  danger = COL_INCIDENCIA,
  warning = COL_LLENO,
  secondary = "#5E6A67",
  base_font = font_link(
    "Barlow",
    href = "https://fonts.googleapis.com/css2?family=Barlow:wght@400;500;600&family=Barlow+Semi+Condensed:wght@500;600;700&display=swap"
  ),
  heading_font = font_collection("Barlow Semi Condensed", "Barlow", "system-ui", "sans-serif"),
  "font-size-base" = "0.95rem",
  "border-radius" = "6px",
  "border-radius-sm" = "4px",
  "border-radius-lg" = "8px"
)

estilos <- tags$style(HTML("
  :root {
    --papel: #F6F7F5;
    --superficie: #FFFFFF;
    --tinta: #1D2A28;
    --tinta-suave: #5E6A67;
    --linea: #DDE2DF;
    --levantado: #2E6A4E;
    --incidencia: #B63A3A;
    --sin-registro: #8C9592;
    --lleno: #D9A21F;
    --condensada: 'Barlow Semi Condensed', 'Barlow', system-ui, sans-serif;
  }
  body { background: var(--papel); color: var(--tinta); }
  :focus-visible { outline: 2px solid var(--levantado); outline-offset: 2px; }

  /* Barra superior */
  .navbar { background: var(--superficie) !important; border-bottom: 1px solid var(--linea); }
  .navbar-brand { font-family: var(--condensada); font-weight: 700; font-size: 1.2rem; color: var(--tinta) !important; }
  .navbar .nav-link { color: var(--tinta-suave) !important; font-weight: 500; }
  .navbar .nav-link:hover { color: var(--tinta) !important; }
  .navbar .nav-link.active { color: var(--tinta) !important; box-shadow: inset 0 -2px 0 var(--levantado); }
  .fecha-datos { color: var(--tinta-suave); font-size: 0.875rem; white-space: nowrap; padding-right: 1rem; }
  .fecha-datos strong { color: var(--tinta); font-weight: 600; }

  /* Controles */
  .form-label, .control-label { font-weight: 600; font-size: 0.875rem; color: var(--tinta); margin-bottom: 0.3rem; }
  .form-control { background: var(--superficie); border-color: var(--linea); }
  .form-group { margin-bottom: 0; }
  .input-daterange .input-group-addon, .input-daterange .input-group-text { background: transparent; border-color: var(--linea); color: var(--tinta-suave); }
  .input-daterange input { text-align: left; }

  /* ---------- Mapa ---------- */
  .mapa-wrap { position: relative; height: calc(100vh - 7rem); min-height: 480px;
               border: 1px solid var(--linea); border-radius: 8px; overflow: hidden; }
  #map { height: 100% !important; }
  .mapa-panel { position: absolute; top: 12px; right: 12px; z-index: 1000; width: 21rem;
                display: flex; flex-direction: column; gap: 0.9rem;
                background: var(--superficie); border: 1px solid var(--linea); border-radius: 8px;
                padding: 1rem; box-shadow: 0 2px 10px rgba(29, 42, 40, 0.12); }
  .buscador { display: flex; gap: 6px; align-items: flex-end; }
  .buscador .form-group { flex: 1; }
  .buscador .shiny-input-container { width: 100% !important; }
  .mapa-panel .checkbox { margin: 0; }
  .mapa-panel .checkbox label { font-size: 0.875rem; }
  .ayuda { color: var(--tinta-suave); font-size: 0.8rem; margin-top: 0.3rem; }

  /* Selector Activos / Inactivos como control segmentado */
  #seleccion_estado .shiny-options-group { display: flex; border: 1px solid var(--linea); border-radius: 6px; overflow: hidden; }
  #seleccion_estado label.radio-inline { flex: 1; margin: 0; padding: 0; position: relative; }
  #seleccion_estado input { position: absolute; opacity: 0; pointer-events: none; }
  #seleccion_estado span { display: block; text-align: center; padding: 0.4rem 0.5rem; cursor: pointer; font-weight: 500; }
  #seleccion_estado input:checked + span { background: var(--tinta); color: #fff; }
  #seleccion_estado input:focus-visible + span { outline: 2px solid var(--levantado); outline-offset: -2px; }

  /* Clusters del mapa en la paleta de la app */
  .marker-cluster-small, .marker-cluster-medium, .marker-cluster-large { background-color: rgba(46, 106, 78, 0.22) !important; }
  .marker-cluster div { background-color: var(--levantado) !important; color: #fff !important;
                        font-family: var(--condensada); font-weight: 600; }

  /* Popups */
  .leaflet-container { font-family: inherit; }
  .leaflet-popup-content-wrapper { border-radius: 8px; }
  .leaflet-popup-content { margin: 0.9rem 1rem; }
  .pop { min-width: 210px; font-size: 0.875rem; color: var(--tinta); }
  .pop-cabecera { display: flex; justify-content: space-between; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem; }
  .pop-gid { font-family: var(--condensada); font-weight: 700; font-size: 1.25rem; }
  .pop dl { display: grid; grid-template-columns: auto 1fr; gap: 0.15rem 0.75rem; margin: 0 0 0.75rem; }
  .pop dt { font-weight: 500; color: var(--tinta-suave); }
  .pop dd { margin: 0; }
  .pop-btn { width: 100%; }

  /* Estado activo / inactivo */
  .estado { display: inline-block; font-size: 0.8rem; font-weight: 600; line-height: 1.2;
            padding: 0.15rem 0.55rem; border-radius: 999px; border: 1.5px solid currentColor; white-space: nowrap; }
  .estado-activo { color: var(--levantado); }
  .estado-inactivo { color: var(--tinta-suave); }

  /* ---------- Historial ---------- */
  .historial { max-width: 1680px; margin: 0 auto; padding: 0 0.5rem 3rem; }
  .controles { display: flex; flex-wrap: wrap; gap: 1rem 1.5rem; align-items: flex-end;
               padding: 0.5rem 0 1.25rem; border-bottom: 1px solid var(--linea); margin-bottom: 1.75rem; }
  #busqueda_gid { width: 11rem; font-family: var(--condensada); font-size: 1.15rem; font-weight: 600; }

  .ficha-cabecera { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem 1rem; }
  .ficha-gid { font-family: var(--condensada); font-weight: 700; font-size: clamp(2.2rem, 5vw, 3.25rem);
               line-height: 1; margin: 0; font-variant-numeric: tabular-nums; }
  .ficha-gid span { font-size: 0.45em; font-weight: 600; color: var(--tinta-suave); margin-right: 0.3em; }
  .ficha-datos { display: flex; flex-wrap: wrap; gap: 0.75rem 2.25rem; margin: 1rem 0 0; }
  .ficha-datos dt { font-size: 0.8rem; font-weight: 500; color: var(--tinta-suave); }
  .ficha-datos dd { margin: 0; font-weight: 600; }

  .seccion { margin-top: 2.25rem; }
  .seccion-titulo { font-size: 1.15rem; font-weight: 600; margin-bottom: 0.9rem; }

  /* Línea de tiempo */
  .lt-scroll { overflow-x: auto; padding-bottom: 0.25rem; }
  /* Períodos largos: barras finas para que un año entero entre en pantalla */
  .lt-barras, .lt-meses { display: grid; grid-template-columns: repeat(var(--dias), minmax(2px, 1fr));
                          column-gap: 1px; min-width: calc(var(--dias) * 3px); }
  .lt-barras { height: 170px; align-items: end; border-bottom: 1px solid var(--tinta);
               background:
                 linear-gradient(var(--linea), var(--linea)) 0 0 / 100% 1px no-repeat,
                 linear-gradient(var(--linea), var(--linea)) 0 50% / 100% 1px no-repeat; }
  .dia { height: 100%; display: flex; align-items: flex-end; }
  .dia-levantado  { color: var(--levantado); }
  .dia-incidencia { color: var(--incidencia); }
  .dia-nopaso     { color: var(--sin-registro); }
  .barra { width: 100%; background: currentColor; border-radius: 2px 2px 0 0;
           transform-origin: bottom; animation: crecer 0.45s ease-out both; animation-delay: calc(var(--i) * 3ms); }
  .dia-sin-dato .barra { background: repeating-linear-gradient(135deg, currentColor 0 1.5px, transparent 1.5px 5px); opacity: 0.75; }
  .dia-lleno .barra { box-shadow: inset 0 4px 0 var(--lleno); }
  .dia:hover .barra { opacity: 0.7; }
  .lt-meses { margin-top: 0.35rem; font-size: 0.8rem; color: var(--tinta-suave); }
  .lt-meses span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  /* Eje diario: columnas más anchas para que entre la fecha vertical de cada día */
  .lt-diario .lt-barras, .lt-diario .lt-meses { grid-template-columns: repeat(var(--dias), minmax(12px, 1fr));
                                                column-gap: 2px; min-width: calc(var(--dias) * 14px); }
  .lt-diario .lt-meses span { writing-mode: vertical-rl; transform: rotate(180deg); justify-self: center;
                              font-size: 0.72rem; line-height: 1; font-variant-numeric: tabular-nums; }
  @keyframes crecer { from { transform: scaleY(0); } }
  @media (prefers-reduced-motion: reduce) { .barra { animation: none; } }

  .leyenda { display: flex; flex-wrap: wrap; gap: 0.4rem 1.5rem; list-style: none; padding: 0;
             margin: 0.9rem 0 0; font-size: 0.85rem; color: var(--tinta-suave); }
  .leyenda li { display: flex; align-items: center; gap: 0.4rem; }
  .muestra { display: inline-block; width: 11px; height: 11px; border-radius: 2px; flex: none; }
  .muestra-levantado  { background: var(--levantado); }
  .muestra-incidencia { background: var(--incidencia); }
  .muestra-nopaso     { background: repeating-linear-gradient(135deg, var(--sin-registro) 0 2px, transparent 2px 4px);
                        box-shadow: inset 0 0 0 1px var(--sin-registro); }
  .muestra-lleno      { background: var(--lleno); height: 4px; }
  .muestra-vacio      { border-bottom: 1px solid var(--tinta); border-radius: 0; height: 6px; }

  /* Resumen del período */
  .resumen { display: grid; grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr)); gap: 1.5rem 2rem; }
  .dato-valor { display: flex; align-items: center; gap: 0.45rem; font-family: var(--condensada);
                font-weight: 700; font-size: 2rem; line-height: 1.1; font-variant-numeric: tabular-nums; }
  .dato-valor .muestra { width: 10px; height: 10px; }
  .dato-texto { margin: 0.25rem 0 0; font-size: 0.875rem; line-height: 1.4; color: var(--tinta-suave); max-width: 24ch; }

  /* Mensajes vacíos */
  .vacio { padding: 2.5rem 0; max-width: 36rem; }
  .vacio h2 { font-size: 1.5rem; font-weight: 600; margin-bottom: 0.4rem; }
  .vacio p { color: var(--tinta-suave); margin: 0; }

  /* Tabla de registros */
  .tabla-registros { background: var(--superficie); border: 1px solid var(--linea); border-radius: 8px; padding: 1rem; }
  .tabla-registros table.dataTable { font-size: 0.875rem; font-variant-numeric: tabular-nums; }
  .tabla-registros table.dataTable thead th { font-weight: 600; color: var(--tinta-suave); border-bottom: 1px solid var(--tinta) !important; white-space: nowrap; }
  .tabla-registros table.dataTable tbody td { border-top: 1px solid var(--linea); white-space: nowrap; }
  /* Columnas de texto largo (Dirección, Incidencia, Condición): pueden partirse en dos líneas */
  .tabla-registros table.dataTable tbody td.col-texto { white-space: normal; min-width: 6rem; }
  .tabla-registros table.dataTable tbody td.col-direccion { white-space: normal; min-width: 11rem; }
  .tabla-registros table.dataTable.compact thead th,
  .tabla-registros table.dataTable.compact tbody td { padding-left: 0.5rem; padding-right: 0.5rem; }
  .dataTables_wrapper .dataTables_info, .dataTables_wrapper .dataTables_length,
  .dataTables_wrapper .dataTables_filter { color: var(--tinta-suave); font-size: 0.85rem; }
  .dataTables_wrapper .page-link { color: var(--tinta); border-color: var(--linea); }
  .dataTables_wrapper .page-item.active .page-link { background: var(--tinta); border-color: var(--tinta); color: #fff; }
  .dataTables_wrapper .page-item.disabled .page-link { background: transparent; color: var(--tinta-suave); }

  /* Valor de texto (ej. motivo de incidencia): más chico que un número */
  .dato-valor-texto { font-size: 1.2rem; line-height: 1.2; align-items: flex-start; }
  .seccion-nota { color: var(--tinta-suave); font-size: 0.875rem; margin: -0.5rem 0 0.9rem; max-width: 70ch; }

  /* Estado del contenedor: % de levantes con cada observación */
  .condiciones { display: grid; grid-template-columns: max-content minmax(6rem, 22rem) max-content;
                 gap: 0.45rem 1rem; align-items: center; font-size: 0.875rem; }
  .cond-barra { height: 10px; background: var(--linea); border-radius: 2px; overflow: hidden; }
  .cond-barra span { display: block; height: 100%; background: var(--tinta-suave); border-radius: 2px; }
  .cond-valor { font-variant-numeric: tabular-nums; color: var(--tinta-suave); }
  .cond-valor strong { color: var(--tinta); font-weight: 600; }

  /* Leyenda de la capa de color del mapa */
  .leaflet-control.info.legend { font-family: inherit; font-size: 0.8rem; color: var(--tinta);
                                 border: 1px solid var(--linea); border-radius: 8px; box-shadow: none; }

  /* Filas clicables (contenedores críticos) */
  .tabla-clicable table.dataTable tbody tr { cursor: pointer; }

  /* Pantallas chicas: el panel del mapa pasa arriba del mapa */
  @media (max-width: 640px) {
    .mapa-wrap { display: flex; flex-direction: column; height: auto; border: none; border-radius: 0; overflow: visible; }
    .mapa-panel { position: static; order: -1; width: auto; box-shadow: none; margin-bottom: 0.75rem; }
    #map { height: 65vh !important; border: 1px solid var(--linea); border-radius: 8px; }
    .condiciones { grid-template-columns: 1fr max-content; }
    .cond-barra { display: none; }
  }
"))

# Enter en el buscador del mapa = click en Buscar
script_enter <- tags$script(HTML("
  $(document).on('keydown', '#busqueda_mapa', function(e) {
    if (e.key === 'Enter') { $('#btn_buscar').click(); }
  });
  // Al cambiar de pestaña, arrancar desde arriba (sino se hereda el scroll de la anterior)
  $(document).on('shown.bs.tab', function() { window.scrollTo(0, 0); });
"))

ui <- page_navbar(
  title = "Gestión de GIDs",
  window_title = "Gestión de GIDs - Montevideo",
  id = "menu_tabs",
  theme = tema,
  fillable = FALSE,
  header = tagList(estilos, script_enter),

  nav_panel(
    "Mapa", value = "mapa",
    div(
      class = "mapa-wrap",
      leafletOutput("map", height = "100%"),
      div(
        class = "mapa-panel",
        div(
          div(
            class = "buscador",
            textInput("busqueda_mapa", "Buscar", placeholder = "GID o dirección"),
            actionButton("btn_buscar", "Buscar", class = "btn-primary")
          ),
          div(class = "ayuda", "Un número busca el GID. Un texto busca la dirección en Montevideo.")
        ),
        radioButtons(
          "seleccion_estado", "Mostrar contenedores",
          choices = c("Activos" = "act", "Inactivos" = "inact"),
          inline = TRUE
        ),
        conditionalPanel(
          "input.seleccion_estado == 'act'",
          selectInput(
            "color_mapa", "Color de los puntos",
            choices = c(
              "Contenedor activo"                                     = "estado",
              "Lleno al levantar (% de levantes, últimos 30 días)"    = "saturacion",
              "El camión no pasó (% de programados, últimos 30 días)" = "no_paso"
            )
          )
        ),
        checkboxInput("usar_clustering", "Agrupar puntos cercanos", value = TRUE)
      )
    )
  ),

  nav_panel(
    "Historial", value = "hist",
    div(
      class = "historial",
      div(
        class = "controles",
        textInput("busqueda_gid", "GID", placeholder = "Ej: 100299"),
        dateRangeInput(
          "rango_fechas_historico",
          "Período",
          start = Sys.Date() - 90,
          end = Sys.Date(),
          max = Sys.Date(),
          format = "dd/mm/yyyy",
          separator = "a",
          language = "es"
        )
      ),
      uiOutput("ficha_historial"),
      conditionalPanel(
        "output.hay_registros",
        div(
          class = "seccion",
          h2(class = "seccion-titulo", "Registros"),
          div(class = "tabla-registros", DTOutput("tabla_historico"))
        )
      )
    )
  ),

  nav_panel(
    "Circuitos", value = "circ",
    div(
      class = "historial",
      div(
        class = "controles",
        dateRangeInput(
          "rango_fechas_circuitos",
          "Período",
          start = Sys.Date() - 30,
          end = Sys.Date(),
          max = Sys.Date(),
          format = "dd/mm/yyyy",
          separator = "a",
          language = "es"
        ),
        selectInput("municipio_circuitos", "Municipio", choices = c("Todos" = ""))
      ),
      uiOutput("aviso_circuitos"),
      div(
        class = "seccion",
        h2(class = "seccion-titulo", "Por municipio"),
        div(class = "tabla-registros", DTOutput("tabla_municipios"))
      ),
      div(
        class = "seccion",
        h2(class = "seccion-titulo", "Por circuito"),
        p(class = "seccion-nota", paste0(
          "Ordenado por atraso: días reales entre levantes dividido los días planificados. ",
          "Más de ", fmt_num(UMBRAL_ATRASO), " se marca en rojo."
        )),
        div(class = "tabla-registros", DTOutput("tabla_circuitos"))
      ),
      div(
        class = "seccion",
        h2(class = "seccion-titulo", "Contenedores críticos"),
        p(class = "seccion-nota", paste0(
          "Con al menos ", MIN_LEVANTES_CRITICO, " levantes en el período, y lleno en el ",
          fmt_num(100 * UMBRAL_SATURACION, 0), "% o más de ellos, o con basura afuera en el ",
          fmt_num(100 * UMBRAL_BASURA_AFUERA, 0), "% o más. Tocá una fila para ver su historial."
        )),
        div(class = "tabla-registros tabla-clicable", DTOutput("tabla_criticos"))
      )
    )
  ),

  nav_spacer(),
  nav_item(span(class = "fecha-datos", textOutput("fecha_actualizacion", inline = TRUE)))
)

server <- function(input, output, session) {

  # datos() ahora lee de los datos compartidos globales (cargados una sola vez)
  datos <- reactive({
    datos_compartidos()
  })

  # Fecha máxima dinámica: se actualiza cuando datos() cambia
  output$fecha_actualizacion <- renderText({
    req(datos())
    fecha <- fmt_fecha(max(as.Date(datos()$historico_llenado$Fecha), na.rm = TRUE))
    paste0("Datos al ", fecha)
  })

  # --- Lógica del Mapa (Inicialización Base) ---
  # El mapa base se renderiza una sola vez. Los marcadores se agregan dinámicamente con leafletProxy.
  # Esto previene que el zoom del mapa se resetee cuando cambian los datos o filtros.
  output$map <- renderLeaflet({
    # Tiles de CARTO (basemap "voyager"): mapa claro y mucho más liviano que
    # OpenStreetMap. Requiere API key de CARTO. maxZoom = 19 es el nivel de
    # detalle nativo máximo de estos tiles; pedir más generaría tiles vacíos/rotos.
    carto_key <- "cb1_2v24_1_3157bbb3b317c6d177c4d450"
    leaflet(options = leafletOptions(maxZoom = 19)) %>%
      addTiles(
        urlTemplate = paste0(
          "https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=",
          carto_key
        ),
        attribution = paste(
          '&copy; <a href="https://carto.com/attributions">CARTO</a>',
          '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        ),
        options = tileOptions(maxZoom = 19)
      ) %>%
      setView(lng = lng_mvd, lat = lat_mvd, zoom = 12)
  })

  # Activos con los indicadores de los últimos DIAS_INDICADORES_MAPA días
  # (para colorear el mapa y completar el popup)
  activos_con_indicadores <- reactive({
    ind <- datos()$indicadores_mapa
    df <- datos()$activos
    idx <- match(as.character(df$GID), as.character(ind$gid))
    df$levantes   <- ifelse(is.na(idx), 0L, ind$levantes[idx])
    df$saturacion <- ind$saturacion[idx]
    df$p_no_paso  <- ind$p_no_paso[idx]
    df
  })

  # Actualización dinámica de marcadores mediante leafletProxy
  observe({
    req(datos())
    proxy <- leafletProxy("map")

    # Limpiamos grupos anteriores
    proxy %>% clearGroup("activos") %>% clearGroup("inactivos")

    # Configuración de clustering según checkbox de la UI.
    # disableClusteringAtZoom: a partir de ese nivel de zoom los clusters se
    # deshacen del todo y quedan los puntos individuales clickeables (sin esto,
    # el círculo con el número puede seguir tapando el click a un GID puntual).
    cluster_opts <- if (input$usar_clustering) {
      markerClusterOptions(disableClusteringAtZoom = 17)
    } else {
      NULL
    }

    # Activos: punto lleno verde. Inactivos: punto hueco (retirado).
    proxy %>% removeControl("leyenda_color")

    if (input$seleccion_estado == "act") {
      df <- activos_con_indicadores()
      modo <- input$color_mapa
      if (is.null(modo) || modo == "estado") {
        relleno <- COL_LEVANTADO
        borde <- COL_LEVANTADO
      } else {
        valor <- if (modo == "saturacion") df$saturacion else df$p_no_paso
        rampa <- if (modo == "saturacion") RAMPA_SATURACION else RAMPA_NO_PASO
        pal <- colorBin(rampa, domain = c(0, 100), bins = CORTES_MAPA, na.color = COL_SIN_DATOS)
        relleno <- pal(100 * valor)
        borde <- COL_TINTA
        proxy %>%
          addLegend(
            position = "bottomleft",
            layerId = "leyenda_color",
            colors = c(rampa, COL_SIN_DATOS),
            labels = c(paste0(head(CORTES_MAPA, -1), "–", CORTES_MAPA[-1], "%"),
                       if (modo == "saturacion") "Sin levantes" else "Sin programación"),
            title = if (modo == "saturacion") "Lleno al levantar" else "El camión no pasó",
            opacity = 1
          )
      }
      proxy %>%
        addCircleMarkers(
          data = df,
          group = "activos",
          radius = 5,
          color = borde,
          weight = 1,
          opacity = 0.9,
          fillColor = relleno,
          fillOpacity = if (identical(relleno, COL_LEVANTADO)) 0.7 else 0.85,
          popup = popup_contenedor(df, activo = TRUE),
          label = ~as.character(GID),
          layerId = ~as.character(GID),
          clusterOptions = cluster_opts
        )
    } else {
      df <- datos()$inactivos
      proxy %>%
        addCircleMarkers(
          data = df,
          group = "inactivos",
          radius = 5,
          color = COL_TINTA,
          weight = 1.5,
          opacity = 0.9,
          fillColor = "#FFFFFF",
          fillOpacity = 0.9,
          popup = popup_contenedor(df, activo = FALSE),
          label = ~as.character(GID),
          layerId = ~as.character(GID),
          clusterOptions = cluster_opts
        )
    }
  })

  # Redirección cruzada: al hacer click en "Ver historial" en el popup del mapa,
  # se cambia de pestaña y se rellena la búsqueda de GID automáticamente.
  observeEvent(input$ver_historial_gid, {
    nav_select("menu_tabs", "hist")
    updateTextInput(session, "busqueda_gid", value = as.character(input$ver_historial_gid))
  })

  # --- Búsqueda de GID en el mapa (Autofocus + Popup automático) ---
  buscar_gid_en_mapa <- function(gid_buscado) {
    # Buscar primero en activos, luego en inactivos
    df_act  <- activos_con_indicadores()
    df_inac <- datos()$inactivos

    encontrado <- df_act[as.character(df_act$GID) == gid_buscado, ]
    grupo <- "activos"
    if (nrow(encontrado) == 0) {
      encontrado <- df_inac[as.character(df_inac$GID) == gid_buscado, ]
      grupo <- "inactivos"
    }

    if (nrow(encontrado) == 0) {
      showNotification(
        paste0("No hay ningún contenedor con GID ", gid_buscado, ", ni activo ni inactivo."),
        type = "warning", duration = 5
      )
      return(invisible())
    }

    coords <- st_coordinates(encontrado[1, ])

    # Si el GID está en el grupo opuesto al seleccionado, cambiamos el selector
    if (grupo == "activos" && input$seleccion_estado != "act") {
      updateRadioButtons(session, "seleccion_estado", selected = "act")
    } else if (grupo == "inactivos" && input$seleccion_estado != "inact") {
      updateRadioButtons(session, "seleccion_estado", selected = "inact")
    }

    leafletProxy("map") %>%
      setView(lng = coords[1], lat = coords[2], zoom = 18) %>%
      clearPopups() %>%
      addPopups(
        lng = coords[1], lat = coords[2],
        popup = popup_contenedor(encontrado[1, ], activo = grupo == "activos")
      )
  }

  # --- Buscador por dirección (geocodificación con Nominatim / OpenStreetMap) ---
  # Prioriza Montevideo de tres formas combinadas:
  #   1. countrycodes = uy  -> nunca sale de Uruguay.
  #   2. viewbox del departamento + bounded = 1 -> primero busca SÓLO dentro del
  #      recuadro de Montevideo.
  #   3. si el usuario escribió sólo calle/número (sin coma), se agrega
  #      ", Montevideo" al texto para desambiguar de localidades homónimas de
  #      otros departamentos (ej.: "18 de Julio" también es un pueblo en Rocha).
  # Además, de los resultados se elige el primero cuyo departamento (address$state)
  # sea Montevideo; sólo si ninguno lo es se cae a un resultado del resto del país.
  buscar_direccion_en_mapa <- function(query) {
    if (nchar(query) < 3) {
      showNotification("Escribí al menos 3 letras de la dirección.", type = "warning", duration = 4)
      return(invisible())
    }

    # Recuadro aproximado del departamento de Montevideo: left,top,right,bottom
    viewbox_mvd <- "-56.52,-34.68,-56.00,-34.98"
    query_ctx <- if (grepl(",", query)) query else paste0(query, ", Montevideo")

    geocodificar <- function(q, bounded) {
      resp <- tryCatch(
        httr::GET(
          "https://nominatim.openstreetmap.org/search",
          query = list(
            q              = q,
            format         = "jsonv2",
            countrycodes   = "uy",
            viewbox        = viewbox_mvd,
            bounded        = bounded,
            addressdetails = 1,
            limit          = 5
          ),
          httr::user_agent("ShinyApp-Nicolas (gestion GIDs Montevideo)"),
          httr::timeout(10)
        ),
        error = function(e) NULL
      )
      if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)
      res <- tryCatch(
        jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8")),
        error = function(e) NULL
      )
      if (is.null(res) || !is.data.frame(res) || nrow(res) == 0) return(NULL)
      res
    }

    # Primer resultado cuyo departamento sea Montevideo (NULL si ninguno lo es).
    fila_montevideo <- function(res) {
      if (is.null(res) || is.null(res$address) || is.null(res$address$state)) return(NULL)
      estado <- res$address$state
      idx <- which(!is.na(estado) & grepl("Montevideo", estado, ignore.case = TRUE))
      if (length(idx) == 0) return(NULL)
      res[idx[1], ]
    }

    hit <- fila_montevideo(geocodificar(query_ctx, bounded = 1))
    if (is.null(hit)) hit <- fila_montevideo(geocodificar(query,     bounded = 1))
    if (is.null(hit)) hit <- fila_montevideo(geocodificar(query_ctx, bounded = 0))

    fuera_mvd <- FALSE
    if (is.null(hit)) {
      res <- geocodificar(query, bounded = 0)
      if (!is.null(res)) {
        hit <- res[1, ]
        fuera_mvd <- TRUE
      }
    }

    if (is.null(hit)) {
      showNotification(
        paste0("No se encontró \"", query, "\". Probá con calle y número, por ejemplo: 18 de Julio 1234."),
        type = "warning", duration = 5
      )
      return(invisible())
    }

    lat <- as.numeric(hit$lat)
    lon <- as.numeric(hit$lon)

    leafletProxy("map") %>%
      clearGroup("geocode") %>%
      setView(lng = lon, lat = lat, zoom = 18) %>%
      addCircleMarkers(
        lng = lon, lat = lat, group = "geocode",
        radius = 10, color = COL_TINTA, weight = 3,
        fillColor = "#FFFFFF", fillOpacity = 0.6,
        popup = paste0("<div class='pop'>", esc(hit$display_name), "</div>")
      )

    if (fuera_mvd) {
      showNotification(
        "Esa dirección está fuera de Montevideo. Se muestra el resultado más cercano en Uruguay.",
        type = "message", duration = 5
      )
    }
  }

  # Un solo buscador: si es un número busca el GID, si no, la dirección
  observeEvent(input$btn_buscar, {
    consulta <- trimws(input$busqueda_mapa)
    req(nzchar(consulta))
    if (grepl("^[0-9]+$", consulta)) {
      buscar_gid_en_mapa(consulta)
    } else {
      buscar_direccion_en_mapa(consulta)
    }
  })

  # --- Lógica del Histórico ---

  # Se espera medio segundo después de la última tecla para no filtrar con GIDs a medio escribir
  gid_consultado <- debounce(reactive(trimws(input$busqueda_gid)), 500)

  # Filtramos el dataframe reactivamente según el GID y el rango de fechas elegidos
  datos_filtrados <- reactive({
    req(nzchar(gid_consultado()), input$rango_fechas_historico)
    gid_buscado <- gid_consultado()
    fecha_desde <- input$rango_fechas_historico[1]
    fecha_hasta <- input$rango_fechas_historico[2]

    datos()$historico_llenado %>%
      filter(
        as.character(gid) == gid_buscado,
        as.Date(Fecha) >= fecha_desde,
        as.Date(Fecha) <= fecha_hasta
      ) %>%
      mutate(
        Hora_pasaje = ifelse(is.na(Fecha_hora_pasaje), "", format(as.POSIXct(Fecha_hora_pasaje), "%H:%M:%S"))
      ) %>%
      select(
        Fecha, Circuito_corto, Posicion, Direccion, Levantado,
        Turno_levantado, Hora_pasaje, Id_viaje_GOL,
        Incidencia, Porcentaje_llenado, Condicion, contenedor_activo
      )
  })

  output$hay_registros <- reactive({
    nzchar(gid_consultado()) && isTruthy(input$rango_fechas_historico) && nrow(datos_filtrados()) > 0
  })
  outputOptions(output, "hay_registros", suspendWhenHidden = FALSE)

  # Cabecera de la ficha: GID, estado actual y dónde está
  ficha_cabecera <- function(gid, df) {
    act  <- datos()$activos[as.character(datos()$activos$GID) == gid, ]
    inac <- datos()$inactivos[as.character(datos()$inactivos$GID) == gid, ]
    esta_activo <- nrow(act) > 0

    # Datos de ubicación: el registro más reciente del período; si no hay, la capa del mapa
    ultimo <- if (nrow(df) > 0) df[order(as.Date(df$Fecha), decreasing = TRUE)[1], ] else NULL
    direccion <- if (!is.null(ultimo)) ultimo$Direccion else if (esta_activo) act$DIRECCION[1] else NA
    circuito  <- if (!is.null(ultimo)) ultimo$Circuito_corto else if (esta_activo) act$COD_RECORRIDO[1] else if (nrow(inac) > 0) inac$COD_RECORRIDO[1] else NA
    posicion  <- if (!is.null(ultimo)) ultimo$Posicion else if (esta_activo) act$POSICION[1] else NA

    dato <- function(etiqueta, valor) {
      if (length(valor) == 0 || is.na(valor) || !nzchar(as.character(valor))) return(NULL)
      div(tags$dt(etiqueta), tags$dd(as.character(valor)))
    }

    tagList(
      div(
        class = "ficha-cabecera",
        h1(class = "ficha-gid", span("GID"), gid),
        if (esta_activo) {
          span(class = "estado estado-activo", "Activo")
        } else if (nrow(inac) > 0) {
          span(class = "estado estado-inactivo", "Inactivo")
        }
      ),
      tags$dl(
        class = "ficha-datos",
        dato("Dirección", direccion),
        dato("Circuito", circuito),
        dato("Posición", posicion),
        if (esta_activo) dato("En servicio desde", fmt_fecha(act$FECHA_DESDE[1])),
        if (!esta_activo && nrow(inac) > 0) dato("Retirado el", fmt_fecha(inac$FECHA_HASTA[1]))
      )
    )
  }

  # Resumen del período: los mismos indicadores que antes, como una sola banda de datos
  # Plan del circuito (fila de circuitos_periodo) o NULL si no hay
  plan_circuito <- function(circuito) {
    cp <- datos()$circuitos
    if (is.null(cp) || length(circuito) == 0 || is.na(circuito)) return(NULL)
    fila <- cp[cp$Circuito_corto == circuito, ]
    if (nrow(fila) == 0) NULL else fila[1, ]
  }

  resumen_periodo <- function(df, plan = NULL) {
    total_programado <- nrow(df)

    # Llenado promedio en el rango seleccionado, solo en los levantes: los "N"
    # pueden venir con 0 % cuando el camión no llegó a revisar el contenedor.
    llenado_prom <- mean(suppressWarnings(as.numeric(df$Porcentaje_llenado[df$Levantado %in% "S"])), na.rm = TRUE)
    llenado_txt <- if (is.nan(llenado_prom)) "Sin datos" else paste0(fmt_num(llenado_prom), "%")

    # Frecuencia promedio de levante: días entre fechas con levante
    levantes <- df %>%
      filter(Levantado == "S") %>%
      mutate(Fecha = as.Date(Fecha)) %>%
      arrange(Fecha)
    fechas_unicas <- unique(levantes$Fecha)
    frecuencia_txt <- if (length(fechas_unicas) >= 2) {
      paste0(fmt_num(mean(as.numeric(diff(fechas_unicas), units = "days"))), " días")
    } else {
      "Sin datos"
    }

    # % de levantes en los que el contenedor estaba al 100%
    saturacion_txt <- if (nrow(levantes) > 0) {
      paste0(fmt_num(mean(as.numeric(levantes$Porcentaje_llenado) == 100, na.rm = TRUE) * 100, 0), "%")
    } else {
      "Sin datos"
    }

    # "N": el camión pasó pero no levantó, hay una Incidencia que lo justifica.
    # NA: estaba programado en el circuito pero el camión no llegó a pasar (sin registro).
    # Son dos fallas distintas, no se agrupan.
    n_incidencia <- sum(df$Levantado == "N", na.rm = TRUE)
    n_no_paso    <- sum(is.na(df$Levantado))

    # Frecuencia planificada del circuito, para comparar con la real
    frecuencia_nota <- "entre un levante y el siguiente, en promedio"
    if (!is.null(plan) && !is.na(plan$Periodo)) {
      frecuencia_nota <- paste0(
        frecuencia_nota, ". Plan: cada ", fmt_num(plan$Periodo), " días",
        if (!is.na(plan$Dias_recoleccion)) paste0(" (", plan$Dias_recoleccion, ")") else ""
      )
    }

    # Motivo más frecuente de no levante
    motivos <- sort(table(df$Incidencia[df$Levantado %in% "N"]), decreasing = TRUE)

    dato <- function(valor, texto, muestra = NULL, clase = NULL) {
      div(
        class = "dato",
        div(class = paste("dato-valor", clase), if (!is.null(muestra)) span(class = paste("muestra", muestra)), valor),
        p(class = "dato-texto", texto)
      )
    }

    div(
      class = "resumen",
      dato(llenado_txt, "llenado promedio cuando se levanta"),
      dato(frecuencia_txt, frecuencia_nota),
      dato(saturacion_txt, "de los levantes lo encontraron lleno", "muestra-lleno"),
      dato(
        paste0(fmt_num(100 * n_incidencia / total_programado), "%"),
        paste0("no se levantó por una incidencia (", n_incidencia, " de ", total_programado, " programados)"),
        "muestra-incidencia"
      ),
      dato(
        paste0(fmt_num(100 * n_no_paso / total_programado), "%"),
        paste0("el camión no pasó (", n_no_paso, " de ", total_programado, " programados)"),
        "muestra-nopaso"
      ),
      if (length(motivos) > 0) {
        dato(
          names(motivos)[1],
          paste0("motivo más frecuente de no levante (", motivos[[1]], " de ", n_incidencia, " incidencias)"),
          clase = "dato-valor-texto"
        )
      }
    )
  }

  # % de los levantes del período con cada observación sobre el contenedor
  estado_contenedor <- function(df) {
    lev <- df[df$Levantado %in% "S", ]
    if (nrow(lev) == 0) return(p(class = "seccion-nota", "Sin levantes en el período."))
    etiquetas <- strsplit(ifelse(is.na(lev$Condicion), "", lev$Condicion), ";", fixed = TRUE)
    etiquetas <- lapply(etiquetas, trimws)
    conteo <- vapply(CONDICIONES_CONTENEDOR, function(e) sum(vapply(etiquetas, function(x) e %in% x, logical(1))), integer(1))
    conteo <- sort(conteo[conteo > 0], decreasing = TRUE)
    if (length(conteo) == 0) {
      return(p(class = "seccion-nota", paste0("Ninguna observación en los ", nrow(lev), " levantes del período.")))
    }
    div(
      class = "condiciones",
      lapply(names(conteo), function(e) {
        prop <- conteo[[e]] / nrow(lev)
        tagList(
          span(e),
          div(class = "cond-barra", span(style = sprintf("width:%s%%", round(100 * prop, 1)))),
          span(class = "cond-valor", strong(fmt_pct(prop)), paste0(" (", conteo[[e]], " de ", nrow(lev), " levantes)"))
        )
      })
    )
  }

  output$ficha_historial <- renderUI({
    if (!nzchar(gid_consultado())) {
      return(div(
        class = "vacio",
        h2("Buscá un contenedor"),
        p("Escribí el número de GID arriba, o abrí un contenedor en el mapa y tocá Ver historial.")
      ))
    }
    req(datos(), input$rango_fechas_historico)
    gid <- gid_consultado()
    desde <- input$rango_fechas_historico[1]
    hasta <- input$rango_fechas_historico[2]
    df <- datos_filtrados()

    if (desde > hasta) {
      return(div(class = "vacio", h2("Revisá el período"), p("La fecha de inicio es posterior a la de fin.")))
    }

    existe <- gid %in% as.character(datos()$activos$GID) ||
      gid %in% as.character(datos()$inactivos$GID) || nrow(df) > 0
    if (!existe) {
      return(div(
        class = "vacio",
        h2(paste0("No hay ningún contenedor con GID ", gid)),
        p("Revisá el número. Se busca entre contenedores activos e inactivos.")
      ))
    }

    if (nrow(df) == 0) {
      return(tagList(
        ficha_cabecera(gid, df),
        div(
          class = "vacio",
          h2("Sin registros en este período"),
          p(paste0("No hay registros de llenado del ", fmt_fecha(desde), " al ", fmt_fecha(hasta),
                   ". Probá ampliar el período."))
        )
      ))
    }

    tagList(
      ficha_cabecera(gid, df),
      div(
        class = "seccion",
        h2(class = "seccion-titulo", "Llenado y levantes por día"),
        linea_tiempo(df, desde, hasta),
        leyenda_linea_tiempo
      ),
      div(
        class = "seccion",
        h2(class = "seccion-titulo", "Resumen del período"),
        resumen_periodo(df, plan_circuito(df$Circuito_corto[which.max(as.Date(df$Fecha))]))
      ),
      div(
        class = "seccion",
        h2(class = "seccion-titulo", "Estado del contenedor"),
        p(class = "seccion-nota", "Observaciones que dejó el camión al levantarlo, en % de los levantes del período."),
        estado_contenedor(df)
      )
    )
  })

  output$tabla_historico <- renderDT({
    df <- datos_filtrados()
    req(nrow(df) > 0)

    # Ordenamos de más reciente a más antiguo y traducimos S / N / NA a texto
    datos_ordenados <- df %>%
      mutate(
        Fecha = as.Date(Fecha),
        Levantado = case_when(
          Levantado == "S" ~ "Sí",
          Levantado == "N" ~ "No",
          is.na(Levantado) ~ "No pasó",
          TRUE             ~ as.character(Levantado)
        )
      ) %>%
      arrange(desc(Fecha))

    datatable(
      datos_ordenados,
      colnames = c(
        "Fecha", "Circuito", "Posición", "Dirección", "¿Levantado?",
        "Turno", "Hora pasaje", "ID viaje GOL", "Incidencia",
        "% llenado", "Condición", "Activo"
      ),
      class = "compact hover",
      options = list(
        pageLength = 15,
        lengthMenu = c(15, 30, 60, 100),
        language = list(url = "https://cdn.datatables.net/plug-ins/1.10.11/i18n/Spanish.json"),
        # scrollX queda sólo como red de seguridad en pantallas chicas
        scrollX = TRUE,
        # Índices base 0: Dirección (3), Incidencia (8), Condición (10)
        columnDefs = list(
          list(className = "col-direccion", targets = 3),
          list(className = "col-texto", targets = c(8, 10))
        )
      ),
      rownames = FALSE
    ) %>%
      formatDate("Fecha", method = "toLocaleDateString", params = list("es-UY", list(timeZone = "UTC", day = "2-digit", month = "2-digit", year = "numeric"))) %>%
      formatStyle(
        "Levantado",
        color = styleEqual(c("Sí", "No", "No pasó"), c(COL_LEVANTADO, COL_INCIDENCIA, "#5E6A67")),
        fontWeight = "600"
      ) %>%
      formatStyle(
        "Porcentaje_llenado",
        backgroundColor = styleEqual(100, "rgba(217, 162, 31, 0.22)")
      )
  })

  # --- Lógica de Circuitos ---

  # Municipios disponibles en el selector (se actualiza con los datos)
  observe({
    mun <- sort(unique(na.omit(datos()$historico_llenado$Municipio)))
    updateSelectInput(
      session, "municipio_circuitos",
      choices = c("Todos" = "", setNames(mun, paste("Municipio", mun))),
      selected = isolate(input$municipio_circuitos)
    )
  })

  # Registros del período (todos los municipios: la tabla por municipio los compara)
  registros_periodo <- reactive({
    req(datos(), input$rango_fechas_circuitos)
    desde <- input$rango_fechas_circuitos[1]
    hasta <- input$rango_fechas_circuitos[2]
    req(desde <= hasta)
    datos()$historico_llenado %>% filter(Fecha >= desde, Fecha <= hasta)
  })

  registros_municipio <- reactive({
    df <- registros_periodo()
    if (nzchar(input$municipio_circuitos)) df <- filter(df, Municipio == input$municipio_circuitos)
    df
  })

  por_circuito <- reactive({
    indicadores_por_circuito(registros_periodo(), datos()$circuitos)
  })

  criticos <- reactive({
    contenedores_criticos(registros_municipio())
  })

  output$aviso_circuitos <- renderUI({
    req(input$rango_fechas_circuitos)
    avisos <- list(
      if (input$rango_fechas_circuitos[1] > input$rango_fechas_circuitos[2]) {
        "La fecha de inicio es posterior a la de fin."
      },
      if (is.null(datos()$circuitos)) {
        "Todavía no están publicadas las frecuencias planificadas de los circuitos: no se puede calcular el atraso."
      }
    )
    avisos <- Filter(Negate(is.null), avisos)
    if (length(avisos) == 0) return(NULL)
    div(class = "vacio", lapply(avisos, p))
  })

  # Formato común de las tablas de indicadores
  tabla_indicadores <- function(df, colnames, pct, dec1 = character(0), orden, clicable = FALSE, paginar = TRUE) {
    tabla <- datatable(
      df,
      colnames = colnames,
      class = "compact hover",
      selection = if (clicable) "single" else "none",
      options = list(
        paging = paginar,
        dom = if (paginar) "lfrtip" else "t",
        pageLength = 15,
        lengthMenu = c(15, 30, 60, 150),
        order = orden,
        language = list(url = "https://cdn.datatables.net/plug-ins/1.10.11/i18n/Spanish.json"),
        scrollX = TRUE
      ),
      rownames = FALSE
    ) %>%
      formatPercentage(pct, digits = 0, dec.mark = ",")
    if (length(dec1) > 0) tabla <- formatRound(tabla, dec1, digits = 1, dec.mark = ",", mark = ".")
    tabla
  }

  output$tabla_municipios <- renderDT({
    df <- indicadores_por_municipio(registros_periodo(), por_circuito()) %>%
      mutate(Municipio = paste("Municipio", Municipio)) %>%
      select(Municipio, programados, p_levantado, p_incidencia, p_no_paso,
             saturacion, llenado, frecuencia_real, atrasados, circuitos)
    tabla_indicadores(
      df,
      colnames = c("Municipio", "Programados", "Levantado", "Incidencia", "No pasó",
                   "Lleno al levantar", "Llenado prom. (%)", "Días entre levantes",
                   "Circuitos atrasados", "Circuitos"),
      pct = c("p_levantado", "p_incidencia", "p_no_paso", "saturacion"),
      dec1 = c("llenado", "frecuencia_real"),
      orden = list(list(5, "desc")),
      paginar = FALSE
    ) %>%
      formatRound("programados", digits = 0, mark = ".")
  })

  output$tabla_circuitos <- renderDT({
    df <- por_circuito()
    if (nzchar(input$municipio_circuitos)) df <- filter(df, Municipio == input$municipio_circuitos)
    df <- df %>%
      select(Circuito_corto, Municipio, Oficina, Dias_recoleccion, Turno, Periodo,
             frecuencia_real, atraso, p_levantado, p_incidencia, p_no_paso, saturacion, llenado)
    tabla_indicadores(
      df,
      colnames = c("Circuito", "Municipio", "Oficina", "Días de recolección", "Turno",
                   "Días plan", "Días reales", "Atraso", "Levantado", "Incidencia",
                   "No pasó", "Lleno al levantar", "Llenado prom. (%)"),
      pct = c("p_levantado", "p_incidencia", "p_no_paso", "saturacion"),
      dec1 = c("Periodo", "frecuencia_real", "llenado"),
      orden = list(list(7, "desc"))
    ) %>%
      formatRound("atraso", digits = 2, dec.mark = ",") %>%
      formatStyle(
        "atraso",
        color = styleInterval(UMBRAL_ATRASO, c(COL_TINTA, COL_INCIDENCIA)),
        fontWeight = styleInterval(UMBRAL_ATRASO, c("400", "600"))
      )
  })

  output$tabla_criticos <- renderDT({
    df <- criticos() %>%
      select(gid, Municipio, Circuito_corto, Direccion, levantes, saturacion, p_basura, p_no_paso)
    tabla_indicadores(
      df,
      colnames = c("GID", "Municipio", "Circuito", "Dirección", "Levantes",
                   "Lleno al levantar", "Basura afuera", "No pasó"),
      pct = c("saturacion", "p_basura", "p_no_paso"),
      orden = list(list(5, "desc")),
      clicable = TRUE
    )
  })

  # Click en un contenedor crítico: abre su historial con el mismo período
  observeEvent(input$tabla_criticos_rows_selected, {
    fila <- input$tabla_criticos_rows_selected
    req(length(fila) == 1)
    gid <- criticos()$gid[fila]
    updateDateRangeInput(
      session, "rango_fechas_historico",
      start = input$rango_fechas_circuitos[1], end = input$rango_fechas_circuitos[2]
    )
    updateTextInput(session, "busqueda_gid", value = as.character(gid))
    nav_select("menu_tabs", "hist")
  })
}

shinyApp(ui, server)
