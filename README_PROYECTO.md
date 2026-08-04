# Proyecto: APP_nuevoinforme

Fecha de creación de esta documentación: 2026-07-23
Última actualización: 2026-07-23

## 📊 Resumen Ejecutivo

Sistema de reporting operativo para la **gestión de recolección de residuos** del Departamento de Desarrollo Ambiental / División Limpieza y Gestión de Residuos de la **Intendencia de Montevideo (IM)**. Integra datos de posiciones de contenedores, viajes de camiones (GOL), planificación de circuitos y capas geoespaciales (PostgreSQL/PostGIS, GeoServer WFS) para producir informes diarios en PDF, Excel, dashboards Shiny/Streamlit y mapas interactivos. Cubre tanto la operación directa de la IM como la de un **Fideicomiso** (contratista externo, circuitos con prefijo `B_01`–`B_07`).

## 🗂️ Estructura

```
APP_nuevoinforme/
├── nuevoinforme.R                 # Orquestador principal del pipeline
├── global.R, funciones_utiles.R   # Infraestructura (logging, entorno, PDFs, GitHub)
├── cargaDeDatos.R                 # ETL incremental de CSVs → históricos RDS
├── funciones_descarga_*.R         # Scraping automatizado (Playwright) de la intranet IM
├── conexionDSN.R, conexionPOSTGRES.R  # Acceso a capas geoespaciales (WFS / Postgres)
├── Visor_vehiculos.R, Visor_hogares_sustentables.R, Pesadas_Intra.R, prueba_api.R
│                                   # Análisis batch de posiciones GPS de flota y pesadas
├── mail.py, process_logo.py, test_logo_conversion.R  # Utilidades sueltas
├── informes/                      # Motor de negocio: informe diario, viajes por turno, planificación
├── db/                            # Caché local por fuente de datos (RDS/GPKG/parquet)
│   ├── 10393_ubicaciones/         # Posiciones/estado de contenedores
│   ├── 10450_pesadas/             # Pesadas de báscula
│   ├── DFR/                       # Capas WFS autenticadas (recorridos, rutas, contenedores)
│   ├── GOL_reportes/               # Histórico de llenado/levante por viaje (GOL)
│   ├── planificados/               # Plantillas de planificación (rotación 42 días)
│   └── POSTGRES/                   # Caché de capas PostGIS (barrido, papeleo, hogares, etc.)
├── endesuso/                      # Copia duplicada de conexionDFR.R (ver improvements.md)
├── scripts/                       # Batch de limpieza urbana (barrido) y automatización QGIS
├── vistas/                        # 7 módulos de reporting (apps Shiny/Streamlit + generadores PDF)
│   ├── App_Informe_Diario/         # Dashboard Streamlit — informe diario (equivalente a informediario/)
│   ├── App_Levantes_Camiones/      # Dashboard Streamlit — vaciados/camiones por turno
│   ├── App_informe_llenado/        # Shiny — mapa de GIDs + histórico de llenado
│   ├── informediario/               # PDF informe diario (A4 apaisado/vertical) + automatización Excel diaria
│   ├── informe_levantes_camiones_porturno_IM_FID/  # PDF vaciados/camiones por turno (Criterio Adrián)
│   ├── informe_operativa/           # PDF/Excel de incidencias operativas (atrasos, grúa, fuego, no está)
│   └── mapas/                       # Solo resultados (mapas HTML pre-generados), sin código
└── renv.lock                      # 138 paquetes R fijados, R 4.5.1
```

## 📈 Flujo de Datos

```
Fuentes externas                     Ingesta/Caché (db/)              Negocio (informes/)         Salida (vistas/)
─────────────────                    ───────────────────              ───────────────────         ────────────────
Intranet IM (10393 ubicaciones) ──▶  db/10393_ubicaciones/       ──▶
Intranet IM (GOL reportes)      ──▶  db/GOL_reportes/            ──▶  informe_diario.R       ──▶  informediario/ (PDF, Excel, Streamlit)
Excel planificación (42 días)   ──▶  db/planificados/            ──▶  informecamiones.R      ──▶  informe_levantes_camiones.../ (PDF, Streamlit)
GeoServer WFS (DFR, autenticado)──▶  db/DFR/                     ──▶  App_informe_llenado    ──▶  App_informe_llenado/ (Shiny + GitHub pins)
PostgreSQL/PostGIS "qgis" (IM)  ──▶  db/POSTGRES/                 ──▶  scripts/barrido        ──▶  reportes de limpieza (Excel, KML)
API intranet visor-vehiculos    ──▶  (en memoria, sin caché RDS)  ──▶  Visor_vehiculos.R      ──▶  salidas/mapas/*.html
Contenedores .ods (báscula)     ──▶  db/10450_pesadas/            ──▶  Pesadas_Intra.R        ──▶  salidas/Resumen_Pesadas.xlsx/.ods
```

`cargaDeDatos.R` es el motor ETL incremental: detecta CSVs nuevos por módulo, delega el parseo a `db/<módulo>/funciones_db_*.R` y acumula en históricos RDS sin reprocesar archivos ya vistos.

## 🔗 Componentes

Ver el detalle completo de cada uno en `docs/modules/`:

- [01 · Orquestador e infraestructura](docs/modules/01-orquestador-y-infraestructura.md) — `nuevoinforme.R`, `global.R`, `funciones_utiles.R`, `cargaDeDatos.R`, `conexionDSN.R`
- [02 · Descarga automatizada](docs/modules/02-descarga-automatizada.md) — scraping Playwright de la intranet IM
- [03 · Conexiones y caché de datos](docs/modules/03-conexiones-y-cache-db.md) — Postgres/PostGIS, WFS DFR, ingesta GOL/ubicaciones
- [04 · Motor del informe diario](docs/modules/04-motor-informe-diario.md) — lógica de negocio central (Programado/Visitado/Vaciado)
- [05 · Visores de flota y mapas](docs/modules/05-visores-flota-y-mapas.md) — posiciones GPS, pesadas, utilidades de imagen/mail
- [06 · Scripts batch de limpieza urbana](docs/modules/06-scripts-batch-limpieza.md) — barrido, KML, automatización QGIS
- [07 · App Informe Diario](docs/modules/07-app-informediario.md) — Streamlit + PDF + automatización Excel diaria
- [08 · App Levantes de Camiones](docs/modules/08-app-levantes-camiones.md) — Streamlit + PDF por turno (Criterio Adrián)
- [09 · App Informe Operativa](docs/modules/09-app-informe-operativa.md) — atrasos/grúa/fuego/no está
- [10 · App Informe de Llenado](docs/modules/10-app-informe-llenado.md) — Shiny + mapa de GIDs

## ⚙️ Dependencias

- **R 4.5.1**, gestionado con `renv` (138 paquetes fijados vía Posit Package Manager). Paquetes clave: `shiny`, `bs4Dash`, `sf`, `leaflet`, `DBI`/`RPostgres`, `pins`, `gert`/`gh`, `reticulate`, `openxlsx`/`readxl`/`readODS`.
- **Python** (vía `reticulate`, virtualenv `r-reticulate`): `streamlit`, `pandas`, `plotly`, `pyreadr`, `reportlab`, `matplotlib`, `openpyxl`, `xlwings` (Windows/Excel), `numpy`, `PIL`.
- **Externos**: PostgreSQL/PostGIS de la IM, GeoServer WFS (autenticado y público), API intranet de posiciones de flota, QGIS Desktop (proyectos `.qgz` en unidad de red).

## 🚀 Próximas Mejoras

Ver detalle priorizado en [docs/improvements.md](docs/improvements.md). Puntos críticos: credenciales hardcodeadas (Postgres, mail), duplicación de lógica entre pares Streamlit/PDF, y el repositorio Git viviendo dentro de una carpeta sincronizada por OneDrive.

## 📅 Historial

Ver [docs/changelog.md](docs/changelog.md).
