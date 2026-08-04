# Arma el archivo HTML final (mapa + tabla) reemplazando placeholders en
# informe_template.html con los datos calculados por generar_informe_html.R.
# Se usa gsub(fixed=TRUE) en vez de sprintf para no tener que escapar los
# muchos "%" propios del CSS/JS de la plantilla.

d <- readRDS("informes/Porcentaje_llenado_peorescasos/datos_informe_html.rds")

tpl <- readLines("informes/Porcentaje_llenado_peorescasos/informe_template.html", warn = FALSE)
tpl <- paste(tpl, collapse = "\n")

# Leaflet embebido localmente (informes/_vendor/leaflet/, copiado del paquete R "leaflet")
# en vez de cargarlo de un CDN, porque el CDN queda bloqueado por políticas de red/CSP.
leaflet_css <- paste(readLines("informes/_vendor/leaflet/leaflet.css", warn = FALSE), collapse = "\n")
leaflet_js <- paste(readLines("informes/_vendor/leaflet/leaflet.js", warn = FALSE), collapse = "\n")

reemplazos <- list(
  "__MUNICIPIO__" = d$municipio,
  "__FECHA_MIN__" = as.character(d$fecha_min),
  "__FECHA_MAX__" = as.character(d$fecha_max),
  "__N_EVALUADOS__" = as.character(d$n_evaluados),
  "__LEAFLET_CSS__" = leaflet_css,
  "__LEAFLET_JS__" = leaflet_js,
  "__JSON_MAPA__" = d$json_mapa,
  "__JSON_TABLA__" = d$json_tabla
)

for (marcador in names(reemplazos)) {
  tpl <- gsub(marcador, reemplazos[[marcador]], tpl, fixed = TRUE)
}

out_path <- "informes/Porcentaje_llenado_peorescasos/informe_peores_contenedores_MunicipioB.html"
writeLines(tpl, out_path, useBytes = TRUE)
cat("HTML generado:", out_path, "\n")
