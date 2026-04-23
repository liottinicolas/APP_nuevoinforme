library(pins)
# install.packages("gert") # Instala este paquete si aún no lo tienes
library(gert) 

# 1. Definir rutas de origen de los datos
ruta_origen_activos   <- "db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds"
ruta_origen_inactivos <- "db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds"
ruta_origen_llenado   <- "db/GOL_reportes/historico_llenadoGol.rds"

# 2. Cargar los datos a la memoria de R
GID_activos           <- readRDS(ruta_origen_activos)
GID_inactivos         <- readRDS(ruta_origen_inactivos)
historico_llenado_web <- readRDS(ruta_origen_llenado)

# 3. Inicializar UN solo tablero local (dentro de tu repositorio Git)
# Asumimos que la carpeta del proyecto R es el repositorio de "APP_nuevoinforme"
# 3. Inicializar UN solo tablero local
ruta_board <- "vistas/App_informe_llenado/data"

# 🔥 LA SOLUCIÓN: Borramos la carpeta entera si ya existe para limpiar versiones viejas
if (dir.exists(ruta_board)) {
  unlink(ruta_board, recursive = TRUE)
}

# Ahora creamos el tablero totalmente limpio y sin versiones
board <- board_folder(ruta_board, versioned = FALSE)
# 4. Actualizar los pines localmente
board %>% pin_write(GID_activos, "GID_activos", type = "rds")
board %>% pin_write(GID_inactivos, "GID_inactivos", type = "rds")
board %>% pin_write(historico_llenado_web, "historico_llenado_web", type = "rds")

message("✅ Pines actualizados en local.")

# 5. Sincronizar automáticamente con GitHub usando 'gert'
tryCatch({
  # Agregamos todos los archivos dentro de la carpeta de datos
  # Usamos "." para asegurarnos de capturar todo lo que cambió en el directorio de trabajo
  git_add(".") 
  
  # Verificamos si hay archivos en el "staged" (listos para commit)
  cambios <- git_status() %>% filter(staged == TRUE)
  
  if (nrow(cambios) > 0) {
    # Si hay cambios, procedemos
    git_commit("Actualización automatizada de datos (pins)")
    git_push()
    message("✅ Sincronización completa: GitHub actualizado exitosamente.")
  } else {
    # Si no hay cambios, simplemente avisamos sin lanzar error
    message("ℹ️ No se detectaron cambios en los datos. No fue necesario actualizar GitHub.")
  }
  
}, error = function(e) {
  message("⚠️ Hubo un error al intentar sincronizar con GitHub:")
  message(e$message)
})
