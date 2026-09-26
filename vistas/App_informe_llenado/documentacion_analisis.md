# Documentación de análisis: KPIs de frecuencia de levante y saturación (App_informe_llenado)

_Última actualización: 2026-09-26 (ver sección 7: auditoría de datos y oportunidades)_

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

---

## 7. Auditoría de datos y oportunidades (2026-09-26)

**Objetivo:** revisar qué información tiene la app de llenado, qué datos más se pueden sacar y qué se puede mejorar.
**Fuente analizada:** `db/GOL_reportes/historico_llenadoGol.rds` completo (3.526.525 filas, 01/03/2025 – 25/09/2026, 18 columnas). Para los cálculos se usó la misma ventana de 12 meses que publica el pin (2.253.583 filas), junto con `GID_activos` (11.178), `GID_inactivos` (30.982) y `circuitos_periodo` (137 circuitos). El análisis se hizo en R base (scripts en el scratchpad de la sesión, no versionados). Esta vez se usó el histórico completo, no la muestra de un día de la sección 6.

### 7.1 Diccionario de datos: correcciones y columnas nuevas

| Columna | Tipo | Significado / observación | Estado en la app |
|---|---|---|---|
| `Porcentaje_llenado` | numeric | **Corrección:** también existe el valor **0**, además de 25/50/75/100. Solo aparece cuando `Levantado == "N"` (64.828 filas en 12 m) y en esos casos siempre falta `Fecha_hora_pasaje`. En los `"S"` nunca es NA ni 0. | Usado |
| `Numero_caja` | numeric (1–99) | **Sin confirmar.** Está en el 26 % de los levantes (`"S"`). ¿Es el número de caja/compactación del camión? | Descartada por `limpieza_datos.R` |
| `Municipio` | chr (A, B, C, CH, D, E, F, G) | Municipio del circuito | Descartada |
| `Oficina` | chr (`IM`, `Fideicomiso`) | Quién opera el circuito | Descartada |
| `Circuito` | chr | Código largo (ej. `A_DU_RM_CL_103`); se une con `circuitos_periodo` | Descartada (solo se usa `Circuito_corto`) |
| `the_geom` | chr WKT | Ubicación del contenedor en ese pasaje | Descartada |
| `Fecha_hora_pasaje` | POSIXct | En el turno nocturno cae en el día siguiente a `Fecha` (487 k filas con +1 día). 699 filas tienen −1 día, lo que parece un error de carga. | Usado (solo la hora) |
| `circuitos_periodo.Periodo` / `Frecuencia` / `Dias_recoleccion` | num / chr | Días planificados entre levantes y levantes por semana de cada circuito | **Lo escribe `limpieza_datos.R`, pero no está en el repo de datos publicado y `App.R` no lo lee** |

### 7.2 Hallazgos

1. **El "llenado promedio" de la ficha está sesgado hacia abajo.** `resumen_periodo()` promedia `Porcentaje_llenado` sobre todas las filas, incluidos los `"N"` cargados con 0 %. Esos 0 corresponden a incidencias en las que el camión no llegó a revisar el contenedor (Capacidad del camión/Tiempo 21,6 k, Rotura sin retorno 17,4 k, Medidas gremiales 12,8 k, Rotura con retorno 10,6 k). A nivel global el promedio da 69,2 % en lugar de 72,0 %, y en un GID con muchas incidencias la diferencia es bastante mayor. *Corrección:* promediar solo `Levantado == "S"`.
2. **Las incidencias `"N"` son en realidad dos tipos distintos.** (a) Las operativas (camión, rotura, gremial): no hay hora de pasaje y el llenado es 0, así que en la práctica equivalen a "el camión no pasó, con motivo". (b) Las del contenedor (No Está 58 k, Auto 9 k, Fuego 6,6 k, Sobrepeso 5,7 k, Feria 3 k…): el camión estuvo ahí. Hoy la app las muestra juntas como "no levantado, con incidencia".
3. **El "% camión no pasó" está inflado porque cuenta registros y no días.** El 9 % de los pares GID-día tiene 2 o más filas (una segunda pasada). El 31,4 % de las filas `NA` se recuperaron el mismo día en otro turno. El denominador "programados" también cuenta filas.
4. **El `NA` depende de la posición en el recorrido.** En los viajes incompletos, el % de "no pasó" sube de 20 % en el primer decil de posiciones a 61 % en el último. Es la huella de rutas que no se terminan por capacidad o tiempo, no de fallas al azar.
5. **Hubo un cambio en la forma de registrar alrededor de nov-2025.** En sep-oct 2025 el `NA` era 2 % y `"N"` 19–27 %. Desde dic-2025, `NA` ronda el 25 % y `"N"` el 5 %. Comparar tasas de no levante que crucen esa fecha no es válido sin normalizar. *(A confirmar con el usuario.)*
6. **Un no-levante empeora el llenado del levante siguiente.** Esto confirma la hipótesis que había quedado pendiente en la sección 5. Si el pasaje anterior fue `"S"`, el siguiente levante encuentra el contenedor lleno el 31,8 % de las veces (llenado medio 70,8 %). Si fue `"N"`, 52,6 % (79,3 %). Si fue `NA`, 77,4 % (91,1 %). La diferencia es significativa (t-test, p < 1e-200).
7. **La brecha entre municipios es grande.** B y CH levantan el 90–95 % de lo programado, con 13–21 % de saturación. A, D, F y G levantan el 53–56 %, con 33–35 % de "no pasó" y 52–56 % de saturación. Parece un problema de capacidad en esos municipios.
8. **La frecuencia real es menor que la planificada.** Entre jun y sep 2026, la mediana de días reales entre levantes es 1,49 veces el `Periodo` planificado. En 64 de 131 circuitos es más de 1,5 veces; los peores son E_136 (diario → cada 2,3 días) y D_120, D_116, D_115 y F_109 (48 h → cada ~4 días).
9. **El turno y el día de la semana influyen.** El turno vespertino encuentra el contenedor lleno en el 61 % de los levantes, frente al 27–35 % de los otros turnos. Los lunes la saturación es 41,6 %, contra 29,5 % los viernes (acumulación del fin de semana). El "no pasó" es más alto los lunes (26 %) que los domingos (19 %).
10. **Hay contenedores con problemas crónicos.** 607 de los 12.832 GIDs con 20 o más levantes están llenos en más del 80 % de las pasadas (candidatos a sumar capacidad o frecuencia). 890 GIDs tienen "Basura Afuera" en más de la mitad de los levantes. `Condicion` está cargada en el 26 % de los levantes y hoy la app solo la muestra como texto en la tabla.
11. **La calidad de las claves es buena.** No hay filas duplicadas por gid-fecha-viaje-posición. Solo 5 GIDs del histórico no están en activos ni en inactivos, 11 activos no tienen registros en 12 meses y ningún GID figura a la vez como activo e inactivo. 180 GIDs cambiaron de circuito en el año.

### 7.3 Recomendaciones (priorizadas)

**Correcciones (cambian números que ya se muestran):**
- Calcular el llenado promedio solo con `Levantado == "S"`.
- Calcular "% no pasó" y "% incidencia" por **día** (un día cuenta como levantado si hubo al menos un `"S"`), igual que ya lo hace la línea de tiempo.
- Dividir "incidencia" en *operativa* (el camión no llegó) y *del contenedor* (el camión llegó y no pudo levantar).

**Datos nuevos que se pueden mostrar con lo que ya existe:**
- En la ficha del GID: frecuencia real contra la planificada (`circuitos_periodo.Periodo`, `Dias_recoleccion`) y el motivo de incidencia más frecuente.
- En la ficha del GID: el % de levantes con cada `Condicion` (Basura Afuera, Requiere Limpieza/Mantenimiento).
- Una pestaña **Circuito / Municipio** con % levantado, % no pasó, saturación y frecuencia real vs plan, más el ranking de circuitos con peor desvío. Para eso habría que dejar de descartar `Municipio`, `Oficina` y `Circuito` en `limpieza_datos.R` y leer el pin `circuitos_periodo`.
- Una capa del mapa coloreada por saturación o por % no pasó en los últimos N días, para ver zonas críticas.
- Un listado de "contenedores críticos": saturados en más del 80 %, con basura afuera crónica o con varios `NA` seguidos.

**Pendientes / preguntas abiertas:**
- ¿Qué es `Numero_caja`?
- ¿Qué cambió en la carga de `Levantado` alrededor de nov-2025?
- ¿Se volvió a correr `limpieza_datos.R`? El pin `circuitos_periodo` no está en `APP_nuevoinforme-data`.

### 7.4 Cambio 2026-09-26: qué se aplicó en la app

Decisiones del usuario sobre la sección 7.3:
- **Llenado promedio:** corregido. Tanto el resumen como la línea de tiempo usan solo `Levantado == "S"`.
- **"% camión no pasó" contado por registros:** **se mantiene así.** Según el usuario el valor es correcto: cada registro `NA` es un viaje planificado que no se hizo o no se completó, aunque el contenedor se haya levantado en otra pasada el mismo día.
- **Separar incidencias operativas y del contenedor:** pendiente, a la espera de que el usuario lo evalúe.
- **`Numero_caja`:** no se usa por ahora.
- **Cambio en la carga de `Levantado` en nov-2025:** el usuario no lo recuerda. Hasta confirmarlo, no comparar tasas de no levante de antes y después de esa fecha.

Qué se agregó:
- `limpieza_datos.R` publica también `Municipio` y `Oficina` en el pin del histórico. El peso del pin prácticamente no cambia (~33 MB), porque el rds comprime bien los textos repetidos. `Circuito` no se agregó: la app une con `circuitos_periodo` por `Circuito_corto`.
- En la ficha del GID:
  - frecuencia real comparada con la planificada del circuito;
  - motivo más frecuente de no levante;
  - sección "Estado del contenedor", con el % de levantes que tuvo cada observación de `Condicion`.
- Una pestaña nueva, **Circuitos**, con período y filtro por municipio. Incluye tres tablas:
  - por municipio;
  - por circuito, ordenada por atraso (días reales / días planificados; más de 1,5 se marca en rojo);
  - contenedores críticos: al menos 5 levantes en el período, y lleno en el 80 % o más de ellos o con "Basura Afuera" en el 50 % o más. Un click abre el historial.
- En el mapa, los activos se pueden colorear según % lleno al levantar o % "no pasó" de los últimos 30 días. El popup muestra esos dos valores.
- Compatibilidad: si el pin publicado no trae `Municipio`/`Oficina`, se completan desde `circuitos_periodo` o desde el prefijo del circuito. Si falta `circuitos_periodo`, las columnas de plan y atraso quedan vacías y la pestaña muestra un aviso.
- Los umbrales son constantes al inicio de `App.R` (`UMBRAL_ATRASO`, `UMBRAL_SATURACION`, `UMBRAL_BASURA_AFUERA`, `MIN_LEVANTES_CRITICO`, `DIAS_INDICADORES_MAPA`).
- Nota: con los umbrales actuales y un período de 30 días, la lista de críticos tiene ~2.300 contenedores. Si resulta demasiado larga, subir `MIN_LEVANTES_CRITICO` o `UMBRAL_SATURACION`.
