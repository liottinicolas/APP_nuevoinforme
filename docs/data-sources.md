# Fuentes de Datos

## Base de Datos: PostgreSQL / PostGIS "qgis" (Intendencia de Montevideo)

- **Host:** `pdbqgistest.imm.gub.uy:5411`, base `qgis`
- **Definida en:** `db/POSTGRES/conexionPOSTGRES.R`, función `conectar_postgres()`
- ⚠️ **Contiene credenciales hardcodeadas en texto plano** (usuario `qgis`, contraseña `mapa22` como valores por defecto de la función) — ver [docs/improvements.md](improvements.md).
- **Reutilizada por:** `scripts/barrido/barrido.R`, `Visor_vehiculos.R`, `Visor_hogares_sustentables.R`, `prueba_api.R`, `Pesadas_Intra.R` (todos vía `source("db/POSTGRES/conexionPOSTGRES.R")`)
- **Tablas/capas principales:** `Intradomiciliario_operativo`, `Intra_proximo`, `Circuitos_intradomiciliaria`, `Circuitos con turnos y frecuencias`, `Hogares_sustentables`, `PLUMA_movimientos`, `papeleras`, capas de `barrido`/`papeleo`/`avenida*` (esquema `public`). Otras referenciadas en comentarios pero no necesariamente activas: `FIDEICOMISO_POSICIONES_MR`, `FIDEICOMISO_RUTA_MR`, `FIDEICOMISO_ZONA_MR`, `RBB_*`, `RECOLECCION MANUAL *`, `imm_municipios`, `pos_ferias`.

## GeoServer WFS autenticado (capas DFR)

- **Endpoint:** `https://geoserver-ed.imm.gub.uy/geoserver/wfs`
- **Definida en:** `db/DFR/conexionDFR.R` (duplicado exacto en `endesuso/conexionDFR.R` — ver mejoras)
- **Autenticación:** usuario/contraseña IMM solicitados interactivamente vía `rstudioapi` (no hardcodeada), pero la contraseña se inserta en la URL del DSN de GDAL (riesgo de exposición en logs de error).
- **Capas:** prefijo `dfr:` — rutas, posiciones y zonas de recorrido, direcciones, contenedores CAP, contenedores soterrados.

## GeoServer WFS público de Montevideo (sin autenticación)

- **Endpoints:** `https://montevideo.gub.uy/app/geoserver/ows` (WFS 1.2.0/2.0.0), `http://geoserver.montevideo.gub.uy/geoserver/wfs`, `https://montevideo.gub.uy/app/geoserver/mapstore-tematicas/...` (límites de municipios, usado en `unificar_capas_barrido()`)
- **WMS base:** `https://montevideo.gub.uy/app/geowebcache/service/wms` (capa `mapstore-base:capas_base`), usado como fondo cartográfico en varios mapas Leaflet
- **Usado en:** `conexionDSN.R`, `Visor_hogares_sustentables.R`, `scripts/barrido/barrido.R`
- Catálogo de +30 capas documentado en comentarios de `conexionDSN.R` (contenedores, barrios, veredas, arbolado, semáforos, etc.)

## API intranet IMM — Visor de Vehículos

- **Endpoint:** `https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones` (GET vía `httr2`)
- **Parámetros:** `matricula`, `fechaDesde`, `fechaHasta`, `grupo` (`sisconve`/`waste`/`crane`/`hired`), `showStopsOnly`
- **Usada en:** `prueba_api.R`, `Visor_vehiculos.R`, `Visor_hogares_sustentables.R`
- Requiere red interna de la IMM; sin autenticación explícita en el código.

## API intranet IMM — Gestión Operativa de Limpieza

- **Endpoints:** `https://intranet.imm.gub.uy/app/limpieza-gestion-operativa/api/frontend/v1/contenedores/circuitos` y `.../contenedores` (GeoJSON, leído con `sf::st_read`)
- **Usada en:** `conexionDSN.R`

## Servidor IMAP

- **Host:** `imap.imm.gub.uy:993`
- **Usado en:** `mail.py`
- ⚠️ **Contiene credenciales de correo hardcodeadas en texto plano** — ver [docs/improvements.md](improvements.md).

## QGIS local (proyectos `.qgz`, sin conexión directa a BD desde este repo)

- **Ubicación:** unidad de red `G:\Desarrollo Ambiental\Limpieza\Spaa\Infograf*\08. MAPAS DIARIOS\...`
- Los proyectos QGIS internamente referencian capas Postgres/GeoServer (`imm:V_DF_POSICIONES_RECORRIDO_GEOM`, `ide:ide_V_DF_POSICIONES_RECORRIDO_GEOM`) fuera del alcance de los scripts R/Python de este repositorio.
- **Automatizados por:** `scripts/qgis/qgis_mapaAtraso.py`, `qgis_mapaRepetidos.py`, `qgis_mapaUNA.py`

## Archivos locales (fuentes crudas)

- `archivos/10393_ubicaciones/AAAA/MM_mes/YYYY-MM-DD.csv` — posiciones/estado de contenedores (ISO-8859-1, delimitado por tabulación)
- `archivos/GOL_reportes/AAAA/MM_mes/YYYY-MM-DD.csv` — llenado/levante por viaje GOL (UTF-8, delimitado por coma)
- `db/10450_pesadas/*.csv` — pesadas de báscula (delimitado por tabulación)
- `informes/planificados/planificacion.xlsx` — plantilla de planificación de circuitos (rotación 42 días)
- `vistas/informediario/reportes/archivo_informe {fecha} 06 AM.xlsx` — Excel madre diario (hojas Hoy/Ayer/Levantado/NoLevantado/DRIVE)
- `vistas/informe_operativa/Contenedores_AAAAMMDD_HHMM.ods` — snapshot de estado de contenedores

## Caché local en `db/` (generada por el pipeline, no fuente original)

| Carpeta | Contenido | Alimentada por |
|---|---|---|
| `db/10393_ubicaciones/` | `historico_ubicaciones.rds`, `archivos_aplicados_historico_ubicaciones.rds` | `funciones_db_ubicaciones.R` + `cargaDeDatos.R` |
| `db/10450_pesadas/` | CSV de pesadas de báscula | descarga manual/externa |
| `db/DFR/` | `RDS/*.rds` (una por capa DFR) + `GPKG/capas.gpkg` | `conexionDFR.R` |
| `db/GOL_reportes/` | `historico_llenadoGol.rds`, `archivos_aplicados_historico_llenadoGol.rds` | `funciones_db_golReportesDiarios.R` + `cargaDeDatos.R` |
| `db/planificados/` | `planificacion_V1.rds`, `planificacion_V2.rds`, `versiones_planificacion.rds` | mantenimiento manual de plantillas |
| `db/POSTGRES/` | `RDS/*.rds` + `GPKG/capas.gpkg` + `df_barrido_unido.parquet` | `conexionPOSTGRES.R`, `scripts/barrido/barrido.R` |

## Resumen de APIs externas

| API | Uso | Autenticación |
|---|---|---|
| GeoServer WFS `geoserver-ed.imm.gub.uy` (DFR) | Capas espaciales de recorridos/circuitos | Usuario/contraseña IMM interactivos |
| GeoServer WFS `montevideo.gub.uy` / `geoserver.montevideo.gub.uy` | Capas públicas (municipios, contenedores, vías) | Sin autenticación |
| WMS `montevideo.gub.uy/app/geowebcache` | Mapa base cartográfico | Sin autenticación |
| API intranet `visor-vehiculos-v2` | Posiciones GPS de flota | Ninguna visible (red interna) |
| API intranet `limpieza-gestion-operativa` | Circuitos y contenedores (GeoJSON) | Ninguna visible |
| IMAP `imap.imm.gub.uy` | Conteo de correos por remitente | Usuario/contraseña hardcodeados |
