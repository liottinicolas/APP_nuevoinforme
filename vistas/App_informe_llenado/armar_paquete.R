# ==============================================================================
# armar_paquete.R
# Arma una carpeta independiente (y un .zip) para que otra persona actualice y
# publique la app "Informe de llenado" desde su PC, sin OneDrive, sin GitHub y
# sin el resto del proyecto.
#
# Correr desde la raíz del proyecto APP_nuevoinforme (abrir el .Rproj):
#   source("vistas/App_informe_llenado/armar_paquete.R")
#   armar_paquete()                       # deja el paquete en el Escritorio
#   armar_paquete("C:/ruta/que/quieras")  # o en otra carpeta
#
# Qué copia:
#   - la app (App.R, informe_pdf.R, informe_excel.R, fonts/, rsconnect/)
#   - los scripts de paquete_independiente/ (LEEME.md, actualizar_y_publicar.R, ...)
#   - el descargador de levantes (archivos/descargar_datos_reportesGOL.py)
#   - los datos actuales, en datos/:
#       historico_llenado.rds   <- db/GOL_reportes/historico_llenadoGol.rds
#                                  (historial completo, solo las columnas de la app;
#                                   al publicar se suben los últimos 4 meses)
#       GID_activos.rds         <- db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds
#       GID_inactivos.rds       <- db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds
#       circuitos_periodo.rds   <- UNA_POR_CIRCUITO/rds/circuitos_periodo.rds
#
# No copia contraseñas ni el token de shinyapps.io: eso se configura en la otra PC.
# ==============================================================================

armar_paquete <- function(destino = file.path(Sys.getenv("USERPROFILE"), "Desktop",
                                              "App_informe_llenado_paquete"),
                          sobrescribir = FALSE, hacer_zip = TRUE) {
  if (!file.exists("APP_nuevoinforme.Rproj")) {
    stop("Correr desde la raíz del proyecto APP_nuevoinforme (abrí el .Rproj).")
  }
  dir_app  <- "vistas/App_informe_llenado"
  plantilla <- file.path(dir_app, "paquete_independiente")

  if (dir.exists(destino)) {
    if (!sobrescribir) {
      stop("Ya existe ", destino, ". Borrala, elegí otra carpeta o usá sobrescribir = TRUE.")
    }
    unlink(destino, recursive = TRUE, force = TRUE)
  }

  # Carpetas
  for (d in c("app", "datos", "descargas", "funciones")) {
    dir.create(file.path(destino, d), recursive = TRUE, showWarnings = FALSE)
  }

  # Scripts del paquete
  file.copy(list.files(plantilla, full.names = TRUE, all.files = TRUE, no.. = TRUE),
            destino, recursive = TRUE, overwrite = TRUE)

  # La app (sin limpieza_datos.R, App_v2.R ni documentación)
  file.copy(file.path(dir_app, c("App.R", "informe_pdf.R", "informe_excel.R")),
            file.path(destino, "app"))
  file.copy(file.path(dir_app, c("fonts", "rsconnect")), file.path(destino, "app"),
            recursive = TRUE)

  # Descargador de levantes (los CSV quedan en descargas/GOL_reportes/)
  file.copy("archivos/descargar_datos_reportesGOL.py", file.path(destino, "descargas"))

  # Datos
  message("Copiando datos...")
  source(file.path(plantilla, "funciones", "funciones_paquete.R"), local = TRUE, encoding = "UTF-8")
  hist <- seleccionar_columnas(readRDS("db/GOL_reportes/historico_llenadoGol.rds"))
  saveRDS(hist, file.path(destino, "datos", "historico_llenado.rds"))
  file.copy("db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds",
            file.path(destino, "datos", "GID_activos.rds"))
  file.copy("db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds",
            file.path(destino, "datos", "GID_inactivos.rds"))
  file.copy("UNA_POR_CIRCUITO/rds/circuitos_periodo.rds",
            file.path(destino, "datos", "circuitos_periodo.rds"))
  saveRDS(character(0), file.path(destino, "datos", "csv_procesados.rds"))

  message("✅ Paquete armado en: ", normalizePath(destino),
          "\n   Datos hasta el ", format(max(as.Date(hist$Fecha), na.rm = TRUE), "%d/%m/%Y"),
          " (", nrow(hist), " filas).")

  if (hacer_zip) {
    archivo_zip <- paste0(destino, ".zip")
    if (file.exists(archivo_zip)) file.remove(archivo_zip)
    zip::zip(archivo_zip, files = basename(destino), root = dirname(destino))
    message("✅ Zip: ", normalizePath(archivo_zip), " (",
            round(file.size(archivo_zip) / 1024^2), " MB). Este es el archivo para mandar.")
  }
  invisible(destino)
}
