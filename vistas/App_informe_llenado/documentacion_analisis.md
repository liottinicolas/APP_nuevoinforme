# Documentación de análisis: KPIs de frecuencia de levante y saturación (App_informe_llenado)

_Última actualización: 2026-08-13_

## 1. Contexto de negocio

**Objetivo del análisis:** agregar al detalle por GID (pestaña "Histórico" de `App.R`) una métrica que refleje la frecuencia con la que se levanta un contenedor y qué tan seguido llega a saturación, además del % de llenado promedio histórico que ya se mostraba.

**Preguntas de negocio a responder:**
- ¿Cada cuánto se levanta exitosamente un contenedor dado?
- ¿Con qué frecuencia ese contenedor llega a estar saturado (100% de llenado)?

**Entrevista realizada (preguntas y respuestas):**

| Pregunta | Respuesta | Quién la respondió |
|---|---|---|
| ¿Qué significa `Levantado` vacío (NA)? (~26% de las filas en un día típico) | El camión no llegó a pasar por ese contenedor (ruta planificada pero incompleta) — no es un "no levantado" con motivo, es directamente ausencia de pasaje real | Nicolás |
| ¿Qué significa "frecuencia de levante"? | Ambas cosas: promedio de días entre levantes exitosos + conteo de levantes en una ventana reciente | Nicolás |
| ¿Qué forma debe tener el "% de llenado según un tiempo"? | % de veces que el contenedor llegó a saturación (100%) en una ventana reciente | Nicolás |
| ¿Dónde va la info nueva en la UI? | Nueva tarjeta KPI (no columna de tabla) | Nicolás |

**Supuestos asumidos sin confirmar:**
- Ventana "reciente" = últimos 30 días. No se preguntó explícitamente cuántos días; se eligió 30 por ser un período operativo estándar. Impacto si es incorrecto: los KPIs "Levantes en Últimos 30 Días" y "% Saturación (Últimos 30 Días)" mostrarían una ventana distinta a la que el usuario espera — es un solo valor (`ventana_dias`) fácil de ajustar en `App.R` si hace falta otro período.

## 2. Diccionario de datos

Columnas relevantes de `historico_llenado_web` (fuente: `db/GOL_reportes/historico_llenadoGol.rds`, generadas por `db/GOL_reportes/funciones_db_golReportesDiarios.R` a partir de los CSV diarios `archivos/GOL_reportes/AAAA/MM_mes/YYYY-MM-DD.csv`):

| Columna | Tipo de dato | Significado de negocio | Valores posibles / formato | Notas |
|---|---|---|---|---|
| `gid` | character | Identificador del contenedor | numérico como texto | Clave de búsqueda en la pestaña Histórico |
| `Fecha` | Date | Día del viaje/recorrido | fecha | Ordena todo el histórico |
| `Levantado` | character | Si el camión levantó el contenedor en ese pasaje | `"S"`, `"N"`, `NA` | **`NA` = el camión no llegó a pasar** (ruta incompleta), no es un levante fallido. `"N"` = pasó pero no levantó, con motivo en `Incidencia` |
| `Incidencia` | character | Motivo por el cual no se levantó (`motivo_no_levante` en el CSV crudo) | texto libre categórico: "Contenedor No Está", "Auto", "Sobrepeso", "Fuego", "Calle Cerrada", etc. | Solo se completa cuando `Levantado == "N"` |
| `Porcentaje_llenado` | numeric | % de llenado observado al momento del pasaje | `25, 50, 75, 100` (discreto, no continuo) | Solo se registra cuando `Levantado == "S"`; es una estimación visual del operario, no una medición precisa |
| `Condicion` | character | Observaciones sobre el estado físico/entorno del contenedor (`condiciones_contenedor` en el CSV crudo) | multi-valor separado por `;` : "Basura Afuera", "Requiere Limpieza", "Requiere Mantenimiento", "Fuera de Lugar", "Dos Ciclos", "Escombro", "Poda", etc. | Puede combinar varios tags en una sola fila |
| `Turno_levantado` | factor | Turno del recorrido | `Matutino`, `Vespertino`, `Nocturno` | Ordenado como factor en el ETL |
| `contenedor_activo` | character | Si el contenedor estaba activo al momento del pasaje | `"S"`, `"N"` | No confundir con el estado activo *actual* (eso sale de `GID_activos`/`GID_inactivos`) |
| `Id_viaje_GOL` | numeric | Identificador del viaje del camión | numérico | Un viaje agrupa múltiples contenedores/posiciones |

## 3. Decisiones de limpieza

| Decisión | Motivo | Filas/valores afectados |
|---|---|---|
| Retención de `historico_llenado_web` limitada a los últimos 12 meses antes de generar el pin (`limpieza_datos.R`) | El archivo completo (todo el histórico acumulado) pesaba 94 MB y se descarga entero en cada arranque en frío de la app en producción, generando carga lenta | Filas con `Fecha < Sys.Date() - 365` |
| Se seleccionan solo las 13 columnas que `App.R` usa (de 18 originales) antes de escribir el pin | Reduce el peso del archivo sin perder funcionalidad | Columnas no listadas en el `select()` de `limpieza_datos.R` |
| `Levantado == NA` se excluye de los cálculos de frecuencia y saturación | Esas filas no representan un pasaje real del camión (ver Fase 0) — incluirlas infla artificialmente el denominador | Filas con `Levantado` vacío dentro del GID consultado |
| Se agregaron dos KPIs que separan `Levantado == "N"` de `Levantado == NA` en vez de agruparlos como "no levante" | El usuario aclaró que son dos fallas operativas distintas: `"N"` = el camión pasó pero no levantó, con una `Incidencia` que lo justifica; `NA` = el contenedor estaba programado en el circuito pero el camión no llegó a pasar, sin ningún registro que lo explique — mezclarlas ocultaría cuál de las dos es el problema real | Tarjetas 8 y 9 en `output$kpis_historico_no_levante` (`App.R`) |

## 4. Hallazgos y conclusiones

- **`Levantado` vacío no es un dato faltante, es una categoría de negocio real** (~26% de las filas en la muestra de un día) — representa contenedores planificados en el circuito de ese turno que el camión no llegó a recorrer. Cómo se llegó a esta conclusión: inspección de un CSV diario (`2026-08-12.csv`, 7492 filas) mostrando que esas filas no tienen `porcentaje_llenado`, `motivo_no_levante` ni `condiciones_contenedor` cargados, y confirmado por el usuario. Por qué le importa al negocio: cualquier métrica de "frecuencia de levante" o "tasa de levante" que no excluya estas filas va a subestimar la frecuencia real.
- **El KPI existente "Registros de Visitas (GOL)" (`total_visitas`) cuenta todas las filas, incluidas las de `Levantado == NA`.** Cómo se llegó a esta conclusión: lectura directa de `App.R` (`total_visitas <- nrow(df)` sin filtrar por `Levantado`). Por qué le importa al negocio: ese número puede estar sobreestimando cuántas veces realmente pasó un camión por el contenedor. No se corrigió en este cambio porque no fue parte del pedido explícito — queda como hallazgo para una futura revisión.
- **`Porcentaje_llenado` es una variable discreta de 4 niveles (25/50/75/100), no continua.** Esto significa que promedios como "Llenado Promedio Histórico" son útiles como tendencia relativa, pero no deben interpretarse como una medición precisa de volumen.

## 5. Recomendaciones

- Si en el futuro se necesita explicar *por qué* no se levantó un contenedor (no solo cuánto), `Incidencia` ya tiene la información categorizada y podría alimentar un KPI adicional (ej. "motivo más frecuente de no levante").
- Pendiente de decidir: medir el impacto real del no-levante en el llenado del pasaje siguiente (comparar `Porcentaje_llenado` del próximo pasaje según si el anterior fue "N" o "NA" para el mismo GID) — es la forma más directa de probar la hipótesis de que un no-levante infla el llenado del día siguiente, pero no se implementó porque requiere emparejar visitas consecutivas por GID y el usuario no confirmó si lo quiere además de los KPIs actuales.

### Cambio 2026-08-13: KPIs eliminados y filtro de rango de fechas

- Se eliminaron los KPIs "Registros de Visitas (GOL)", "Último Llenado Reportado" y "Levantes en Últimos 30 Días" a pedido del usuario.
- Se agregó `dateRangeInput("rango_fechas_historico")` en la pestaña Histórico (rango por defecto: últimos 90 días, tope máximo hoy). `datos_filtrados()` ahora filtra por GID **y** por ese rango, así que todos los KPIs restantes (Llenado Promedio, Frecuencia de Levante, % Saturación, % No Levantado con Incidencia, % Camión No Pasó) y la tabla se recalculan automáticamente sobre el rango elegido — ya no hay ventanas fijas de 30 días hardcodeadas.
- Motivo del recorte por defecto a 90 días: es solo un valor inicial razonable para no cargar el año completo de entrada; el usuario puede ampliarlo hasta el límite de retención de 12 meses del pin (ver sección 3).

## 6. Fuentes y metodología

- **Origen de los datos:** `db/GOL_reportes/historico_llenadoGol.rds`, construido por `db/GOL_reportes/funciones_db_golReportesDiarios.R` a partir de los CSV diarios en `archivos/GOL_reportes/AAAA/MM_mes/YYYY-MM-DD.csv`. Pin consumido por la Shiny app vía `vistas/App_informe_llenado/limpieza_datos.R` → `pins`.
- **Período cubierto:** histórico completo en la fuente original; recortado a últimos 12 meses en el pin que consume la app (ver sección 3).
- **Herramientas usadas:** inspección directa del CSV diario del 2026-08-12 con `pandas` (no se pudo cargar el `.rds` completo de 94 MB por límite de memoria del entorno de análisis; se usó el CSV crudo de un día como muestra representativa de la estructura).
- **Limitaciones conocidas:** el análisis de distribución de valores (`Levantado`, `motivo_no_levante`, `condiciones_contenedor`) se hizo sobre un solo día (7492 filas), no sobre los 3.24M de filas del histórico completo — la estructura de columnas y categorías es estable (confirmada contra el código del ETL), pero las proporciones exactas (ej. "26% de NA") pueden variar día a día.
