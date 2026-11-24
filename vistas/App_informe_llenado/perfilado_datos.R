# ==============================================================================
# perfilado_datos.R — Perfila las fuentes RDS de la app de llenado y deja:
#
#   documentacion/catalogo/perfil/app_<fuente>_<AAAA-MM-DD>.json
#
# Qué calcula por fuente:
#   - filas
#   - por columna: clase, nulos, valores distintos
#   - numéricas: mínimo y máximo
#   - si hay 50 valores distintos o menos: conteo por valor
#   - fechas: no se perfilan (decisión del catálogo)
#   - geometrías: solo se marca la clase
#
# Correr LOCALMENTE desde la raíz del proyecto APP_nuevoinforme/.
# Requiere here, jsonlite (ya en el proyecto).
#
# ESTADO: escrito, no ejecutado. Hay que correrlo una vez y revisar la salida.
# ==============================================================================

library(jsonlite)

# Mismas fuentes que limpieza_datos.R. Si cambian allí, cambiar aquí.
FUENTES <- c(
  GID_activos           = "db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds",
  GID_inactivos         = "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds",
  historico_llenado_web = "db/GOL_reportes/historico_llenadoGol.rds",
  circuitos_periodo     = "UNA_POR_CIRCUITO/rds/circuitos_periodo.rds"
)

MAX_VALORES <- 50

DOC_CATALOGO <- here::here("documentacion", "catalogo")


perfilar_columna <- function(x) {
  info <- list(
    clase    = class(x)[1],
    nulos    = sum(is.na(x)),
    distintos = length(unique(x[!is.na(x)]))
  )

  if (inherits(x, "sfc")) {
    info$clase <- "geometria"
    return(info)
  }

  if (inherits(x, c("Date", "POSIXct", "POSIXt"))) {
    info$rango <- "no se perfila (decisión del catálogo)"
    return(info)
  }

  if (is.numeric(x) && info$distintos > 0) {
    info$minimo <- min(x, na.rm = TRUE)
    info$maximo <- max(x, na.rm = TRUE)
  }

  if (info$distintos > 0 && info$distintos <= MAX_VALORES) {
    tab <- table(as.character(x), useNA = "ifany")
    nombres <- names(tab)
    nombres[is.na(nombres)] <- "NULL"
    info$valores <- as.list(stats::setNames(as.integer(tab), nombres))
  }

  info
}


perfilar_fuente <- function(nombre, ruta, fecha) {
  df <- readRDS(here::here(ruta))
  columnas <- lapply(names(df), function(col) perfilar_columna(df[[col]]))
  names(columnas) <- names(df)

  list(
    fuente  = nombre,
    ruta    = ruta,
    fecha   = fecha,
    filas   = nrow(df),
    columnas = columnas
  )
}


main <- function(fecha = format(Sys.Date(), "%Y-%m-%d")) {
  carpeta <- file.path(DOC_CATALOGO, "perfil")
  dir.create(carpeta, recursive = TRUE, showWarnings = FALSE)

  for (nombre in names(FUENTES)) {
    perfil <- perfilar_fuente(nombre, FUENTES[[nombre]], fecha)
    salida <- file.path(carpeta, paste0("app_", nombre, "_", fecha, ".json"))
    write_json(perfil, salida, auto_unbox = TRUE, pretty = TRUE, na = "null")
    message("Perfil generado: ", salida)
  }

  invisible(TRUE)
}

# Ejecutar: main()
