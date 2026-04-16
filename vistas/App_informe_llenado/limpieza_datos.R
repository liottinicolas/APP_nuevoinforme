library(pins)

# 1. Definir rutas (usando / para evitar errores de escape)
ruta_origen_activos   <- "db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds"
ruta_origen_inactivos <- "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds"
# Nueva ruta para el reporte de llenado GOL
ruta_origen_llenado   <- "db/GOL_reportes/historico_llenadoGol.rds"

ruta_destino_carpeta  <- "vistas/App_informe_llenado/data"

# 2. Cargar los dataframes a la memoria de R
GID_activos       <- readRDS(ruta_origen_activos)
GID_inactivos     <- readRDS(ruta_origen_inactivos)
historico_llenado <- readRDS(ruta_origen_llenado)

# 3. Configurar el Board (el tablero) en la carpeta de la App
board <- board_folder(ruta_destino_carpeta)

# 4. Escribir los pins
board %>% pin_write(GID_activos, "GID_activos", type = "rds")
board %>% pin_write(GID_inactivos, "GID_inactivos", type = "rds")
# Guardamos el nuevo pin
board %>% pin_write(historico_llenado, "historico_llenado", type = "rds")

message("✅ Los tres pins se han actualizado correctamente en la carpeta data.")