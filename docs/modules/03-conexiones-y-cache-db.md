# 03 · Conexiones y Caché de Datos (`db/`)

Tipo: R scripts (conexión + ingesta)

## 📖 ¿Qué hace?

Define las conexiones a las fuentes de datos externas (PostgreSQL/PostGIS de la IM, GeoServer WFS autenticado) y las funciones de ingesta que transforman los CSVs diarios crudos en históricos normalizados. Ver el detalle completo de fuentes en [../data-sources.md](../data-sources.md).

## 📊 Entrada (Input)

- **PostgreSQL** `pdbqgistest.imm.gub.uy:5411`, base `qgis` — vía `db/POSTGRES/conexionPOSTGRES.R`
- **GeoServer WFS autenticado** `https://geoserver-ed.imm.gub.uy/geoserver/wfs` (capas prefijo `dfr:`) — vía `db/DFR/conexionDFR.R` (duplicado en `endesuso/conexionDFR.R`)
- CSVs de `archivos/10393_ubicaciones/AAAA/MM_mes/YYYY-MM-DD.csv` (ISO-8859-1) — vía `db/10393_ubicaciones/funciones_db_ubicaciones.R`
- CSVs de `archivos/GOL_reportes/AAAA/MM_mes/YYYY-MM-DD.csv` (UTF-8) — vía `db/GOL_reportes/funciones_db_golReportesDiarios.R`

## 🔄 Proceso

### `db/POSTGRES/conexionPOSTGRES.R`
```r
conectar_postgres(host, port, dbname, user, password)   # valores por defecto hardcodeados
listar_tablas_postgres(con)
leer_capa_postgres(con, tabla, schema = "public")
actualizar_capa_postgres(con, tabla, schema, base_dir = "db/POSTGRES")
cargar_capa_local_postgres(tabla, base_dir, formato = c("RDS", "GPKG"))
cargar_capas_barrido(con = NULL, base_dir, formato)   # filtra tablas barrido|papeleo|avenida, fallback a disco
```
También define `df_flota` (matrículas/marca/base/servicio de camiones, hardcodeado), reutilizado por `Pesadas_Intra.R`, `Visor_vehiculos.R` y `prueba_api.R`.

### `db/DFR/conexionDFR.R`
```r
cargar_capas_wfs(url_base, prefijo, usuario)   # GetCapabilities + st_read por capa (WFS: DSN con user:pass en URL)
guardar_capas_wfs()
cargar_capas_local()
im_base_map() / im_add_capa() / im_capas_control() / im_exportar_html()   # helpers Leaflet genéricos
```
Solicita usuario/contraseña IMM interactivamente vía `rstudioapi`.

### `db/10393_ubicaciones/funciones_db_ubicaciones.R`
```r
funcion_actualizar_ubicaciones_10393(rutas_completas, rutas_relativas)
obtener_ubicaciones_por_fecha(fecha)
```
Valida que la fecha del nombre de archivo no sea futura, renombra columnas (`GID`→`gid`, `Recorrido`→`Circuito`), clasifica `Oficina` (regex `^B.*_0?[1-7]$` → Fideicomiso) y deriva `Municipio`/`Circuito_corto`.

### `db/GOL_reportes/funciones_db_golReportesDiarios.R`
```r
funcion_actualizar_llenadoGOL(rutas_completas, rutas_relativas)
```
Une todos los CSV, parsea `dia_viaje`/`fecha_pasaje`, limpia `condiciones_contenedor`, corrige formato WKT de `the_geom`, deriva `cod_recorrido`/`Municipio`, clasifica `Oficina` (regex `^B_0?[1-7]`).

## 📤 Salida (Output)

- `db/POSTGRES/RDS/*.rds`, `db/POSTGRES/GPKG/capas.gpkg`
- `db/DFR/RDS/*.rds`, `db/DFR/GPKG/capas.gpkg`
- Históricos consolidados `db/10393_ubicaciones/historico_ubicaciones.rds`, `db/GOL_reportes/historico_llenadoGol.rds` (persistidos por `cargaDeDatos.R`, que llama a estas funciones)

## 🔗 Dependencias

- R: `DBI`, `RPostgres`, `sf`, `httr`, `xml2`, `stringr`, `rstudioapi`, `dplyr`, `purrr`, `readr`, `tools`

## ⚡ Mejoras Futuras

- [ ] 🔴 **Crítico — credencial hardcodeada**: `db/POSTGRES/conexionPOSTGRES.R` tiene usuario `qgis` y contraseña `mapa22` en texto plano como valores por defecto de `conectar_postgres()`. Migrar a variables de entorno o `keyring`/`.Renviron`, y rotar la contraseña ya expuesta en el repositorio.
- [ ] **Archivo duplicado**: `endesuso/conexionDFR.R` es una copia exacta de `db/DFR/conexionDFR.R` — mantenimiento duplicado, riesgo de desincronización. Eliminar la copia de `endesuso/` y dejar una sola fuente de verdad.
- [ ] La contraseña del WFS DFR se embebe en la URL del DSN de GDAL (`URLencode`) — puede quedar expuesta en logs de error de GDAL/sf.
- [ ] Función `arreglar_direcciones()` referenciada en `funciones_db_ubicaciones.R` está comentada/deshabilitada — revisar si es una dependencia externa faltante.
- [ ] Reglas de clasificación de Oficina/Municipio por regex están hardcodeadas en 3 archivos distintos (ubicaciones, GOL, informe_operativa) — considerar centralizar en una única función/constante compartida.
- [ ] El parseo de `dia_viaje` en GOL depende del locale español del sistema (`%A/%m/%d`) — puede fallar silenciosamente en otro locale/SO.

## 📌 Notas

`conexionPOSTGRES.R` mezcla definición de conexión con datos de negocio (`df_flota`) y bloques grandes de código comentado/experimental — sería más mantenible separar la conexión de la tabla de flota en archivos distintos.
