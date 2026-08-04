# Documentación de análisis: Peores contenedores por Condicion (historico_llenadoGol.rds)

_Última actualización: 2026-08-03_

## 1. Contexto de negocio

**Objetivo del análisis:** identificar los contenedores del Municipio B que acumulan con más frecuencia los reportes de la cuadrilla "Basura Afuera" y/o "Requiere Limpieza" en los últimos 30 días, para priorizar acciones (más capacidad/otro contenedor, más frecuencia de recolección, o intervención sobre el entorno).

Es la réplica del análisis de saturación (`informes/Porcentaje_llenado_peorescasos/`, ver `documentacion_analisis_peores_contenedores.md`) usando la columna `Condicion` en lugar de `Porcentaje_llenado` — ese documento ya anticipaba en su sección de Recomendaciones cruzar el ranking de saturación con `Condicion`; este análisis lo hace como pieza independiente, con la misma metodología.

**Preguntas de negocio a responder:**
- ¿Cuáles son los contenedores que más veces son reportados con "Basura Afuera" y/o "Requiere Limpieza" en Municipio B?
- Igual que con la saturación: ¿cómo distinguir un contenedor que acumula el problema pese a recolección frecuente (probable falta de capacidad o causa externa) de uno que mejoraría solo con más frecuencia de recolección?

**Entrevista realizada (preguntas y respuestas):**

| Pregunta | Respuesta | Quién la respondió |
|---|---|---|
| ¿Qué significa `Condicion == NA` en una recolección efectiva? | "Sin problema" (no es un dato faltante) — el campo es de excepción, igual que `Incidencia`, y solo se completa cuando la cuadrilla encuentra algo. El denominador de la tasa es TODAS las recolecciones efectivas, no solo las que tienen `Condicion` cargada | Usuario |
| ¿Se mantiene el cruce de cuadrante (tasa del problema × frecuencia de recolección) usado en el análisis de saturación? | Sí, adaptado: alta tasa + recolección frecuente sugiere capacidad insuficiente o causa externa (no se arregla con más frecuencia); alta tasa + baja frecuencia sugiere que aumentar la frecuencia podría ayudar | Usuario |
| ¿Cómo tratar "Basura Afuera" y "Requiere Limpieza"? | Tasa combinada (OR, "y/o") para el ranking y el mapa, más desglose de cada una como columnas separadas en la tabla | Usuario |
| Municipio y período a analizar | Municipio B, últimos 30 días (mismo criterio que el análisis de saturación) | Usuario (pedido original) |

**Supuestos asumidos sin confirmar** (heredados del análisis de saturación, siguen aplicando igual acá — ver ese documento para el detalle completo):
- `gid` como identidad del contenedor físico individual.
- Ventana de "últimos 30 días" anclada a la última fecha disponible en la data (2026-08-02), no a la fecha del sistema.
- Umbral "alto/bajo" del cuadrante = mediana de la propia muestra, no un valor de negocio fijo.
- Mínimo de 3 recolecciones efectivas en la ventana para incluir un contenedor en el ranking.

**Supuesto nuevo de este análisis:**
- **`Condicion` se evalúa por *substring* (`grepl`), no por coincidencia exacta.** El campo combina varios valores con `;` (ej. `"Basura Afuera;Dos Ciclos;Escombro"`). Existe un script previo en el repo, `scripts/generar_mapas_KML.R::generar_reportes_limpieza()`, que filtra con `Condicion %in% c("Basura Afuera", "Escombro", "Poda")` — esto es coincidencia **exacta** de toda la celda, por lo que ignora todas las filas donde el valor viene combinado con otras condiciones (que, verificado contra los datos, son la mayoría de los casos reales). Por eso este análisis usa `grepl("Basura Afuera", Condicion, fixed = TRUE)` y lo mismo para "Requiere Limpieza", detectando la presencia del texto en cualquier posición del campo combinado. Impacto si esto no es lo que se buscaba: si se prefiriera el criterio de coincidencia exacta (como en `generar_mapas_KML.R`), los conteos serían mucho más bajos y probablemente poco representativos, dado que la inmensa mayoría de los valores de `Condicion` en la ventana analizada vienen combinados.

## 2. Diccionario de datos

Columnas reutilizadas del análisis de saturación (`Fecha`, `Circuito`/`Circuito_corto`, `Municipio`, `Direccion`, `gid`, `Levantado`, `contenedor_activo`, `Numero_caja`) tienen el mismo significado ya documentado en `informes/Porcentaje_llenado_peorescasos/documentacion_analisis_peores_contenedores.md`, sección 2. Acá se detalla específicamente la columna protagonista de este análisis:

| Columna | Tipo de dato | Significado de negocio | Valores posibles / formato | Notas |
|---|---|---|---|---|
| `Condicion` | chr | Observaciones que la cuadrilla registra sobre el estado del contenedor/entorno al momento de la recolección | Texto combinado con `;`, ej. `"Basura Afuera;Requiere Limpieza"`, `"Escombro"`, `"Requiere Mantenimiento"` | Campo de excepción: NA en el 75.5% de las filas del subconjunto analizado (Municipio B/30 días); de las filas con dato, 9.501 de 9.503 (99.98%) tienen `Levantado == "S"` — se comporta igual que `Incidencia`, que solo se completa cuando hay algo que reportar |
| `flag_basura_afuera` (derivada) | lógico | Si esa recolección incluyó el reporte "Basura Afuera" | `grepl("Basura Afuera", Condicion, fixed = TRUE)`, `NA` tratado como `FALSE` | 8.660 de 38.864 filas del subconjunto |
| `flag_requiere_limpieza` (derivada) | lógico | Si esa recolección incluyó el reporte "Requiere Limpieza" | `grepl("Requiere Limpieza", Condicion, fixed = TRUE)`, `NA` tratado como `FALSE` | 1.710 de 38.864 filas del subconjunto |

## 2.1. Diccionario de la tabla generada (salida del informe)

Columnas de las hojas "Peores contenedores" / "Todos los contenedores" del Excel, y del mapa/tabla del HTML (una fila = un `gid` dentro de la ventana analizada):

| Columna | Tipo | Significado | Cómo se calcula | Notas |
|---|---|---|---|---|
| `gid` | texto | Identificador único del contenedor | — | |
| `Direccion` / `direccion` | texto | Dirección física del contenedor | La más reciente en la ventana para ese `gid` | |
| `Circuito_corto` / `circuito` | texto | Circuito/ruta de recolección | La más reciente en la ventana | ej. `B_01`, `B_101` |
| `n_recolecciones` | entero | Cantidad de recolecciones efectivas (`Levantado == "S"`) en la ventana de 30 días | `n()` | Base de todos los cálculos; mínimo 3 por el filtro de confiabilidad |
| `n_basura_afuera` | entero | Cuántas de esas recolecciones tuvieron el reporte "Basura Afuera" | `sum(flag_basura_afuera)` | |
| `n_requiere_limpieza` | entero | Cuántas de esas recolecciones tuvieron el reporte "Requiere Limpieza" | `sum(flag_requiere_limpieza)` | |
| `n_alguna_condicion` | entero | Cuántas recolecciones tuvieron "Basura Afuera" y/o "Requiere Limpieza" | `sum(flag_basura_afuera | flag_requiere_limpieza)` | Puede ser menor a `n_basura_afuera + n_requiere_limpieza` si ambas ocurren en la misma visita |
| `tasa_condicion` | decimal (0-1) | Proporción de recolecciones con alguno de los dos reportes | `n_alguna_condicion / n_recolecciones` | Métrica principal de severidad — 1.0 significa que el problema se reportó en el 100% de las recolecciones |
| `frecuencia_dias` | decimal | Promedio de días entre recolecciones efectivas | Misma fórmula que en el análisis de saturación: `(última_fecha − primera_fecha) / (n_recolecciones − 1)` | Valor bajo (~1) = recolección diaria; valor alto = recolección espaciada |
| `cuadrante` | texto | Clasificación de la causa probable, cruzando `tasa_condicion` y `frecuencia_dias` contra la mediana de cada una en la muestra | Ver sección 1 | 3 valores: `"Persiste pese a recolección frecuente (posible falta de capacidad o causa externa)"`, `"Aumentar frecuencia podría ayudar"`, `"OK / bajo riesgo"` — no se incluye en la tabla del informe HTML (a pedido del usuario, igual que en el informe de saturación) |

La hoja "Resumen por cuadrante" del Excel agrega estas mismas columnas como promedio por grupo, más `contenedores` (cantidad de `gid` en ese cuadrante).

## 3. Decisiones de limpieza

| Decisión | Motivo | Filas/valores afectados |
|---|---|---|
| Se filtró `Municipio == "B"` y `Fecha` entre 2026-07-04 y 2026-08-02 (últimos 30 días con datos) | Mismo criterio que el análisis de saturación | De 3.176.629 filas totales a 38.864 |
| Se usaron solo filas con `Levantado == "S"` como "recolección efectiva", SIN filtrar por `!is.na(Condicion)` | A diferencia de `Porcentaje_llenado` (que exigía dato no nulo), acá `NA` es una categoría válida = "sin problema", así que se mantiene en el denominador | 36.886 recolecciones efectivas en la ventana (mismo universo que el análisis de saturación) |
| Se excluyeron contenedores con menos de 3 recolecciones efectivas en la ventana | Mismo criterio de confiabilidad que el análisis de saturación | 8 de 1.417 contenedores con al menos 1 dato |
| Se detectó "Basura Afuera"/"Requiere Limpieza" con `grepl` (substring), no con `%in%` (coincidencia exacta) | El campo combina valores con `;`; un match exacto ignoraría la mayoría de los casos reales (ver supuesto en sección 1) | Difiere del criterio usado en `scripts/generar_mapas_KML.R::generar_reportes_limpieza()` |

## 4. Hallazgos y conclusiones

- **El problema está mucho más extendido que la saturación por llenado.** 1.102 de 1.418 gid (77.7%) tuvieron al menos una ocurrencia de "Basura Afuera" o "Requiere Limpieza" en la ventana, con una mediana de 4 ocurrencias por contenedor (máximo 26). La mediana de `tasa_condicion` en la muestra confiable es 16.7% (vs. 3.3% de `tasa_saturacion` en el análisis de llenado) — cómo se llegó: se calculó sobre los 1.409 contenedores con al menos 3 recolecciones efectivas. Por qué importa: sugiere que "Basura Afuera"/"Requiere Limpieza" es un problema más frecuente y posiblemente más visible para los vecinos que la saturación pura del contenedor.
- **717 de 1.409 contenedores evaluados (51%) están en zona de riesgo** (tasa por encima de la mediana), repartidos en dos grupos con implicancias distintas:
  - **431 contenedores "persisten pese a recolección frecuente"** (frecuencia ≤1 día) — el problema no se resuelve recolectando más seguido; sugiere volumen insuficiente para la demanda del lugar, mal uso del entorno (gente dejando bolsas fuera del contenedor), o necesidad de intervención distinta a logística de recolección.
  - **286 contenedores "aumentar frecuencia podría ayudar"** (frecuencia >1 día, hasta varios días entre recolecciones) — acá sí hay una palanca directa de recolección.
- **El peor caso combinado (gid 181192, Nicaragua 1555, circuito B_101)** tiene el reporte en el 100% de sus recolecciones efectivas (9 de 9), con una frecuencia de 3.5 días entre recolecciones — cae en el grupo "aumentar frecuencia podría ayudar".
- **El peor caso con recolección diaria (gid 181137, Av. Uruguay 1884, circuito B_04)** acumula el reporte en 26 de 30 recolecciones (86.7%) pese a ser recolectado todos los días — cae en "persiste pese a recolección frecuente", y es candidato a revisión de capacidad/entorno antes que de logística.

## 5. Recomendaciones

- **Priorizar revisión de capacidad/entorno** (no de frecuencia) en los 431 contenedores del grupo "Persiste pese a recolección frecuente" — ya se recolectan a diario y el problema se repite igual.
- **Evaluar aumentar la frecuencia de recolección** en los 286 contenedores del grupo "Aumentar frecuencia podría ayudar" antes de otras intervenciones más costosas.
- **Cruzar este ranking con el de saturación** (`informes/Porcentaje_llenado_peorescasos/`) para ver superposición: un contenedor que aparece en ambos rankings (satura Y acumula basura afuera/requiere limpieza) es una señal más fuerte de urgencia que aparecer en uno solo.
- **Considerar un tercer análisis futuro sobre "Requiere Mantenimiento"** (valor distinto de `Condicion`, no incluido acá porque el pedido fue específicamente sobre "Basura Afuera" y "Requiere Limpieza") si el negocio también quiere priorizar contenedores con problemas mecánicos/de infraestructura.

## 6. Fuentes y metodología

- **Origen de los datos:** mismo que el análisis de saturación — `db/GOL_reportes/historico_llenadoGol.rds`.
- **Período cubierto por el informe:** 2026-07-04 a 2026-08-02 (últimos 30 días con datos disponibles), Municipio B.
- **Herramientas usadas:** R (`dplyr`, `writexl`, `sf`, `jsonlite`), scripts `PeoresCondicion.R` (Excel), `generar_informe_html.R` + `armar_html.R` (HTML) — mismo patrón de scripts que `Porcentaje_llenado_peorescasos/`.
- **Salida:**
  - `informes/Condicion_peorescasos/salidas/peores_condicion_MunicipioB.xlsx` (hojas: "Peores contenedores", "Todos los contenedores", "Resumen por cuadrante").
  - `informe_peores_condicion_MunicipioB.html` (informe standalone): mapa Leaflet con los 1.409 contenedores evaluados (color y tamaño = `tasa_condicion`, misma paleta secuencial roja y escala de tamaño en raíz cuadrada que el informe de saturación) + tabla de los 717 contenedores en riesgo (sin la columna `cuadrante`, con filtro de texto, orden por columna y botón de descarga CSV). La librería Leaflet (JS+CSS) está **embebida localmente** (copiada de `informes/_vendor/leaflet/`, compartida con el informe de saturación) en vez de cargarse desde un CDN — el mapa base usa teselas de **CARTO Positron** (`basemaps.cartocdn.com/light_all`) en vez de `tile.openstreetmap.org` (mismo motivo y cambio que en el informe de saturación); solo se necesita internet para bajar estas imágenes de fondo.
- **Relación con otros scripts del repo:** existe `scripts/generar_mapas_KML.R::generar_reportes_limpieza()`, que hace un ranking similar pero con coincidencia exacta de `Condicion`, sin filtro de `Levantado`, sin ventana fija ni cuadrante, y exporta a KML en vez de HTML+Excel. No se modificó ni se reemplazó ese script; este análisis es independiente y metodológicamente más estricto (ver sección 1).
- **Limitaciones conocidas:**
  - Mismas limitaciones que el análisis de saturación (identidad de `gid` ante reemplazos físicos, no se cruzó con `db/planificados/` para frecuencia programada, umbral de cuadrante relativo a la muestra).
  - No se investigó si "Basura Afuera" y "Requiere Limpieza" tienen causas distintas entre sí (ej. una podría deberse a mal uso del entorno y la otra a falta de mantenimiento) — el desglose por columna separada en la tabla permite ese análisis pero no se interpretó en profundidad acá.
