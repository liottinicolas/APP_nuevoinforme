# 08 · App Levantes de Camiones (`vistas/App_Levantes_Camiones/` + `vistas/informe_levantes_camiones_porturno_IM_FID/`)

Tipo: App Streamlit (Python) + generador de PDF (Python, reportlab/matplotlib)

## 📖 ¿Qué hace?

Reporta contenedores vaciados y camiones utilizados por turno (Matutino/Vespertino/Nocturno), aplicando el **"Criterio de Adrián"** (turno nocturno se imputa al día calendario siguiente, ver [04 · Motor del informe diario](04-motor-informe-diario.md)), en dos formatos: dashboard Streamlit y PDF institucional.

## 📊 Entrada (Input)

- `.rds` en `vistas/informe_levantes_camiones_porturno_IM_FID/data/` (sufijo `*_criterioadrian.rds`, generados por `informes/informecamiones.R`):
  - `informediarionuevo_total_soloim_criterioadrian.rds` / `_imyfideicomiso_criterioadrian.rds`
  - `total_viajesporcamionsoloim_criterioadrian.rds` / `total_viajesporcamionIM_fid_criterioadrian.rds`
- Variable de entorno opcional `FECHA_REPORTE`

## 🔄 Proceso

### `App_Levantes_Camiones/Levantes_Camiones.py` — dashboard Streamlit
Carga cacheada (`ttl=300`), filtra "hasta ayer", filtros de rango de fechas (default últimos 30 días) y turno. 2 tabs (Vaciados/Camiones) con gráficos de barras apiladas por turno (colores institucionales: Matutino amarillo, Vespertino naranja, Nocturno gris) y tablas pivot (Fecha × Turno).

### `informe_levantes_camiones_porturno_IM_FID/generar_pdfs_reportlab.py` — versión activa en producción
```
load_and_prepare_data()     # filtra ±32 días
procesar_datos_pivot()      # tabla Fecha x Turno con Total general
crear_grafico_apilado()     # gráfico matplotlib, colores institucionales
```
Construye PDF con `reportlab` (`BaseDocTemplate`, templates Portrait/Landscape alternados), logo y pie de página institucional. Genera 2 PDFs por corrida: solo-IM e IM+Fideicomiso.

### `generar_reporte_pdf_camionesylevantesIMFID.py` — **prototipo obsoleto**
Versión anterior con datos hardcodeados de ejemplo; contiene un bug (usa `io.BytesIO()` sin importar `io`, fallaría con `NameError`). No se usa en producción.

## 📤 Salida (Output)

- Dashboard interactivo (2 tabs, tablas pivot)
- `IM-Contenedores-Vaciados-Turno_{fecha}-Camiones Utilizados.pdf` y `IM+Fid-...pdf` (histórico de ~130 PDFs ya generados)

## 🔗 Dependencias

- Python: `streamlit`, `pandas`, `plotly`, `pyreadr`, `matplotlib` (backend `Agg`), `reportlab`, `numpy`

## ⚡ Mejoras Futuras

- [ ] **Duplicación de lógica de negocio**: `Levantes_Camiones.py` (Streamlit) y `generar_pdfs_reportlab.py` comparten la misma fuente de datos, el mismo pivot Fecha×Turno y los mismos colores institucionales, pero no comparten código. Extraer a un módulo común de procesamiento de datos.
- [ ] Eliminar o archivar explícitamente `generar_reporte_pdf_camionesylevantesIMFID.py` (prototipo obsoleto con bug de import y datos hardcodeados) para evitar confusión sobre cuál es la versión vigente.
- [ ] En `Levantes_Camiones.py`, `plotly.graph_objects` está importado pero no usado — limpiar import.

## 📌 Notas

Es el módulo con más historial de PDFs generados (~130), lo que sugiere que es uno de los reportes de mayor uso recurrente del sistema.
