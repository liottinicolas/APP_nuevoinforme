# 05 · Visores de Flota, Pesadas y Utilidades

Tipo: R scripts + Python scripts (análisis batch independientes, no integrados a `nuevoinforme.R`)

## 📖 ¿Qué hace?

Grupo de scripts analíticos que consultan la API interna de posiciones GPS de la flota de camiones IMM, la cruzan con capas territoriales (Postgres) para detectar servicios reales por sector, y generan mapas HTML interactivos. Incluye también el procesamiento de pesadas de báscula y utilidades sueltas (logo, mail).

## 📊 Entrada (Input)

- API `https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones` (GET, params `matricula`, `fechaDesde`, `fechaHasta`, `grupo`, `showStopsOnly`) — usada por `prueba_api.R`, `Visor_vehiculos.R`, `Visor_hogares_sustentables.R`
- Capas Postgres `Intradomiciliario_operativo`, `Hogares_sustentables` (vía `cargar_capa_local_postgres()`)
- `df_flota` (de `conexionPOSTGRES.R`)
- CSV de pesadas más reciente en `db/10450_pesadas/*.csv` (Pesadas_Intra.R)
- `logoazul.png` (process_logo.py, test_logo_conversion.R)
- Servidor IMAP `imap.imm.gub.uy:993` (mail.py)

## 🔄 Proceso

### `prueba_api.R` — diagnóstico de la API de flota (1757 líneas)
```r
probar_conexion_api(matricula, fecha_desde, hora_desde, fecha_hasta, hora_hasta, grupo = "sisconve", solo_paradas = FALSE)
obtener_posiciones_flota_ambos_turnos_api(df_matriculas, fecha, solo_paradas)
buscar_camiones_en_sector_api(nombre_sector, fecha, buffer_metros = 70, ...)
graficar_mapa_estilo_imm() / exportar_mapa_estilo_imm()
```
Script de pruebas documentado como tal; termina con un bloque `if (FALSE) {...}` con 10 ejemplos de uso inactivos.

### `Visor_hogares_sustentables.R` — batch de validación de servicio real
Para cada sector de `Hogares_sustentables` y cada turno, aplica **7 filtros secuenciales** (mínimo de paradas, tiempo mínimo de permanencia, cobertura de núcleo interno erosionado, dispersión de área 2D, recorte de puntos periféricos, validación de servicio real, duración por visita) antes de generar el mapa, para descartar camiones que solo pasan de largo por el sector. Parámetros configurables al inicio del script (`tolerancia_metros`, `umbral_validacion_metros`, `min_paradas_vehiculo`, etc.) y `fecha_proceso` **hardcodeada** al inicio.

### `Visor_vehiculos.R` — búsqueda por geometría + delegación a Python
```r
buscar_vehiculos_en_geometria(capa_geometria, fecha, turno, df_flota_ref, buffer_metros = 50, solo_paradas = TRUE)
exportar_mapa_interactivo(capa_geometria, puntos_detectados, salida_html, python_path = python_venv, ...)
```
A diferencia de los otros dos, delega el dibujo del mapa a un script Python (`vistas/mapas/mapa_intro_dibujarutas.py`) vía `system2()`. **Ejecuta 3 bloques de análisis batch automáticamente al hacer `source()`** (no protegidos por `if (FALSE)`).

### `Pesadas_Intra.R`
Cruza pesadas (peso neto por viaje) con `df_flota` y una lista fija de 20 `circuitos_permitidos`; agrupa por (Fecha, Servicio) y por (Fecha, Servicio, Circuito); exporta a Excel/ODS con formato.

### `mail.py`
Cuenta correos por remitente en la bandeja IMAP vía `imaplib`, exporta ranking a Excel.

### `process_logo.py` / `test_logo_conversion.R`
Conversión del logo a PNG transparente: `process_logo.py` usa BFS desde los bordes (algoritmo robusto, en uso real); `test_logo_conversion.R` es una prueba de umbral simple, desechable.

## 📤 Salida (Output)

- `salidas/mapas/*.html` (prueba_api.R, Visor_vehiculos.R), `vistas/mapas/<fecha> recoleccion Hogares sustentables/.../*.html` (Visor_hogares_sustentables.R)
- `salidas/Resumen_Pesadas.xlsx` / `.ods` (Pesadas_Intra.R)
- `ranking_remitentes.xlsx` (mail.py)
- `logoazul_transparent.png` (process_logo.py, usado por los mapas HTML)

## 🔗 Dependencias

- R: `httr2`, `jsonlite`, `dplyr`, `sf`, `purrr`, `leaflet`, `htmltools`, `htmlwidgets`, `readODS`, `openxlsx`
- Python: `imaplib`, `email` (stdlib), `numpy`, `PIL`

## ⚡ Mejoras Futuras

- [ ] 🔴 **Crítico — credencial hardcodeada**: `mail.py` tiene `EMAIL`/`PASSWORD` de correo en texto plano en el código. Rotar la credencial y mover a variable de entorno.
- [ ] **Bug**: `mail.py` usa `openpyxl` y `Counter` sin importarlos — fallaría con `NameError`/`ModuleNotFoundError` tal cual está. Agregar los imports faltantes.
- [ ] **Triplicación de lógica**: `prueba_api.R`, `Visor_vehiculos.R` y `Visor_hogares_sustentables.R` reimplementan, con variantes, las mismas funciones de consulta a la API de posiciones (`probar_conexion_api`/equivalentes). Alto riesgo de mantenimiento/inconsistencia — consolidar en una sola librería compartida.
- [ ] `Visor_vehiculos.R` ejecuta 3 bloques de análisis/generación batch automáticamente al hacer `source()` — envolver en `if (FALSE)` o en una función explícita como ya hace `prueba_api.R`, para evitar llamadas reales accidentales a la API y generación de archivos.
- [ ] `Visor_hogares_sustentables.R` tiene `fecha_proceso` hardcodeada — parametrizar como argumento de función o variable de entorno (`FECHA_REPORTE`, ya usado en otros módulos).
- [ ] `Pesadas_Intra.R` toma el CSV más reciente por fecha de modificación sin advertir si hay más de uno — podría usar un archivo incorrecto si hay backups tocados después.
- [ ] Ninguno de los 3 scripts de consulta a la API paraleliza las llamadas HTTP (una por matrícula×turno×fecha) — podría ser lento con flotas grandes; evaluar paralelización con `furrr` o batching del lado servidor si la API lo soporta.
- [ ] `test_logo_conversion.R` es un script de prueba desechable — eliminar si `process_logo.py` ya es la versión definitiva.

## 📌 Notas

Ninguno de estos scripts está integrado al pipeline automático de `nuevoinforme.R`; se ejecutan manualmente según necesidad.
