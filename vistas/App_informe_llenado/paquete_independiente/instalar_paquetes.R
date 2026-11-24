# ==============================================================================
# instalar_paquetes.R
# Instala los paquetes de R que usan la app y el script. Correr UNA vez por PC:
#   source("instalar_paquetes.R")
# ==============================================================================

paquetes <- c(
  # La app
  "shiny", "bslib", "htmltools", "mapgl", "sf", "pins", "dplyr", "DT",
  "jsonlite", "httr", "ggplot2", "showtext", "sysfonts", "openxlsx",
  # El script de actualización
  "purrr", "readr", "stringr", "xml2", "rstudioapi",
  # Publicar
  "rsconnect"
)

faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  message("Instalando: ", paste(faltan, collapse = ", "))
  install.packages(faltan, repos = "https://cloud.r-project.org")
}

faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) == 0) {
  message("✅ Están todos los paquetes.")
} else {
  stop("No se pudieron instalar: ", paste(faltan, collapse = ", "))
}
