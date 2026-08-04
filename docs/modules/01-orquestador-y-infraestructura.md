# 01 · Orquestador e Infraestructura

Tipo: R scripts (raíz del proyecto)
Última modificación: ver `git log` de cada archivo

## 📖 ¿Qué hace?

Este grupo de scripts constituye el **punto de entrada y la infraestructura común** del pipeline. `nuevoinforme.R` es el orquestador manual que se ejecuta para correr todo el ciclo diario; `global.R` y `funciones_utiles.R` son librerías de soporte (logging, entorno, generación de PDFs, sincronización con GitHub); `cargaDeDatos.R` es el motor ETL incremental; `conexionDSN.R` provee acceso a capas WFS públicas de Montevideo.

## 📊 Entrada (Input)

- CSVs nuevos en `archivos/GOL_reportes/` y `archivos/10393_ubicaciones/` (nombre `YYYY-MM-DD.csv`)
- WFS público `https://montevideo.gub.uy/app/geoserver/ows`, `http://geoserver.montevideo.gub.uy/geoserver/wfs`
- API intranet `https://intranet.imm.gub.uy/app/limpieza-gestion-operativa/api/frontend/v1/contenedores` (y `/circuitos`)
- RDS de registro de archivos ya procesados por módulo

## 🔄 Proceso

### `nuevoinforme.R` — orquestador principal
Ejecuta en orden, vía `source()`: `global.R` → `funciones_utiles.R` → `funciones_descarga_consulta10393ubicaciones.R` → `funciones_descarga_reportesGOL.R` → `cargaDeDatos.R` → `informes/informe_diario.R` → `informes/informecamiones.R` → `db/DFR/conexionDFR.R`. Luego:
1. Actualiza capas WFS del DFR (`actualizar_capas_wfs(base_dir="db/DFR")`)
2. Genera PDFs en R (`generar_reporte_pdf_camionesylevantesIMFID`)
3. Genera PDFs en Python vía `reticulate` + `system2()`: `informeOP_generar_pdf.py`, `actualizar_ayer.py` → `generar_mapas.py`, y 3 scripts QGIS
4. Sincroniza la app Shiny (`vistas/App_informe_llenado/limpieza_datos.R`, que hace pin+push a GitHub)

### `global.R` — infraestructura
```r
preparar_entorno(paquetes = NULL, tz = "America/Montevideo")
cargar_configuracion_modulo(modulo, nombre_archivo_funcion = NULL, nombre_archivo_historico = NULL)
escribir_log(nivel, mensaje)
manejar_error(err, contexto)
cargar_archivo(ruta_archivo)   # source() envuelto en tryCatch
```
`preparar_entorno()` setea timezone/opciones, define ~30 paquetes por defecto e instala los faltantes automáticamente. `cargar_configuracion_modulo()` resuelve las 4 rutas estándar de cada módulo de datos con `here()`.

### `cargaDeDatos.R` — ETL incremental
```r
actualizar_planillas_RDS(ruta_funciones, ruta_carpeta_archivos, ruta_RDS_datos, ruta_RDS_archivos_procesados)
```
Detecta CSVs nuevos vía `fs::dir_ls`, valida nombre/fecha (no futura), procesa cada uno con `tryCatch` (los fallidos se reintentan la próxima corrida), acumula con `bind_rows()` + `distinct()` y persiste con `saveRDS`.

### `conexionDSN.R`
Funciones `cargar_capa_mvd()` / `descargar_capa_mvd()` para consultar el catálogo WFS público de Montevideo (+30 capas documentadas en comentarios). El resto del archivo es en gran parte scratch/pruebas (mapas Leaflet de ejemplo, definición de `df_flota`).

## 📤 Salida (Output)

- `db/GOL_reportes/historico_llenadoGol.rds`, `db/10393_ubicaciones/historico_ubicaciones.rds` y sus RDS de "archivos aplicados"
- PDFs, mapas y capas DFR actualizadas
- Datos "pineados" en GitHub para la app Shiny

## 🔗 Dependencias

- R: `here`, `fs`, `dplyr`, `reticulate`, `processx`, `sf`, `httr`/`httr2`, `xml2`, `jsonlite`, `leaflet`
- Scripts: sourcea prácticamente todo el resto del proyecto

## ⚡ Mejoras Futuras

- [ ] **`nuevoinforme.R` tiene una llamada activa con fecha hardcodeada** (`generar_reporte_pdf_camionesylevantesIMFID(fecha = "2026-02-17", ...)`) justo antes de la llamada real con `fecha = NULL` — parece resto de una prueba, generaría un PDF duplicado/incorrecto en cada corrida real. Eliminar esa línea.
- [ ] `nuevoinforme.R` no valida el código de salida de los `system2()` a scripts Python intermedios — un fallo silencioso en `actualizar_ayer.py` no detendría `generar_mapas.py`, que depende de él.
- [ ] `conexionDSN.R` contiene una línea de texto en español pegada como código plano (alrededor de la línea 213-217, "¡Excelentes noticias!...") que rompería la ejecución del script tal cual está — parece pegado accidentalmente de una explicación de chat. Eliminar.
- [ ] `preparar_entorno()` instala paquetes automáticamente sin confirmación — considerar un modo "dry run" o log explícito de qué se instaló.

## 📌 Notas

`global.R` está bien diseñado y documentado; es el módulo más sólido de este grupo. `conexionDSN.R`, en cambio, funciona más como notebook de exploración que como librería limpia.
