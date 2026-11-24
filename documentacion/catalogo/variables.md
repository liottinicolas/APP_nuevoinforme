# Catálogo de variables — APP_nuevoinforme (verificado: 2026-11-18)

Columna **Tarea** indica dónde se usa. Las tareas se listan en el [README maestro](../README_MAESTRO.md).

| Variable | Tarea | Archivo | Tipo | Valor / ejemplo | Qué significa |
|---|---|---|---|---|---|
| `REPO_DATOS` | App Shiny de llenado | `App.R` | texto | `liottinicolas/APP_nuevoinforme-data` | Repo de GitHub donde están los pins. |
| `url_github` | App Shiny de llenado | `App.R` | URL | `https://raw.githubusercontent.com/<REPO_DATOS>/master/data/` | Base raw para leer los pins sin autenticación. |
| `global_board` | App Shiny de llenado | `App.R` | objeto pins | `board_folder("data")` o `board_url(url_github)` | Board de donde se leen los pins. Según el comentario, la carpeta local se usa en local y la URL en producción. POR CONFIRMAR: condición exacta de cambio. |
| `current_board` | App Shiny de llenado | `App.R` | objeto pins | `board_url(url_github)` | Board activo al cargar la app. |
| `url_repo_datos` | App Shiny de llenado | `limpieza_datos.R` | URL | `https://github.com/liottinicolas/APP_nuevoinforme-data.git` | Repo git que se clona o actualiza. |
| `ruta_repo_datos` | App Shiny de llenado | `limpieza_datos.R` | ruta | carpeta padre del proyecto + `APP_nuevoinforme-data` | Clon local del repo de datos. |
| `ruta_board` | App Shiny de llenado | `limpieza_datos.R` | ruta | `<ruta_repo_datos>\data` | Carpeta donde se escriben los pins. |
| `ruta_origen_activos` | App Shiny de llenado | `limpieza_datos.R` | ruta relativa | `db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds` | Entrada: contenedores activos. |
| `ruta_origen_inactivos` | App Shiny de llenado | `limpieza_datos.R` | ruta relativa | `db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds` | Entrada: contenedores inactivos (histórico). |
| `ruta_origen_llenado` | App Shiny de llenado | `limpieza_datos.R` | ruta relativa | `db/GOL_reportes/historico_llenadoGol.rds` | Entrada: histórico de llenado. |
| `ruta_origen_circuitos` | App Shiny de llenado | `limpieza_datos.R` | ruta relativa | `UNA_POR_CIRCUITO/rds/circuitos_periodo.rds` | Entrada: circuitos por período. |
| `GID_activos` | App Shiny de llenado | pin | sf / data.frame, RDS | — | Pin que publica los activos. |
| `GID_inactivos` | App Shiny de llenado | pin | sf / data.frame, RDS | — | Pin que publica los inactivos. |
| `historico_llenado_web` | App Shiny de llenado | pin | data.frame, RDS | — | Pin del histórico de llenado. |
| `circuitos_periodo` | App Shiny de llenado | pin | data.frame, RDS | — | Pin de circuitos por período. |
| `REPO_DATOS` (uso) | App Shiny de llenado | `App.R` | — | — | Ver arriba. |
| `THE_GEOM` | App Shiny de llenado | `App.R` | columna WKT | — | Geometría en texto. Se convierte con `st_as_sf(wkt = "THE_GEOM", crs = 32721)`. |

## Detalles de uso
- `board_url()` necesita `_pins.yaml`. Lo genera `write_board_manifest()`. Sin ese archivo, el pin devuelve 404.
- Los pins se escriben sin versionado (`versioned = FALSE`), así que siempre se lee la última versión.
