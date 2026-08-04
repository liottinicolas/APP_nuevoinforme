# 07 · App Informe Diario (`vistas/App_Informe_Diario/` + `vistas/informediario/`)

Tipo: App Streamlit (Python) + generadores de PDF (Python) + automatización Excel (xlwings)

## 📖 ¿Qué hace?

Presenta el estado diario de recolección (Programado/Visitados/Vaciados, por municipio y turno, separado IM/Fideicomiso) en tres formatos: dashboard interactivo (Streamlit), PDF institucional (dos layouts) y una automatización diaria de Excel + generación de CSVs para mapas QGIS.

## 📊 Entrada (Input)

- `.rds` en `vistas/informediario/data/`: `tabla_soloIM_resumen_pordia_municipio_turno_completo.rds`, `tabla_soloFID_resumen_pordia_municipio_turno_completo.rds` (generados por [04 · Motor del informe diario](04-motor-informe-diario.md))
- `db/10393_ubicaciones/historico_ubicaciones.rds` (para contar contenedores instalados)
- Archivo Excel madre `archivo_informe {fecha} 06 AM.xlsx` (más reciente, detectado por `glob`)
- Variable de entorno opcional `FECHA_REPORTE`

## 🔄 Proceso

### `App_Informe_Diario/Informe_diario.py` — dashboard Streamlit
3 pestañas: Detalle Diario (IM), Datos FID, Evolución Histórica. Carga cacheada (`@st.cache_data(ttl=300)`), filtros de fecha/municipio/turno, KPIs (Visitados, Vaciados, Eficiencia = Visitados/Programado), gráficos de barras y línea (Plotly).

### `informediario/informe_diario_pdf.py` (A4 apaisado) e `informediario/informe_diario_a4v_pdf.py` (A4 vertical)
`load_real_data()` filtra por fecha objetivo (última disponible o `FECHA_REPORTE`); construye tabla de contenedores por municipio (IM y Fideicomiso), bloque de Toneladas, disponibilidad de recolección lateral por turno y contenedores instalados. Layout con `reportlab` (`BaseDocTemplate`).

### `informediario/reportes/actualizar_ayer.py` — rotación diaria del Excel madre (xlwings)
Mueve datos de la hoja "Hoy" a "Ayer" (como valores), limpia "Hoy" y la puebla con datos frescos desde los RDS. Trabaja sobre una copia temporal local (el archivo vive en OneDrive) y maneja el bug histórico de fechas seriales de Excel/Lotus 1-2-3. Refresca tablas dinámicas y guarda de vuelta.

### `informediario/reportes/generar_mapas.py`
A partir del Excel madre del día, genera `Mapas/Atraso {fecha}.csv`, `Mapas/UNA {fecha}.csv` (índice `Frecuencia × Acumulación / 7 × 100`, categorizado en 5 rangos) y `Mapas/Repite {fecha}.csv` (contenedores repetidos entre hoy y ayer). Estos CSVs alimentan los scripts QGIS de [06 · Scripts batch de limpieza](06-scripts-batch-limpieza.md).

## 📤 Salida (Output)

- Dashboard interactivo en navegador (Streamlit) + descargas CSV
- `informe_test_visual.pdf` / `informe_diario_a4v_test.pdf` (modo test) o PDF de producción con fecha
- Nuevo `archivo_informe {fecha_siguiente} 06 AM.xlsx`
- `Mapas/Atraso|UNA|Repite {fecha}.csv`

## 🔗 Dependencias

- Python: `streamlit`, `pandas`, `numpy`, `plotly`, `pyreadr`, `reportlab`, `xlwings` (requiere Excel de escritorio — solo Windows)

## ⚡ Mejoras Futuras

- [ ] `Informe_diario.py` duplica casi exactamente la lógica de KPIs/gráficos entre la pestaña IM y la pestaña FID — extraer a una función parametrizada por oficina.
- [ ] **Duplicación de código significativa** entre `informe_diario_pdf.py` e `informe_diario_a4v_pdf.py`: `load_real_data()` está copiada casi línea por línea en ambos. Extraer un módulo común (`informe_diario_data.py`) del que ambos importen.
- [ ] Los datos de "Disponibilidad" y "Toneladas" en los PDFs son **dummy/hardcodeados** (`get_dummy_data_extra()`) — riesgo de distribuir el reporte con números ficticios si no se conecta a la fuente real antes de producción.
- [ ] `actualizar_ayer.py` depende de la estructura exacta de hojas/rangos de celdas del Excel madre y de tener Excel de escritorio instalado — no portable a un servidor Linux. Documentar como requisito operativo.
- [ ] `actualizar_ayer.py` y `generar_mapas.py` repiten la misma lógica de búsqueda del "archivo madre" por `glob`+regex — extraer a una función compartida.

## 📌 Notas

`App_Informe_Diario` (Streamlit) e `informediario` (PDF) muestran esencialmente el mismo dato en dos formatos distintos (interactivo vs. distribución impresa/email) — mantener sincronizada la lógica de negocio entre ambos si cambian las reglas de cálculo.
