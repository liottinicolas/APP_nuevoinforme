# ==============================================================================
# token_shinyapps_EJEMPLO.R  (este archivo NO tiene el token: es un modelo)
#
# Para que el paquete independiente lleve el token de shinyapps.io adentro:
#   1. Copiá este archivo en la misma carpeta con el nombre  token_shinyapps.R
#   2. En token_shinyapps.R, reemplazá la línea de abajo por el comando que da
#      shinyapps.io → Tokens → Show → Show Secret → Copy to clipboard.
#   3. Guardá. armar_paquete() lo copia al zip y actualizar_y_publicar.R lo usa
#      solo si la PC no tiene la cuenta configurada.
#
# token_shinyapps.R está en .gitignore: NUNCA se sube a GitHub (el repo es
# público). Tampoco se publica con la app (.rscignore).
# Si el token se filtra: shinyapps.io → Tokens → borrarlo y crear otro.
# ==============================================================================

rsconnect::setAccountInfo(name = "datoseindicadores", token = "PEGAR_TOKEN", secret = "PEGAR_SECRET")
