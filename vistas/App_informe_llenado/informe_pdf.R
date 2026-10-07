# Informe en PDF del Historial de un contenedor.
#
# Se arma en R con grid + ggplot2 (sin Chrome ni LaTeX, así funciona igual en
# shinyapps.io). Lo usa el botón "Descargar PDF" de la pestaña Historial.
# Los números vienen de las mismas funciones que la pantalla (calcular_ficha,
# calcular_resumen, conteo_condiciones, resumen_por_dia, registros_para_tabla
# en App.R) y los colores de la misma paleta (COL_*).
#
# Página 1: ficha, línea de tiempo, resumen y estado del contenedor.
# Páginas siguientes: la tabla de registros completa.

library(grid)

# --- FUENTES ---
# Títulos y números grandes: Barlow Semi Condensed, la misma de la app
# (licencia OFL, carpeta fonts/). showtext la dibuja como trazos, y eso pesa:
# por eso solo se usa en esos textos cortos. El resto (textos, gráfico, tabla)
# va en la Helvetica que trae todo lector de PDF, que no se incrusta y deja el
# archivo liviano. Si faltan los archivos de la fuente, todo sale en Helvetica.
FUENTE_TEXTO  <- "sans"
FUENTE_TITULO <- "sans"
tryCatch({
  sysfonts::font_add(
    "BarlowSemiCondensed",
    regular = "fonts/BarlowSemiCondensed-SemiBold.ttf",
    bold    = "fonts/BarlowSemiCondensed-Bold.ttf"
  )
  FUENTE_TITULO <- "BarlowSemiCondensed"
}, error = function(e) {
  message("⚠️ [PDF] No se pudo cargar la fuente Barlow Semi Condensed: ", conditionMessage(e))
})

# Evalúa `expr` con showtext prendido si el texto es de la fuente de títulos
con_fuente <- function(familia, expr) {
  if (identical(familia, FUENTE_TITULO) && FUENTE_TITULO != FUENTE_TEXTO) {
    showtext::showtext_begin()
    on.exit(showtext::showtext_end())
  }
  expr
}

COL_TINTA_SUAVE <- "#5E6A67"
COL_LINEA       <- "#DDE2DF"
COL_PAPEL       <- "#F6F7F5"

# A4 horizontal, en pulgadas
PDF_ANCHO  <- 11.69
PDF_ALTO   <- 8.27
PDF_MARGEN <- 0.5
# Espacio que ocupan el título de la página de registros y el pie
ALTO_TITULO_TABLA <- 0.55
ALTO_PIE          <- 0.45
# Letra de la tabla de registros (pt): tamaño estándar de lectura
TAMANO_TABLA      <- 9
# Margen horizontal total de cada celda de la tabla y sangría del texto (pt)
PADDING_TABLA     <- 8
SANGRIA_TABLA     <- 5
# Alto de cada fila de la tabla (pulgadas): la letra más un margen arriba y abajo
ALTO_FILA_TABLA   <- (TAMANO_TABLA + 3.6) / 72

# Barras sin dato de llenado: el mismo color, más claro
ALFA_SIN_DATO <- 0.35

COLORES_ESTADO <- c(levantado = COL_LEVANTADO, incidencia = COL_INCIDENCIA, nopaso = COL_SIN_REGISTRO)

# --- PIEZAS DE TEXTO ---
texto <- function(label, x, y, tam = 9, col = COL_TINTA, negrita = FALSE,
                  titulo = FALSE, hjust = 0, vjust = 0.5, ...) {
  textGrob(
    label, x = x, y = y, hjust = hjust, vjust = vjust,
    gp = gpar(
      fontfamily = if (titulo) FUENTE_TITULO else FUENTE_TEXTO,
      fontface = if (negrita) "bold" else "plain",
      fontsize = tam, col = col, ...
    )
  )
}

# Los textos en la fuente de títulos se juntan y se dibujan todos juntos al
# cerrar la página (volcar_titulos): prender y apagar showtext es lento, así
# se hace una sola vez por página.
titulos_pendientes <- new.env()
titulos_pendientes$lista <- list()

escribir <- function(g) {
  if (identical(g$gp$fontfamily, FUENTE_TITULO) && FUENTE_TITULO != FUENTE_TEXTO) {
    titulos_pendientes$lista <- c(titulos_pendientes$lista, list(g))
  } else {
    grid.draw(g)
  }
}

volcar_titulos <- function() {
  if (length(titulos_pendientes$lista) == 0) return(invisible())
  con_fuente(FUENTE_TITULO, for (g in titulos_pendientes$lista) grid.draw(g))
  titulos_pendientes$lista <- list()
}

ancho_texto <- function(label, tam, negrita = FALSE, titulo = FALSE) {
  g <- texto(label, 0, 0, tam, negrita = negrita, titulo = titulo)
  con_fuente(g$gp$fontfamily, convertWidth(grobWidth(g), "in", valueOnly = TRUE))
}

# Recorta un texto largo con "…" para que entre en una celda
recortar <- function(x, n) {
  x <- ifelse(is.na(x), "", as.character(x))
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "…"), x)
}

# Parte un texto en líneas que entren en `ancho` pulgadas
envolver <- function(label, ancho, tam) {
  palabras <- strsplit(label, " ", fixed = TRUE)[[1]]
  lineas <- character(0)
  actual <- ""
  for (p in palabras) {
    candidata <- if (nzchar(actual)) paste(actual, p) else p
    if (nzchar(actual) && ancho_texto(candidata, tam) > ancho) {
      lineas <- c(lineas, actual)
      actual <- p
    } else {
      actual <- candidata
    }
  }
  c(lineas, actual)
}

titulo_seccion_en <- function(label, x, y) {
  escribir(texto(label, unit(x, "in"), unit(y, "in"), tam = 12.5, negrita = TRUE, titulo = TRUE, vjust = 1))
}
titulo_seccion <- function(label, y) titulo_seccion_en(label, 0, y)

# Pie de página: de dónde salen los datos y el número de página
pie_pagina <- function(pagina, total, fecha_datos) {
  generado <- format(Sys.time(), "%d/%m/%Y %H:%M", tz = "America/Montevideo")
  grid.lines(x = c(0, 1), y = unit(c(0.28, 0.28), "in"), gp = gpar(col = COL_LINEA, lwd = 0.8))
  escribir(texto(
    paste0("Gestión de GIDs  ·  Datos al ", fmt_fecha(fecha_datos), "  ·  Generado el ", generado),
    0, unit(0.1, "in"), tam = 7.5, col = COL_TINTA_SUAVE
  ))
  escribir(texto(
    paste0("Página ", pagina, " de ", total),
    1, unit(0.1, "in"), tam = 7.5, col = COL_TINTA_SUAVE, hjust = 1
  ))
  # El pie es lo último de cada página: se dibujan los títulos que esperaban
  volcar_titulos()
}

# Área útil de la página (dentro de los márgenes), en pulgadas
abrir_pagina <- function(nueva = TRUE) {
  if (nueva) grid.newpage()
  pushViewport(viewport(
    x = unit(PDF_MARGEN, "in"), y = unit(PDF_MARGEN * 0.7, "in"),
    width = unit(PDF_ANCHO - 2 * PDF_MARGEN, "in"),
    height = unit(PDF_ALTO - PDF_MARGEN * 1.7, "in"),
    just = c("left", "bottom")
  ))
}

# --- CABECERA DE LA FICHA ---
# Dibuja desde `y` (pulgadas desde abajo del área útil) hacia abajo y devuelve
# dónde terminó.
dibujar_cabecera <- function(ficha, desde, hasta, y) {
  escribir(texto("HISTORIAL DE CONTENEDOR", 0, unit(y, "in"), tam = 8.5,
                  col = COL_TINTA_SUAVE, negrita = TRUE, vjust = 1))

  # Período arriba a la derecha
  escribir(texto("Período", 1, unit(y, "in"), tam = 8.5, col = COL_TINTA_SUAVE, hjust = 1, vjust = 1))
  escribir(texto(paste(fmt_fecha(desde), "a", fmt_fecha(hasta)), 1, unit(y - 0.2, "in"),
                  tam = 11, negrita = TRUE, hjust = 1, vjust = 1))

  # "GID" chico + número grande, y la píldora de estado al lado
  y_gid <- y - 0.72
  escribir(texto("GID", 0, unit(y_gid, "in"), tam = 15, col = COL_TINTA_SUAVE, titulo = TRUE, vjust = 0))
  x_num <- ancho_texto("GID", 15, titulo = TRUE) + 0.08
  escribir(texto(ficha$gid, unit(x_num, "in"), unit(y_gid, "in"), tam = 36, negrita = TRUE, titulo = TRUE, vjust = 0))

  if (!is.null(ficha$estado)) {
    col_estado <- if (ficha$estado == "Activo") COL_LEVANTADO else COL_TINTA_SUAVE
    x_pill <- x_num + ancho_texto(ficha$gid, 36, negrita = TRUE, titulo = TRUE) + 0.18
    w_pill <- ancho_texto(ficha$estado, 9, negrita = TRUE) + 0.24
    grid.roundrect(
      x = unit(x_pill, "in"), y = unit(y_gid + 0.13, "in"),
      width = unit(w_pill, "in"), height = unit(0.24, "in"),
      r = unit(0.12, "in"), just = c("left", "center"),
      gp = gpar(col = col_estado, fill = NA, lwd = 1.3)
    )
    escribir(texto(ficha$estado, unit(x_pill + w_pill / 2, "in"), unit(y_gid + 0.13, "in"),
                    tam = 9, col = col_estado, negrita = TRUE, hjust = 0.5))
  }

  # Datos de la ficha en una fila (pasa a otra línea si no entran)
  y_datos <- y_gid - 0.3
  x <- 0
  ancho_util <- PDF_ANCHO - 2 * PDF_MARGEN
  for (etiqueta in names(ficha$datos)) {
    valor <- recortar(ficha$datos[[etiqueta]], 60)
    w <- max(ancho_texto(etiqueta, 8), ancho_texto(valor, 10, negrita = TRUE)) + 0.4
    if (x > 0 && x + w > ancho_util) {
      x <- 0
      y_datos <- y_datos - 0.45
    }
    escribir(texto(etiqueta, unit(x, "in"), unit(y_datos, "in"), tam = 8, col = COL_TINTA_SUAVE, vjust = 1))
    escribir(texto(valor, unit(x, "in"), unit(y_datos - 0.17, "in"), tam = 10, negrita = TRUE, vjust = 1))
    x <- x + w
  }

  y_linea <- y_datos - 0.52
  grid.lines(x = c(0, 1), y = unit(c(y_linea, y_linea), "in"), gp = gpar(col = COL_TINTA, lwd = 0.8))
  y_linea
}

# --- LÍNEA DE TIEMPO ---
# Misma lectura que en pantalla: altura = % de llenado del levante, color =
# qué pasó ese día, barra clara = sin dato de llenado, franja ámbar = lleno.
grafico_linea_tiempo <- function(df, desde, hasta) {
  por_dia <- resumen_por_dia(df) %>%
    mutate(
      sin_dato = is.na(pct),
      altura = ifelse(sin_dato, 100, pmax(pct, 3)),
      lleno = !sin_dato & pct >= 100
    )
  n_dias <- as.numeric(hasta - desde) + 1
  ancho_barra <- if (n_dias > 200) 1 else 0.78

  # Eje: hasta un mes, cada día; hasta ~3 meses, cada semana; si no, cada mes
  if (n_dias <= 31) {
    cortes <- seq(desde, hasta, by = "day")
    etiqueta <- function(d) format(d, "%d/%m")
  } else if (n_dias <= DIAS_MAX_EJE_DIARIO) {
    cortes <- seq(desde, hasta, by = "week")
    etiqueta <- function(d) format(d, "%d/%m")
  } else {
    cortes <- seq(as.Date(format(desde, "%Y-%m-01")), hasta, by = "month")
    cortes <- cortes[cortes >= desde]
    paso <- ceiling(length(cortes) / 12)
    cortes <- cortes[seq(1, length(cortes), by = paso)]
    etiqueta <- function(d) paste(substr(MESES_ES[as.integer(format(d, "%m"))], 1, 3), format(d, "%y"))
  }

  ggplot(por_dia, aes(x = dia)) +
    geom_hline(yintercept = c(50, 100), colour = COL_LINEA, linewidth = 0.3) +
    geom_col(
      aes(y = altura, fill = estado, alpha = sin_dato),
      width = ancho_barra
    ) +
    geom_tile(
      data = filter(por_dia, lleno),
      aes(y = 97, height = 6), width = ancho_barra, fill = COL_LLENO
    ) +
    geom_hline(yintercept = 0, colour = COL_TINTA, linewidth = 0.4) +
    scale_fill_manual(values = COLORES_ESTADO, guide = "none") +
    scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = ALFA_SIN_DATO), guide = "none") +
    scale_x_date(
      limits = c(desde - 0.6, hasta + 0.6), breaks = cortes, labels = etiqueta,
      expand = expansion(0)
    ) +
    scale_y_continuous(
      limits = c(0, 100), breaks = c(0, 50, 100), labels = function(x) paste0(x, "%"),
      expand = expansion(c(0, 0.02))
    ) +
    labs(x = NULL, y = NULL) +
    theme_minimal(base_family = FUENTE_TEXTO, base_size = 8) +
    theme(
      panel.grid = element_blank(),
      axis.text = element_text(colour = COL_TINTA_SUAVE, size = 7.5),
      axis.text.x = if (n_dias <= 31) element_text(angle = 90, vjust = 0.5, hjust = 1) else element_text(),
      axis.ticks.x = element_line(colour = COL_LINEA, linewidth = 0.3),
      axis.ticks.length.x = unit(2, "pt"),
      plot.margin = margin(4, 2, 0, 0)
    )
}

# Muestras con el mismo aspecto que las barras: sin dato de llenado (incidencia,
# no pasó) = barra completa clara. Pasa a otra línea si no entra; devuelve
# dónde terminó.
dibujar_leyenda <- function(y) {
  items <- list(
    list(col = COL_LEVANTADO,    alpha = 1,           label = "Levantado"),
    list(col = COL_INCIDENCIA,   alpha = ALFA_SIN_DATO, label = "No levantado, con incidencia"),
    list(col = COL_SIN_REGISTRO, alpha = ALFA_SIN_DATO, label = "El camión no pasó"),
    list(col = COL_LLENO,        alpha = 1,           label = "Lleno (100%)"),
    list(col = NA,               alpha = 1,           label = "Barra clara: sin dato de llenado"),
    list(col = NA,               alpha = 1,           label = "Sin barra: no estaba programado")
  )
  ancho_util <- PDF_ANCHO - 2 * PDF_MARGEN
  x <- 0
  primera_nota <- TRUE
  for (it in items) {
    w <- ancho_texto(it$label, 7.5) + if (is.na(it$col)) 0 else 0.15
    # Las notas sin muestra de color van en su propia línea
    nueva_linea <- is.na(it$col) && primera_nota
    if (is.na(it$col)) primera_nota <- FALSE
    if (x > 0 && (nueva_linea || x + w > ancho_util)) {
      x <- 0
      y <- y - 0.2
    }
    if (!is.na(it$col)) {
      grid.rect(x = unit(x, "in"), y = unit(y, "in"), width = unit(0.1, "in"), height = unit(0.1, "in"),
                just = c("left", "center"), gp = gpar(fill = it$col, col = NA, alpha = it$alpha))
    }
    escribir(texto(it$label, unit(x + w - ancho_texto(it$label, 7.5), "in"), unit(y, "in"),
                    tam = 7.5, col = COL_TINTA_SUAVE))
    x <- x + w + 0.25
  }
  y
}

# --- RESUMEN DEL PERÍODO ---
# Grilla de tarjetas de 3 columnas: número grande + qué significa.
# Ocupa `ancho` pulgadas desde `x`.
dibujar_resumen <- function(resumen, x, y, ancho) {
  cols <- 3
  sep <- 0.14
  w <- (ancho - sep * (cols - 1)) / cols
  h <- 0.96
  for (i in seq_along(resumen)) {
    d <- resumen[[i]]
    fila <- (i - 1) %/% cols
    col <- (i - 1) %% cols
    x0 <- x + col * (w + sep)
    y0 <- y - fila * (h + sep)
    grid.roundrect(x = unit(x0, "in"), y = unit(y0, "in"), width = unit(w, "in"), height = unit(h, "in"),
                   r = unit(0.06, "in"), just = c("left", "top"), gp = gpar(fill = COL_PAPEL, col = NA))
    x_valor <- x0 + 0.14
    if (!is.null(d$muestra)) {
      col_muestra <- switch(d$muestra, lleno = COL_LLENO, incidencia = COL_INCIDENCIA, nopaso = COL_SIN_REGISTRO)
      grid.rect(x = unit(x_valor, "in"), y = unit(y0 - 0.28, "in"), width = unit(0.1, "in"), height = unit(0.1, "in"),
                just = c("left", "center"), gp = gpar(fill = col_muestra, col = NA))
      x_valor <- x_valor + 0.17
    }
    valor <- if (d$es_texto) recortar(d$valor, 24) else d$valor
    escribir(texto(valor, unit(x_valor, "in"), unit(y0 - 0.28, "in"),
                    tam = if (d$es_texto) 13 else 20, negrita = TRUE, titulo = TRUE))
    lineas <- envolver(d$texto, w - 0.28, 7.8)
    if (length(lineas) > 3) lineas <- c(lineas[1:2], paste0(lineas[3], "…"))
    escribir(texto(paste(lineas, collapse = "\n"), unit(x0 + 0.14, "in"), unit(y0 - 0.47, "in"),
                    tam = 7.8, col = COL_TINTA_SUAVE, vjust = 1, lineheight = 1.15))
  }
  filas <- ceiling(length(resumen) / cols)
  y - filas * h - (filas - 1) * sep
}

# --- ESTADO DEL CONTENEDOR ---
# Una fila por observación: nombre, barra y "% (n de N)". Ocupa `ancho`
# pulgadas desde `x`.
dibujar_condiciones <- function(cond, x, y, ancho) {
  if (cond$levantes == 0 || nrow(cond$conteo) == 0) {
    msg <- if (cond$levantes == 0) "Sin levantes en el período." else
      paste0("Ninguna observación en los ", cond$levantes, " levantes del período.")
    escribir(texto(msg, unit(x, "in"), unit(y, "in"), tam = 9, col = COL_TINTA_SUAVE, vjust = 1))
    return(y - 0.3)
  }
  tam <- 8.5
  pcts <- fmt_pct(cond$conteo$prop)
  detalles <- paste0(" (", cond$conteo$n, " de ", cond$levantes, ")")
  w_etiqueta <- max(vapply(cond$conteo$condicion, ancho_texto, numeric(1), tam = tam)) + 0.15
  w_valor <- max(vapply(pcts, ancho_texto, numeric(1), tam = tam, negrita = TRUE) +
                   vapply(detalles, ancho_texto, numeric(1), tam = tam)) + 0.15
  x_barra <- x + w_etiqueta
  w_barra <- max(0.5, ancho - w_etiqueta - w_valor)
  alto_fila <- 0.23
  for (i in seq_len(nrow(cond$conteo))) {
    f <- cond$conteo[i, ]
    yi <- y - 0.08 - (i - 1) * alto_fila
    escribir(texto(f$condicion, unit(x, "in"), unit(yi, "in"), tam = tam))
    grid.rect(x = unit(x_barra, "in"), y = unit(yi, "in"), width = unit(w_barra, "in"), height = unit(0.1, "in"),
              just = c("left", "center"), gp = gpar(fill = COL_LINEA, col = NA))
    grid.rect(x = unit(x_barra, "in"), y = unit(yi, "in"), width = unit(w_barra * f$prop, "in"), height = unit(0.1, "in"),
              just = c("left", "center"), gp = gpar(fill = COL_TINTA_SUAVE, col = NA))
    x_valor <- x_barra + w_barra + 0.15
    escribir(texto(pcts[i], unit(x_valor, "in"), unit(yi, "in"), tam = tam, negrita = TRUE))
    escribir(texto(detalles[i], unit(x_valor + ancho_texto(pcts[i], tam, negrita = TRUE), "in"), unit(yi, "in"),
                   tam = tam, col = COL_TINTA_SUAVE))
  }
  y - nrow(cond$conteo) * alto_fila
}

# --- TABLA DE REGISTROS ---
# Columnas de texto libre que se recortan con "…" para que la tabla entre en
# el ancho de la página, con su largo máximo inicial (caracteres). Las demás
# columnas (fechas, IDs, etc.) nunca se achican.
LARGOS_TEXTO <- c("Dirección" = 26, "Incidencia" = 26, "Condición" = 26)
LARGO_MINIMO <- 10

preparar_tabla <- function(df, largos = LARGOS_TEXTO) {
  t <- registros_para_tabla(df)
  data.frame(
    fmt_fecha(t$Fecha),
    recortar(t$Circuito_corto, 10),
    recortar(t$Posicion, 6),
    recortar(t$Direccion, largos[["Dirección"]]),
    t$Levantado,
    recortar(t$Turno_levantado, 10),
    recortar(t$Hora_pasaje, 19),
    recortar(t$Id_viaje_GOL, 12),
    recortar(t$Incidencia, largos[["Incidencia"]]),
    ifelse(is.na(t$Porcentaje_llenado), "", as.character(t$Porcentaje_llenado)),
    recortar(t$Condicion, largos[["Condición"]]),
    recortar(t$contenedor_activo, 5),
    check.names = FALSE, stringsAsFactors = FALSE
  ) |> setNames(COLNAMES_REGISTROS)
}

# Ancho (pulgadas) que ocupa cada columna en la tabla: su texto más ancho,
# encabezado incluido, más el margen de la celda
anchos_columnas <- function(tabla) {
  # Cada texto se mide por separado (el ancho de un textGrob con varios
  # textos es el del primero, no el del más ancho)
  ancho <- function(x, negrita) {
    pushViewport(viewport(gp = gpar(fontfamily = FUENTE_TEXTO, fontsize = TAMANO_TABLA,
                                    fontface = if (negrita) "bold" else "plain")))
    on.exit(popViewport())
    max(convertWidth(stringWidth(unique(x)), "in", valueOnly = TRUE))
  }
  vapply(names(tabla), function(col) {
    max(ancho(col, TRUE), ancho(tabla[[col]], col == "¿Levantado?")) + PADDING_TABLA / 72
  }, numeric(1))
}

# Arma la tabla recortando las columnas de texto libre, de a poco y empezando
# por la más ancha, hasta que entre en el ancho de la página. Devuelve la
# tabla y el ancho de cada columna, estirado para ocupar toda la página.
ajustar_tabla <- function(df) {
  ancho_util <- PDF_ANCHO - 2 * PDF_MARGEN
  largos <- LARGOS_TEXTO
  repeat {
    tabla <- preparar_tabla(df, largos)
    anchos <- anchos_columnas(tabla)
    recortables <- names(largos)[largos > LARGO_MINIMO]
    if (sum(anchos) <= ancho_util || length(recortables) == 0) break
    mas_ancha <- recortables[which.max(anchos[recortables])]
    largos[[mas_ancha]] <- largos[[mas_ancha]] - 1
  }
  list(tabla = tabla, anchos = anchos * ancho_util / sum(anchos))
}

# Cuántas filas de registros entran en una página (debajo del encabezado)
filas_por_pagina <- function() {
  alto_tabla <- PDF_ALTO - PDF_MARGEN * 1.7 - ALTO_TITULO_TABLA - ALTO_PIE
  max(1, floor(alto_tabla / ALTO_FILA_TABLA) - 1)
}

# Dibuja una página de la tabla desde `y` (arriba) hacia abajo. Cada columna
# se escribe en una sola llamada (mucho más rápido que celda por celda).
dibujar_tabla <- function(tabla, anchos, y) {
  n <- nrow(tabla)
  x_col <- cumsum(c(0, head(anchos, -1)))
  x_texto <- x_col + SANGRIA_TABLA / 72
  gp_texto <- function(...) gpar(fontfamily = FUENTE_TEXTO, fontsize = TAMANO_TABLA, ...)
  y_filas <- y - ALTO_FILA_TABLA * (seq_len(n) + 0.5)

  # Fondos: filas alternadas y % llenado = 100 resaltado en ámbar
  pares <- seq_len(n) %% 2 == 0
  if (any(pares)) {
    grid.rect(x = 0, y = unit(y_filas[pares], "in"), width = unit(sum(anchos), "in"),
              height = unit(ALTO_FILA_TABLA, "in"), just = c("left", "center"),
              gp = gpar(fill = COL_PAPEL, col = NA))
  }
  col_llenado <- match("% llenado", names(tabla))
  llenos <- tabla[[col_llenado]] == "100"
  if (any(llenos)) {
    grid.rect(x = unit(x_col[col_llenado], "in"), y = unit(y_filas[llenos], "in"),
              width = unit(anchos[col_llenado], "in"), height = unit(ALTO_FILA_TABLA, "in"),
              just = c("left", "center"), gp = gpar(fill = "#F6E8C3", col = NA))
  }

  # Encabezado y línea debajo, como en la tabla de la app
  grid.text(names(tabla), x = unit(x_texto, "in"), y = unit(y - ALTO_FILA_TABLA / 2, "in"),
            hjust = 0, gp = gp_texto(fontface = "bold", col = COL_TINTA_SUAVE))
  grid.lines(x = unit(c(0, sum(anchos)), "in"), y = unit(rep(y - ALTO_FILA_TABLA, 2), "in"),
             gp = gpar(col = COL_TINTA, lwd = 0.8))

  # Datos: "¿Levantado?" en negrita y con su color
  for (j in seq_along(tabla)) {
    valores <- tabla[[j]]
    gp <- if (names(tabla)[j] == "¿Levantado?") {
      gp_texto(fontface = "bold", col = ifelse(valores == "Sí", COL_LEVANTADO,
                                               ifelse(valores == "No", COL_INCIDENCIA, COL_TINTA_SUAVE)))
    } else {
      gp_texto(col = COL_TINTA)
    }
    grid.text(valores, x = unit(x_texto[j], "in"), y = unit(y_filas, "in"), hjust = 0, gp = gp)
  }
}

# --- INFORME COMPLETO ---
generar_pdf_historial <- function(archivo, gid, desde, hasta, df, ficha, resumen,
                                  condiciones, fecha_datos) {
  # WinAnsi (CP1252): la codificación de Helvetica que incluye tildes, ñ, ¿ y "…"
  grDevices::pdf(archivo, width = PDF_ANCHO, height = PDF_ALTO, onefile = TRUE,
                 title = paste0("Historial GID ", gid), encoding = "WinAnsi.enc")
  on.exit(grDevices::dev.off(), add = TRUE)
  titulos_pendientes$lista <- list()  # por si un PDF anterior quedó a medias

  # Las medidas de la tabla se toman con el dispositivo ya abierto (con sus fuentes)
  ajuste <- ajustar_tabla(df)
  tabla <- ajuste$tabla
  por_pagina <- filas_por_pagina()
  paginas_tabla <- max(1, ceiling(nrow(tabla) / por_pagina))
  total_paginas <- 1 + paginas_tabla

  alto_util <- PDF_ALTO - PDF_MARGEN * 1.7

  # Página 1: el informe
  # Medir la tabla ya abrió la primera página del dispositivo
  abrir_pagina(nueva = FALSE)
  y <- dibujar_cabecera(ficha, desde, hasta, alto_util)

  y <- y - 0.3
  titulo_seccion("Llenado y levantes por día", y)
  alto_grafico <- 1.75
  y <- y - 0.3
  print(
    grafico_linea_tiempo(df, desde, min(hasta, fecha_datos)),
    vp = viewport(x = 0, y = unit(y, "in"), width = 1, height = unit(alto_grafico, "in"), just = c("left", "top"))
  )
  y <- dibujar_leyenda(y - alto_grafico - 0.18)

  # Abajo, en dos columnas: resumen a la izquierda, estado a la derecha
  y <- y - 0.38
  ancho_util <- PDF_ANCHO - 2 * PDF_MARGEN
  ancho_resumen <- ancho_util * 0.6
  x_estado <- ancho_resumen + 0.45
  ancho_estado <- ancho_util - x_estado

  titulo_seccion("Resumen del período", y)
  dibujar_resumen(resumen, 0, y - 0.3, ancho_resumen)

  titulo_seccion_en("Estado del contenedor", x_estado, y)
  escribir(texto("Observaciones que dejó el camión al levantarlo, en % de los levantes.",
                 unit(x_estado, "in"), unit(y - 0.28, "in"), tam = 8, col = COL_TINTA_SUAVE, vjust = 1))
  dibujar_condiciones(condiciones, x_estado, y - 0.55, ancho_estado)

  pie_pagina(1, total_paginas, fecha_datos)
  popViewport()

  # Páginas siguientes: registros
  for (p in seq_len(paginas_tabla)) {
    filas <- seq((p - 1) * por_pagina + 1, min(p * por_pagina, nrow(tabla)))
    abrir_pagina()
    titulo_seccion("Registros", alto_util)
    escribir(texto(
      paste0("GID ", gid, "  ·  ", fmt_fecha(desde), " a ", fmt_fecha(hasta), "  ·  ",
             nrow(tabla), " registros, del más reciente al más antiguo",
             if (paginas_tabla > 1) paste0("  ·  ", p, " de ", paginas_tabla) else ""),
      0, unit(alto_util - 0.3, "in"), tam = 8, col = COL_TINTA_SUAVE, vjust = 1
    ))
    # Mismos anchos en todas las páginas (los de la tabla completa)
    dibujar_tabla(tabla[filas, , drop = FALSE], ajuste$anchos, alto_util - ALTO_TITULO_TABLA)
    pie_pagina(1 + p, total_paginas, fecha_datos)
    popViewport()
  }

  invisible(archivo)
}
