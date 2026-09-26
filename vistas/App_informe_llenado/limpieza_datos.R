library(pins)
library(dplyr)
library(gert)


# ==============================================================================
# limpieza_datos.R
# Correr este script LOCALMENTE (desde la raíz del proyecto APP_nuevoinforme/)
# para actualizar los datos que lee la Shiny app deployada (App.R via board_url()).
#
# Los pines se publican en un repo de GitHub APARTE (APP_nuevoinforme-data),
# no en este repo de código: así el historial de código no se llena de copias
# binarias nuevas en cada corrida. Si el repo de datos no existe localmente
# todavía, se clona; si ya existe, se actualiza antes de escribir los pines.
# ==============================================================================

# --- 0. Repo de datos (separado de este repo de código) ---
ruta_repo_datos <- normalizePath(
  file.path(dirname(here::here()), "APP_nuevoinforme-data"),
  mustWork = FALSE
)
url_repo_datos <- "https://github.com/liottinicolas/APP_nuevoinforme-data.git"

if (!dir.exists(ruta_repo_datos)) {
  message("📥 Clonando repo de datos en ", ruta_repo_datos, "...")
  git_clone(url_repo_datos, ruta_repo_datos)
} else {
  message("📥 Actualizando repo de datos local...")
  # Si el repo remoto todavia no tiene ningun commit (primera vez), el clone
  # local no queda con upstream configurado y el pull falla - no es un error
  # real, solo no hay nada que traer todavia.
  tryCatch(
    git_pull(repo = ruta_repo_datos),
    error = function(e) message("   (nada para traer todavia: ", conditionMessage(e), ")")
  )
}

# --- 1. Rutas de origen de los datos ---
ruta_origen_activos   <- "db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds"
ruta_origen_inactivos <- "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds"
ruta_origen_llenado   <- "db/GOL_reportes/historico_llenadoGol.rds"
# Una fila por circuito con Municipio, Oficina y Periodo (la genera
# UNA_POR_CIRCUITO/scripts/funciones_periodo.R en cada corrida del pipeline UNA)
ruta_origen_circuitos <- "UNA_POR_CIRCUITO/rds/circuitos_periodo.rds"

# --- 2. Cargar los datos ---
message("📂 Cargando datos locales...")
GID_activos           <- readRDS(ruta_origen_activos)
GID_inactivos         <- readRDS(ruta_origen_inactivos)
historico_llenado_web <- readRDS(ruta_origen_llenado)
circuitos_periodo     <- readRDS(ruta_origen_circuitos)
message("✅ Datos cargados.")

# --- 3. Recortar el histórico de llenado (retención de 12 meses) ---
# La app solo consulta el estado reciente de un GID; se limita a los últimos
# 12 meses y a las columnas que App.R realmente usa para reducir el peso del
# pin (impacta directamente en el tiempo de carga en frío de la Shiny app).
message("✂️  Recortando histórico de llenado a los últimos 12 meses...")
peso_original_mb <- round(object.size(historico_llenado_web) / 1024^2, 1)

historico_llenado_web <- historico_llenado_web %>%
  filter(as.Date(Fecha) >= (Sys.Date() - 365)) %>%
  select(
    gid, Fecha, Fecha_hora_pasaje, Municipio, Oficina, Circuito_corto,
    Posicion, Direccion, Levantado, Turno_levantado, Id_viaje_GOL,
    Incidencia, Porcentaje_llenado, Condicion, contenedor_activo
  )

peso_recortado_mb <- round(object.size(historico_llenado_web) / 1024^2, 1)
message(sprintf(
  "   %s MB -> %s MB (%s filas)",
  peso_original_mb, peso_recortado_mb, nrow(historico_llenado_web)
))

# --- 4. Escribir los pines localmente (SIN versiones) ---
message("📌 Escribiendo pines locales...")
ruta_board <- file.path(ruta_repo_datos, "data")

# Borrar carpeta vieja para evitar versiones acumuladas
if (dir.exists(ruta_board)) {
  unlink(ruta_board, recursive = TRUE)
}

board <- pins::board_folder(ruta_board, versioned = FALSE)

board %>% pin_write(GID_activos,           "GID_activos",           type = "rds")
board %>% pin_write(GID_inactivos,         "GID_inactivos",         type = "rds")
board %>% pin_write(historico_llenado_web, "historico_llenado_web", type = "rds")
board %>% pin_write(circuitos_periodo,     "circuitos_periodo",     type = "rds")

# board_url() (usado por App.R en producción) necesita este manifest para
# poder resolver, a partir de una URL base fija, la subcarpeta con hash de
# versión que pin_write genera en cada corrida (sin esto, App.R apunta a una
# URL que ya no existe y el pin_read falla con 404).
pins::write_board_manifest(board)

message("✅ Pines escritos en local.")

# --- 5. Subir cambios a GitHub con gert (al repo de DATOS, no al de código) ---
message("🚀 Subiendo cambios a GitHub...")
tryCatch({

  git_add("data", repo = ruta_repo_datos)

  cambios <- git_status(repo = ruta_repo_datos) %>% filter(staged == TRUE)

  if (nrow(cambios) > 0) {
    git_commit("Actualización automatizada de datos (pins)", repo = ruta_repo_datos)
    git_push(repo = ruta_repo_datos)
    message("✅ ¡GitHub actualizado! La Shiny app ya tiene los datos nuevos.")
  } else {
    message("ℹ️ No hubo cambios en los datos. GitHub ya estaba al día.")
  }

}, error = function(e) {
  message("⚠️ Error al sincronizar con GitHub: ", e$message)
  message("   Los pines están actualizados localmente, pero no se subieron a GitHub.")
  message("   Podés hacer git push manual desde ", ruta_repo_datos)
})