# Changelog

## 2026-11-24 | Módulo 11 — Enlace de la planilla fuera del código

- 🔒 `URL_DISPONIBILIDAD` (`flota_funciones.R`) se lee de la variable de entorno del mismo nombre en el `.Renviron` de la raíz (no versionado): el repo es público y la planilla se abre con el enlace. Sin la variable, `descargar_disponibilidad()` avisa y usa la copia local
- 🧹 `nuevoinforme.R`: se quita el fragmento suelto del final (daba error de sintaxis) y la consulta de promedio de levantes diarios pasa a `scripts/consultas/promedio_levantes_diarios.R`
- 🙈 `.gitignore`: `*.pkl` (intermedios de los `.py` de `scripts/analisis_servicios/`)

---

## 2026-10-15 | Módulo 11 — Columnas de uso de flota separadas

- ✏️ `uso_flota_actual()` y `resumen_flota_turno()`: la columna `BCHC_*` (que incluía C_110–C_116 y parecía no filtrar C) se separa en `analizados_*` (B_101–103, CH, C_101–109), `C110_116_media` y `quedan_*` (la suma, usada cuando A/D/E/F/G dejan el sistema). Resultados sin cambios; assert nuevo en `verificar_analisis.R`
- 📝 Textos "B/CH/C" y "CH y C" en scripts, Excel (`Definiciones`) y `documentacion_analisis.md` aclaran C_101–C_109

---

## 2026-10-15 | Módulo 11 — Camiones disponibles desde la planilla de operaciones

- ✏️ Los camiones disponibles ya no son una flota fija (27 con 10 % de reserva): salen de la planilla "Información", hoja Disponibilidad (camiones al inicio de cada turno), media de los últimos 3 meses por turno y día de semana. Nuevas funciones en `flota_funciones.R`: `descargar_disponibilidad()`, `leer_disponibilidad()`, `disponibilidad_por_turno()`, `disponibles_tabla()`, `validar_con_planilla()`; `lugar_libre()` y `resumen_flota_turno()` aceptan un número o la tabla por turno
- ➕ Copia local en `db/disponibilidad/disponibilidad_camiones.csv`; hojas nuevas `Disponibles` y `Validacion_planilla` en el Excel de flota; asserts nuevos en `verificar_analisis.R`
- ✅ Validación: camiones usados (planilla) vs camiones-turno de GOL, diferencia media < 1 por turno y correlación diaria 0,93
- 📊 Disponibles en días hábiles: 26 de noche, 23 de mañana, 21 de tarde. Mínimo 6/semana hoy 47 → 45 camiones-turno extra; completar + 6/semana cubre el 79 % (antes 94 %); sin A/D/E/F/G se liberan ~6 camiones por noche (antes 4)
- 📝 Actualizados `documentacion_analisis.md`, `docs/modules/11-analisis-servicios-y-flota.md` y `docs/data-sources.md`

---

## 2026-10-15 | Módulo 11 — Se excluyen C_110 a C_116

- ✏️ `CIRCUITOS_C_EXCLUIDOS` (C_110–C_116) en `analisis_servicios_funciones.R`: salen del universo (35 circuitos). En `viajes_por_bloque()` quedan como bloque `C_excluido`, que sigue contando en el uso de la flota
- 📊 Demanda 113,7 → 93,7 camiones-turno/semana; mínimo 6/semana hoy 57 → 47 camiones-turno extra

---

## 2026-10-15 | Módulo 11 — Flota de 30 a 27 camiones

- ✏️ `FLOTA` pasa de 30 a 27 en `analisis_flota.R` y `verificar_analisis.R` (últimamente hay menos camiones); actualizadas las definiciones de `flota_funciones.R`, las cifras de `documentacion_analisis.md` y `docs/modules/11-analisis-servicios-y-flota.md`
- 📊 Con reserva 10 % quedan 24 camiones disponibles: hoy no hay lugar libre de noche y la mañana admite ~6 camiones-turno/semana; el aumento de frecuencia va mayormente de tarde

---

## 2026-10-14 | Módulo 11 — Análisis de servicios, capacidad y flota

- ➕ Creado `docs/modules/11-analisis-servicios-y-flota.md`: proceso, orden de ejecución, parámetros, salidas y decisiones de criterio de `scripts/analisis_servicios/` (`analisis_servicios_viajes.R`, `analisis_capacidad.R`, `analisis_flota.R`, `verificar_analisis.R` y sus `*_funciones.R`)
- 🔗 Agregado al índice de componentes de `README_PROYECTO.md`

---

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
