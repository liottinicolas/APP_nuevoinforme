# 02 · Descarga Automatizada

Tipo: R scripts (raíz del proyecto)

## 📖 ¿Qué hace?

Detectan qué días de datos faltan descargar de la intranet de la IM y disparan scripts Python con Playwright para automatizar la descarga (scraping de un portal APEX/GOL). Dos archivos casi idénticos, uno por fuente de datos.

## 📊 Entrada (Input)

- `funciones_descarga_consulta10393ubicaciones.R`: carpeta `archivos/10393_ubicaciones/*.csv` (nombre `YYYY-MM-DD.csv`), variables de entorno `APEX_USUARIO`/`APEX_CONTRASENA` (o prompt interactivo de RStudio), script `archivos/descargar_datos_10393_ubicaciones.py`
- `funciones_descarga_reportesGOL.R`: análogo, sobre `archivos/GOL_reportes/` y `archivos/descargar_datos_reportesGOL.py`

## 🔄 Proceso

1. Calcula `ultima_fecha` disponible (o `Sys.Date() - 10` si no hay archivos)
2. Genera la secuencia de fechas pendientes hasta `Sys.Date() - 1`
3. Resuelve credenciales (env vars o prompt)
4. Obtiene `reticulate::virtualenv_python("r-reticulate")`
5. Por cada fecha faltante: `system2(python_venv, args = c(script, fecha, usuario, contrasena))`
6. Si una descarga falla, `stop()` corta todo el loop

## 📤 Salida (Output)

- CSVs nuevos en `archivos/10393_ubicaciones/` y `archivos/GOL_reportes/` (generados por los scripts Python externos, fuera de este repo de análisis)

## 🔗 Dependencias

- R: `reticulate`, `rstudioapi` (opcional)
- Externos: `archivos/descargar_datos_10393_ubicaciones.py`, `archivos/descargar_datos_reportesGOL.py` (no incluidos en este análisis)

## ⚡ Mejoras Futuras

- [ ] **Riesgo de seguridad**: la contraseña se pasa como argumento de línea de comandos a Python vía `system2()` — puede quedar expuesta en logs o en el listado de procesos del sistema operativo. Preferir variables de entorno leídas directamente por el script Python, o un archivo de credenciales con permisos restringidos.
- [ ] Si falla una fecha intermedia, `stop()` corta todo el loop sin reintentar solo esa fecha ni continuar con las siguientes — considerar `tryCatch` por fecha (como sí hace `cargaDeDatos.R`).
- [ ] **Duplicación casi total de código** entre ambos scripts — candidato claro a refactor en una única función parametrizada por módulo, en línea con el patrón que ya usa `cargar_configuracion_modulo()` en `global.R`.

## 📌 Notas

Estos scripts se ejecutan al inicio de `nuevoinforme.R`, antes del ETL de `cargaDeDatos.R`.
