# 06 · Scripts Batch de Limpieza Urbana (`scripts/`)

Tipo: R scripts + Python scripts (automatización QGIS)

## 📖 ¿Qué hace?

Actualiza y unifica capas geoespaciales de limpieza urbana (barrido mecánico/manual, papeleo, avenidas) desde PostgreSQL, genera reportes de puntos críticos (KML/Excel), y automatiza la actualización diaria de 3 proyectos QGIS de mapas de recolección.

## 📊 Entrada (Input)

- PostgreSQL vía `db/POSTGRES/conexionPOSTGRES.R` (capas de barrido/papeleo/avenidas)
- Servicio WFS externo `montevideo.gub.uy/app/geoserver` (límites de municipios)
- Data frame en memoria (histórico de llenado) para `generar_mapas_KML.R`
- CSVs `vistas/informediario/reportes/Mapas/{Atraso|Repite|UNA} YYYY-MM-DD.csv` y Excel `archivo_informe {fecha} *.xlsx` (hoja "Datos Mapas") — para los scripts QGIS
- Proyectos QGIS `.qgz` en unidad de red `G:\Desarrollo Ambiental\Limpieza\...`

## 🔄 Proceso

### `scripts/barrido/barrido.R`
```r
unificar_capas_barrido()      # armoniza CRS, resuelve conflictos de tipo, calcula Responsable/Municipio/Tipo_barrido vía st_intersects
actualizar_capa_postgres()    # actualiza cada capa "barrido|papeleo|avenida" encontrada
```

### `scripts/generar_mapas_KML.R`
```r
generar_reportes_limpieza(df, ...)   # top N puntos críticos (Basura Afuera/Escombro/Poda) por denuncias
```
Exporta Excel (`openxlsx`) y KML (transformando de EPSG:32721 a EPSG:4326).

### `scripts/qgis/qgis_mapaAtraso.py`, `qgis_mapaRepetidos.py`, `qgis_mapaUNA.py`
Automatizan, fuera de PyQGIS, la actualización diaria de 3 proyectos QGIS manipulando directamente el XML del `.qgz`: localizan el proyecto con `glob`, buscan el CSV/Excel más reciente por fecha en el nombre, inyectan/actualizan capa, *join* espacial y simbología categorizada, y actualizan textos del layout de impresión (fecha, % leídos de Excel).

## 📤 Salida (Output)

- `db/POSTGRES/RDS/*.rds`, `db/POSTGRES/GPKG/capas.gpkg`, y `scripts/barrido/db/df_barrido_unido.parquet` (para consumo Python/JupyterHub)
- Excel de puntos críticos + KML
- Proyectos `.qgz` actualizados in-place, listos para exportar a PDF desde QGIS Desktop

## 🔗 Dependencias

- R: `here`, `dplyr`, `sf`, `DBI`, `RPostgres`, `openxlsx`, opcionalmente `sfarrow`/`arrow`
- Python: `os`, `glob`, `zipfile`, `re`, `uuid`, `datetime`, `xml.etree.ElementTree`, `pandas` (sin librerías de terceros de geoprocesamiento)

## ⚡ Mejoras Futuras

- [ ] Los scripts QGIS requieren que QGIS Desktop esté cerrado (bloqueo de archivo) — documentar este requisito operativo de forma visible para quien ejecute el pipeline.
- [ ] Rutas hardcodeadas a la unidad de red `G:\...` específica de una máquina/usuario — frágil ante cambios de nombre de carpeta o de máquina que ejecuta el proceso.
- [ ] La manipulación de XML por reemplazo de texto en la simbología es frágil ante cambios de estructura del proyecto QGIS (ej. actualización de versión de QGIS) — considerar migrar a PyQGIS si se dispone del entorno.
- [ ] `barrido.R` descarga en vivo desde el WFS público de Montevideo sin manejo de reintentos — agregar `tryCatch`/retry ante caídas puntuales del servicio.

## 📌 Notas

Estos scripts no se listan explícitamente en el `source()` de `nuevoinforme.R` salvo los 3 QGIS (invocados vía `system2` en la sección 4 del orquestador); `barrido.R` y `generar_mapas_KML.R` parecen ejecutarse de forma independiente/manual.
