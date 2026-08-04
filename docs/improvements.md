# Mejoras Futuras Detectadas

Generado en el primer análisis completo del proyecto (2026-07-23). Ver el módulo correspondiente en `docs/modules/` para el detalle de cada punto.

## 🔴 Críticas (seguridad / riesgo de datos)

- [ ] **Credencial de PostgreSQL hardcodeada en texto plano**: `db/POSTGRES/conexionPOSTGRES.R`, función `conectar_postgres()` — usuario `qgis` / contraseña `mapa22` como valores por defecto. Migrar a variables de entorno o `keyring`/`.Renviron` y **rotar la contraseña**, ya que quedó expuesta en el historial de Git. → [03 · Conexiones y caché de datos](modules/03-conexiones-y-cache-db.md)
- [ ] **Credencial de correo hardcodeada en texto plano**: `mail.py` (`EMAIL`, `PASSWORD`). Rotar y mover a variable de entorno. → [05 · Visores de flota y mapas](modules/05-visores-flota-y-mapas.md)
- [ ] **Repositorio Git dentro de una carpeta sincronizada por OneDrive**: se detectaron archivos de conflicto con sufijo `-939868WN` incluso dentro de `.git/` (`.git/index-939868WN`, `.git/logs/HEAD-939868WN`), en `.Rproj.user/` y en copias de scripts (`limpieza_datos-939868WN.R`) y datos (`.xlsx`). Riesgo real de corrupción del repositorio ante ediciones concurrentes entre dispositivos. Recomendación: excluir `.git/` (y preferentemente todo el repo) de la sincronización de OneDrive, o mover el repositorio fuera de la carpeta sincronizada. → [10 · App Informe de Llenado](modules/10-app-informe-llenado.md)
- [ ] **Contraseña pasada como argumento de línea de comandos** en `funciones_descarga_consulta10393ubicaciones.R` / `funciones_descarga_reportesGOL.R` (`system2()` hacia Python) — puede quedar expuesta en logs o en el listado de procesos del SO. → [02 · Descarga automatizada](modules/02-descarga-automatizada.md)
- [ ] **Contraseña del WFS DFR embebida en URL del DSN de GDAL** (`db/DFR/conexionDFR.R`) — riesgo de exposición en logs de error de GDAL/sf. → [03 · Conexiones y caché de datos](modules/03-conexiones-y-cache-db.md)

## 🟠 Bugs activos

- [ ] **`nuevoinforme.R`** tiene una llamada activa con fecha hardcodeada (`fecha = "2026-02-17"`) inmediatamente antes de la llamada real (`fecha = NULL`) — generaría un PDF duplicado/incorrecto en cada corrida real. → [01 · Orquestador e infraestructura](modules/01-orquestador-y-infraestructura.md)
- [ ] **`conexionDSN.R`** contiene una línea de texto en español pegada como código plano (alrededor de la línea 213-217) que rompería la ejecución del script tal cual está. → [01 · Orquestador e infraestructura](modules/01-orquestador-y-infraestructura.md)
- [ ] **`mail.py`** usa `openpyxl` y `Counter` sin importarlos — fallaría con `NameError`/`ModuleNotFoundError`. → [05 · Visores de flota y mapas](modules/05-visores-flota-y-mapas.md)
- [ ] **`generar_reporte_pdf_camionesylevantesIMFID.py`** (prototipo obsoleto) usa `io.BytesIO()` sin importar `io`. Recomendación: eliminar el archivo, ya fue reemplazado por `generar_pdfs_reportlab.py`. → [08 · App Levantes de Camiones](modules/08-app-levantes-camiones.md)
- [ ] Los datos de "Disponibilidad" y "Toneladas" en `informe_diario_pdf.py`/`informe_diario_a4v_pdf.py` son **dummy/hardcodeados** (`get_dummy_data_extra()`) — riesgo de distribuir el reporte con números ficticios. → [07 · App Informe Diario](modules/07-app-informediario.md)

## 🟡 Importantes (duplicación de código / mantenibilidad)

- [ ] Triplicación de la lógica de consulta a la API de posiciones de flota entre `prueba_api.R`, `Visor_vehiculos.R` y `Visor_hogares_sustentables.R`. → [05](modules/05-visores-flota-y-mapas.md)
- [ ] Duplicación casi total de `load_real_data()` entre `informe_diario_pdf.py` e `informe_diario_a4v_pdf.py`. → [07](modules/07-app-informediario.md)
- [ ] Duplicación de lógica entre el dashboard Streamlit y el generador de PDF en ambos pares interactivo/PDF (`App_Informe_Diario`↔`informediario`, `App_Levantes_Camiones`↔`informe_levantes_camiones_porturno_IM_FID`). → [07](modules/07-app-informediario.md), [08](modules/08-app-levantes-camiones.md)
- [ ] `informeOP.qmd` (R/Quarto) es redundante con `informeOP_generar_pdf.py` (Python), con rutas ya obsoletas — candidato a archivar. → [09](modules/09-app-informe-operativa.md)
- [ ] `endesuso/conexionDFR.R` es copia exacta de `db/DFR/conexionDFR.R` — eliminar la duplicada. → [03](modules/03-conexiones-y-cache-db.md)
- [ ] Duplicación de código entre `funciones_descarga_consulta10393ubicaciones.R` y `funciones_descarga_reportesGOL.R` — refactor a función única parametrizada por módulo. → [02](modules/02-descarga-automatizada.md)
- [ ] Reglas de clasificación de Oficina/Municipio por regex (`^B_0?[1-7]`) duplicadas en al menos 3 archivos distintos (ingesta ubicaciones, ingesta GOL, informe operativa) — centralizar en una función/constante compartida.
- [ ] `Visor_vehiculos.R` ejecuta 3 bloques de análisis batch automáticamente al hacer `source()` (no protegidos por `if (FALSE)`) — riesgo de llamadas reales accidentales a la API. → [05](modules/05-visores-flota-y-mapas.md)
- [ ] `nuevoinforme.R` no valida el código de salida de los `system2()` a scripts Python — un fallo silencioso en un paso intermedio no detiene el resto del pipeline. → [01](modules/01-orquestador-y-infraestructura.md)

## 🟢 Nice to Have

- [ ] Paralelizar las llamadas HTTP a la API de posiciones de flota (una por matrícula×turno×fecha). → [05](modules/05-visores-flota-y-mapas.md)
- [ ] Eliminar `test_logo_conversion.R` y `pruebaplani.R` (prototipos ya superados por sus versiones definitivas), o moverlos a una carpeta de referencia histórica.
- [ ] Migrar la manipulación de XML de los proyectos QGIS (`scripts/qgis/*.py`) a PyQGIS si se dispone del entorno, para mayor robustez ante cambios de versión de QGIS. → [06](modules/06-scripts-batch-limpieza.md)
- [ ] Agregar reintentos/`tryCatch` a la descarga en vivo del WFS público de Montevideo en `barrido.R`. → [06](modules/06-scripts-batch-limpieza.md)
