library(pins)
library(dplyr)
library(gert)


# ==============================================================================
# limpieza_datos.R
# Correr este script LOCALMENTE (desde la raíz del proyecto APP_nuevoinforme/)
# para actualizar los datos en GitHub. La Shiny app lee desde board_url().
# ==============================================================================

# --- 1. Rutas de origen de los datos ---
ruta_origen_activos   <- "db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds"
ruta_origen_inactivos <- "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds"
ruta_origen_llenado   <- "db/GOL_reportes/historico_llenadoGol.rds"

# --- 2. Cargar los datos ---
message("📂 Cargando datos locales...")
GID_activos           <- readRDS(ruta_origen_activos)
GID_inactivos         <- readRDS(ruta_origen_inactivos)
historico_llenado_web <- readRDS(ruta_origen_llenado)
message("✅ Datos cargados.")

# --- 3. Escribir los pines localmente (SIN versiones) ---
message("📌 Escribiendo pines locales...")
ruta_board <- "vistas/App_informe_llenado/data"

# Borrar carpeta vieja para evitar versiones acumuladas
if (dir.exists(ruta_board)) {
  unlink(ruta_board, recursive = TRUE)
}

board <- pins::board_folder(ruta_board, versioned = FALSE)

board %>% pin_write(GID_activos,           "GID_activos",           type = "rds")
board %>% pin_write(GID_inactivos,         "GID_inactivos",         type = "rds")
board %>% pin_write(historico_llenado_web, "historico_llenado_web", type = "rds")

message("✅ Pines escritos en local.")

# --- 4. Subir cambios a GitHub con gert ---
message("🚀 Subiendo cambios a GitHub...")
tryCatch({

  git_add(ruta_board)

  cambios <- git_status() %>% filter(staged == TRUE)

  if (nrow(cambios) > 0) {
    git_commit("Actualización automatizada de datos (pins)")
    git_push()
    message("✅ ¡GitHub actualizado! La Shiny app ya tiene los datos nuevos.")
  } else {
    message("ℹ️ No hubo cambios en los datos. GitHub ya estaba al día.")
  }

}, error = function(e) {
  message("⚠️ Error al sincronizar con GitHub: ", e$message)
  message("   Los pines están actualizados localmente, pero no se subieron a GitHub.")
  message("   Podés hacer git push manual desde la terminal.")
})