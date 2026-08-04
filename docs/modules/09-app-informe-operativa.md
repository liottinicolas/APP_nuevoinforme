# 09 · App Informe Operativa (`vistas/informe_operativa/`)

Tipo: Script Python (activo, PDF + Excel) + documento Quarto/R (legacy)

## 📖 ¿Qué hace?

A diferencia de los demás módulos de `vistas/`, no mide volúmenes de recolección sino **incidencias operativas**: contenedores atrasados (sin levante hace ≥3 días), motivos que requieren grúa, contenedores en estado "Fuego" o "No Está" (con duración del episodio activo).

## 📊 Entrada (Input)

- `Contenedores_AAAAMMDD_HHMM.ods` (único archivo esperado en la carpeta del módulo, detectado por regex vía `buscar_archivo_contenedores()`)
- `db/GOL_reportes/historico_llenadoGol.rds` (histórico de incidencias, para el análisis "No Está" contra 90 días)

## 🔄 Proceso

### `informeOP_generar_pdf.py` — versión activa
Clasifica `Oficina` (IM vs Fideicomiso) por regex de `Circuito` (`^B_0?[1-7]`) y filtra solo IM; calcula `Acumulacion_horas/dias_calendario`.
```
procesar_atrasos()   # tabla resumen Municipio x categoría (3, 4, 5, ≥6 días) + detalle por circuito con "tramos" compactados
procesar_grua()      # motivos: Roto, Sobrepeso, Fuera de Alcance, Buzonera Girada, Cruzado, Calle Cerrada
procesar_fuego()
procesar_no_esta()   # reconstruye "episodios" de estado No Está por GID (run-length encoding sobre histórico normalizado)
```
Genera PDF (reportlab, tablas con `Paragraph` para word-wrap) y Excel equivalente (openpyxl). El slot horario (0915/1220) se determina por la hora del `.ods` de origen.

### `informeOP.qmd` — versión legacy en R/Quarto
Misma lógica de negocio (Atrasos, Grúa, No Está, Fuego) implementada en R/tidyverse, salida PDF vía LaTeX (`kableExtra`) y Excel (`openxlsx`). Lee un archivo fijo `pruebaods.ods` (no el patrón dinámico) y una ruta obsoleta (`scripts/db/GOL_reportes/...`) que ya no coincide con la estructura actual del repo.

## 📤 Salida (Output)

- `Reporte_Atrasos_Grua_No_esta_Fuego-{fecha}_{0915|1220}.pdf` y `.xlsx` equivalente (histórico de ~150 pares generados)

## 🔗 Dependencias

- Python: `pandas`, `numpy`, `reportlab`, `openpyxl`, `pyreadr`
- R (legacy): `readODS`, `dplyr`, `stringr`, `lubridate`, `tidyr`, `purrr`, `openxlsx`, `knitr`, `kableExtra`, `here`, `janitor`, `stringi`

## ⚡ Mejoras Futuras

- [ ] **Redundancia entre lenguajes**: `informeOP.qmd` (R) parece ser el prototipo original, reescrito íntegramente en Python (`informeOP_generar_pdf.py`), probablemente para independizarse de LaTeX/Quarto. Si la versión Python ya es la fuente de verdad en producción, archivar o eliminar el `.qmd` para evitar mantenimiento duplicado y confusión sobre rutas obsoletas.
- [ ] `informeOP_generar_pdf.py` requiere exactamente un único `.ods` en la carpeta (falla si hay 0 o más de 1) — agregar mensaje de error más claro o manejo explícito de ese caso.
- [ ] Ruta hardcodeada de 3 niveles hacia arriba para llegar a `db/GOL_reportes/` — usar una resolución de ruta más robusta (ej. `here()` como en los scripts R).
- [ ] Las reglas de clasificación de Oficina por regex están duplicadas respecto a otros módulos (ver [03 · Conexiones y caché de datos](03-conexiones-y-cache-db.md)) — centralizar.

## 📌 Notas

Es el único módulo de `vistas/` centrado en incidencias en vez de volúmenes; complementa, no reemplaza, a los reportes de [07](07-app-informediario.md) y [08](08-app-levantes-camiones.md).
