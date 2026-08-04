# 10 · App Informe de Llenado (`vistas/App_informe_llenado/`)

Tipo: Shiny App (R, `bs4Dash` + `leaflet`) + script de preparación de datos (`pins` + `gert`)

## 📖 ¿Qué hace?

"Gestión de GIDs - Montevideo": mapa interactivo de contenedores (GID) activos/inactivos y un histórico de llenado/vaciamiento consultable por GID individual. Es el único módulo con arquitectura de despliegue dual (local / Shiny Cloud vía GitHub).

## 📊 Entrada (Input)

- En local: pines en `vistas/App_informe_llenado/data/` (`GID_activos`, `GID_inactivos`, `historico_llenado_web`)
- En producción (Shiny Cloud): mismos pines vía `board_url()` apuntando a `raw.githubusercontent.com/liottinicolas/APP_nuevoinforme/main/vistas/App_informe_llenado/data/`
- Fuentes originales (para `limpieza_datos.R`): `db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds` (activos), `db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds` (inactivos), `db/GOL_reportes/historico_llenadoGol.rds`

## 🔄 Proceso

### `App.R`
`reactivePoll` recarga datos cada 10 minutos comprobando `mtime` local o SHA del último commit remoto (vía API de GitHub). `preprocesar_datos()` transforma geometrías WKT a `sf` (EPSG:32721 → WGS84 4326). Pestaña "Mapa Interactivo": `leafletProxy` con clustering opcional, popups con botón "Ver Historial"; búsqueda por GID o por dirección (geocodifica contra Nominatim/OpenStreetMap). Pestaña "Histórico": filtra por GID, calcula KPIs (visitas totales, último % llenado, llenado promedio, estado activo/inactivo) y tabla `DT`.

### `limpieza_datos.R` — preparación de datos (ETL manual, no runtime)
Convierte los `.rds` fuente en pines (`pins::pin_write`) dentro de `data/`, y sube automáticamente a GitHub con `gert` (`git_add` acotado a la carpeta de datos, commit condicional, push).

### `limpieza_datos-939868WN.R` — versión anterior
Copia previa del script anterior; usa `git_add(".")` (todo el working directory) en vez de acotar a la carpeta de datos — la versión vigente es más segura.

## 📤 Salida (Output)

- Dashboard Shiny interactivo (mapa + tabla), sin generación de archivos en runtime
- Pines actualizados + commit/push a GitHub (por `limpieza_datos.R`)

## 🔗 Dependencias

- R: `shiny`, `bs4Dash`, `leaflet`, `leaflet.extras`, `sf`, `pins`, `dplyr`, `DT`, `jsonlite`, `httr`, `gert`

## ⚡ Mejoras Futuras

- [ ] Llamadas a Nominatim para geocodificar direcciones no tienen caché — riesgo de rate-limiting si se buscan muchas direcciones seguidas.
- [ ] El flujo de auto-commit + push automatizado dentro de un script de datos (`limpieza_datos.R`) es riesgoso operativamente (puede generar pushes accidentales o conflictos) — considerar revisión manual antes de push, o un paso de confirmación.
- [ ] **Hallazgo transversal importante**: el sufijo `-939868WN` en `limpieza_datos-939868WN.R` es un patrón de **conflicto de sincronización de OneDrive** (device ID), no una convención del proyecto. Se encontró el mismo sufijo en archivos internos de `.git/` (`.git/index-939868WN`, `.git/logs/HEAD-939868WN`), en `.Rproj.user/` y en xlsx de `informediario/reportes/archivos/`. Esto indica que **el repositorio Git vive dentro de una carpeta sincronizada por OneDrive**, con riesgo real de corrupción del repo. Ver recomendación en [../improvements.md](../improvements.md).
- [ ] Eliminar `limpieza_datos-939868WN.R` una vez confirmado que es un duplicado de conflicto y no una versión con cambios propios pendientes de revisar.

## 📌 Notas

Es el único módulo geoespacial de `vistas/` (no mide volúmenes/incidencias sino estado y ubicación de contenedores individuales), y el único con arquitectura de despliegue local/nube basada en `pins` + GitHub.
