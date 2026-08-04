# Changelog

## 2026-07-23 | v1.0.0 — Documentación inicial

**Generado automáticamente por la skill `proyecto-documentador`:**
- ➕ Creado `README_PROYECTO.md` (documento central)
- ➕ Creado `docs/data-sources.md` — inventario de conexiones (Postgres, WFS DFR, WFS público, APIs intranet IMM, IMAP) y carpetas de caché en `db/`
- ➕ Creado `docs/improvements.md` — 5 hallazgos críticos de seguridad (credenciales hardcodeadas, repo Git dentro de OneDrive), 5 bugs activos, y mejoras de mantenibilidad/duplicación
- ➕ Creado `docs/modules/` con 10 documentos, cubriendo ~30 scripts R/Python y 7 apps/módulos de `vistas/`:
  1. Orquestador e infraestructura (`nuevoinforme.R`, `global.R`, `funciones_utiles.R`, `cargaDeDatos.R`, `conexionDSN.R`)
  2. Descarga automatizada (Playwright, intranet IM)
  3. Conexiones y caché de datos (Postgres/PostGIS, WFS DFR, ingesta GOL/ubicaciones)
  4. Motor del informe diario (lógica de negocio central: Programado/Visitado/Vaciado, Criterio de Adrián)
  5. Visores de flota y mapas (posiciones GPS, pesadas, utilidades)
  6. Scripts batch de limpieza urbana (barrido, KML, automatización QGIS)
  7. App Informe Diario (Streamlit + PDF + automatización Excel)
  8. App Levantes de Camiones (Streamlit + PDF por turno)
  9. App Informe Operativa (atrasos/grúa/fuego/no está)
  10. App Informe de Llenado (Shiny + mapa de GIDs + pins/GitHub)

**Alcance:** documentación completa del proyecto (todos los scripts raíz, `db/`, `scripts/`, `informes/`, `endesuso/` y los 7 módulos de `vistas/`). No se leyó el contenido binario de archivos `.rds`/`.gpkg`/`.xlsx`, solo su rol como entrada/salida.

---

*A partir de aquí, este archivo se actualiza con `/doc-update --auto` (cambios detectados automáticamente) o `/doc-update --manual "descripción"` (notas manuales).*
