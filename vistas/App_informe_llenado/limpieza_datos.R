library(pins)

# 1. Definir rutas de origen de los datos
ruta_origen_activos   <- "db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds"
ruta_origen_inactivos <- "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds"
ruta_origen_llenado   <- "db/GOL_reportes/historico_llenadoGol.rds"

# 2. Cargar los datos a la memoria de R
GID_activos       <- readRDS(ruta_origen_activos)
GID_inactivos     <- readRDS(ruta_origen_inactivos)
historico_llenado_web <- readRDS(ruta_origen_llenado)

# 3. Inicializar los dos tableros (Boards)
# --- Board Local ---
board_local <- board_folder("vistas/App_informe_llenado/data")

# --- Board GitHub ---
board_nube <- pins:::board_github(
  repo = "liottinicolas/APP_nuevoinforme",
  path = "data",
  token = Sys.getenv("GITHUB_PAT")
)

# 4. Función para escribir en ambos boards (para no repetir código)
actualizar_pins <- function(objeto, nombre_pin) {
  # Guardar en local
  board_local %>% pin_write(objeto, nombre_pin, type = "rds")
  # Guardar en GitHub
  board_nube %>% pin_write(objeto, nombre_pin, type = "rds")
}

# 5. Ejecutar la actualización masiva
actualizar_pins(GID_activos, "GID_activos")
actualizar_pins(GID_inactivos, "GID_inactivos")
actualizar_pins(historico_llenado_web, "historico_llenado_web")

message("✅ Sincronización completa: Local y GitHub actualizados.")