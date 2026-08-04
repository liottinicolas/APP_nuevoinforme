# Documentación de análisis: Peores contenedores por saturación (historico_llenadoGol.rds)

_Última actualización: 2026-08-03_

## 1. Contexto de negocio

**Objetivo del análisis:** identificar los contenedores del Municipio B que están en peor estado de saturación (llegan a 100% de llenado con frecuencia) en los últimos 30 días, para priorizar acciones (agregar capacidad o aumentar frecuencia de recolección).

**Preguntas de negocio a responder:**
- ¿Cuáles son los contenedores que más se saturan (Porcentaje_llenado == 100) en Municipio B?
- Dado que un 100% aislado no es necesariamente grave, ¿cómo distinguir un contenedor realmente subdimensionado (se satura aunque lo recolecten seguido) de uno que solo necesita más frecuencia de recolección?

**Entrevista realizada (preguntas y respuestas):**

| Pregunta | Respuesta | Quién la respondió |
|---|---|---|
| ¿Qué visitas cuentan como "recolección efectiva"? | Solo filas con `Levantado == "S"` (no se suman los `N` con dato de sensor) | Usuario |
| ¿Qué se considera "contenedor saturado" en una visita? | Exactamente `Porcentaje_llenado == 100` (no se usa umbral de "casi lleno" ≥90%) | Usuario |
| ¿Cómo priorizar el ranking de "peores", dado que 100% depende de la frecuencia? | Cruzar tasa de saturación con frecuencia efectiva de recolección (enfoque de cuadrante), en vez de ordenar solo por tasa de saturación pura | Usuario |
| Municipio y período a analizar | Municipio B, últimos 30 días | Usuario (pedido original) |

**Supuestos asumidos sin confirmar** (no bloquean el análisis, pero conviene validarlos si se van a tomar decisiones grandes en base a esto):
- **`gid` = identidad del contenedor físico individual.** Se usa `gid` (no `Circuito`+`Posicion` ni `Numero_caja`) como unidad de análisis porque es el identificador estable de "Gestión de GIDs" usado en el resto del proyecto (ver `docs/modules/10-app-informe-llenado.md`). Se verificó que un mismo `gid` puede tener hasta 10 direcciones distintas registradas y hasta 3 circuitos distintos en todo el histórico (probablemente por reasignaciones de ruta/renombres de dirección a lo largo del tiempo), pero dentro de una ventana de 30 días esto es prácticamente siempre estable (se usa la dirección/circuito más reciente en la ventana). Impacto si es incorrecto: contenedores podrían estar fusionados o separados incorrectamente si `gid` no representa un contenedor físico único.
- **Ventana de "últimos 30 días" anclada a la última fecha disponible en la data (2026-08-02), no a la fecha del sistema (2026-08-03).** Se eligió así porque es el criterio reproducible: la carga de datos puede tener un día de rezago. Impacto si es incorrecto: el informe queda con un día de desfasaje respecto a "hoy", que se considera despreciable.
- **Umbral "alto/bajo" para el cuadrante = mediana** de `tasa_saturacion` y de `frecuencia_dias` dentro del propio subconjunto analizado (Municipio B, ventana), no un valor de negocio fijo (ej. "≥20% de saturación es alto"). Es un criterio estadístico estándar para matrices de 2x2 (similar a una matriz BCG), pero es relativo a la muestra: si el problema de saturación es generalizado en todo el municipio, la mediana sube y el punto de corte se vuelve menos exigente. Impacto si es incorrecto: conviene revisar si el usuario prefiere fijar umbrales de negocio absolutos en vez de relativos.
- **Mínimo de 3 recolecciones efectivas en la ventana** para incluir un contenedor en el análisis de frecuencia/cuadrante (se excluyeron 8 de 1417 contenedores con datos por tener 1-2 recolecciones, insuficiente para estimar un intervalo confiable). Impacto: contenedores muy nuevos o con muy poca actividad en el período no aparecen en el ranking.

## 2. Diccionario de datos

Solo se documentan las columnas relevantes para este análisis (dataset completo tiene 18 columnas, 3.176.629 filas, período total 2025-03-01 a 2026-08-02).

| Columna | Tipo de dato | Significado de negocio | Valores posibles / formato | Notas |
|---|---|---|---|---|
| `Fecha` | Date | Día de la visita/paso programado del camión por esa posición del circuito | fecha | |
| `Circuito` / `Circuito_corto` | chr | Identificador de la ruta de recolección | ej. `A_DU_RM_CL_103` / `B_01` | Un `gid` puede figurar en más de un circuito a lo largo del histórico completo (reasignaciones de ruta) |
| `Municipio` | chr | Municipio al que pertenece el circuito | A, B, C, CH, D, E, F, G | Filtro pedido: `B` |
| `Direccion` | chr | Dirección física asociada a esa posición | texto libre | Un `gid` puede tener múltiples direcciones registradas en el histórico completo (~2 en promedio) |
| `gid` | chr | **Identificador único del contenedor físico** (usado como unidad de análisis) | numérico como texto | 14.829 gid únicos en todo el dataset; 1.418 en Municipio B / últimos 30 días |
| `Levantado` | chr | Si el camión efectivamente recolectó el contenedor ese día | `S` (sí), `N` (no), `NA` (sin registro) | `NA` representa ~20-25% de las filas de forma persistente en todo el histórico (no es solo un rezago de carga reciente); en Municipio B/últimos 30 días es bajo (3.5%) |
| `Incidencia` | chr | Motivo por el que NO se recolectó (solo tiene valor cuando `Levantado == "N"`) | ej. "Contenedor No Está", "Calle Cerrada" | |
| `Porcentaje_llenado` | num | % de llenado del contenedor medido en el momento del paso del camión | 0-100 | Solo tiene valor cuando `Levantado == "S"` (100% de los casos en la muestra analizada); cuando `Levantado == "N"` a veces también tiene valor (lectura de sensor sin recolección), pero por decisión del usuario esos casos NO se usan en este análisis |
| `Condicion` | chr | Estado físico/observaciones del contenedor reportadas por la cuadrilla (ej. "Basura Afuera", "Requiere Mantenimiento", "Escombro") | texto combinado con `;` | No se usó en este análisis, pero es una fuente rica para un análisis futuro de causas (ver Recomendaciones) |
| `contenedor_activo` | chr | Si el contenedor está activo en el sistema | S / N | No se filtró explícitamente porque el filtro por Municipio+ventana de 30 días ya deja prácticamente solo contenedores activos |
| `Numero_caja` | num | **No es el contenedor** — solo 57 valores únicos en todo el dataset, probablemente identifica la caja/tolva del camión, no el contenedor recolectado | | No usar como identificador de contenedor |

## 2.1. Diccionario de la tabla generada (salida del informe)

Columnas de las hojas "Peores contenedores" / "Todos los contenedores" del Excel (una fila = un `gid` dentro de la ventana analizada):

| Columna | Tipo | Significado | Cómo se calcula | Notas |
|---|---|---|---|---|
| `gid` | texto | Identificador único del contenedor | — | Unidad de análisis (ver supuesto en sección 1) |
| `Direccion` | texto | Dirección física del contenedor | Se toma la dirección registrada en la fecha más reciente de la ventana para ese `gid` | Referencia para ubicar el contenedor en el territorio, no interviene en los cálculos |
| `Circuito_corto` | texto | Circuito/ruta de recolección al que pertenece | Igual que `Direccion`, la más reciente en la ventana | ej. `B_01`, `B_103` |
| `n_recolecciones` | entero | Cantidad de recolecciones efectivas del contenedor en la ventana de 30 días | `n()` de filas con `Levantado == "S"` y `Porcentaje_llenado` no nulo | Base para todos los cálculos siguientes; mínimo 3 por el filtro de confiabilidad |
| `n_saturaciones` | entero | Cuántas de esas recolecciones encontraron el contenedor exactamente al 100% | `sum(Porcentaje_llenado == 100)` | |
| `tasa_saturacion` | decimal (0-1) | Proporción de recolecciones en las que el contenedor estaba saturado (100%) | `n_saturaciones / n_recolecciones` | Es la métrica principal de severidad — 0.83 significa que 83% de las veces que pasó el camión, el contenedor ya estaba lleno |
| `llenado_promedio` | decimal (0-100) | Nivel de llenado promedio del contenedor al momento de la recolección | `mean(Porcentaje_llenado)` sobre las recolecciones efectivas | Da una idea de qué tan cerca del límite está incluso cuando no llega a saturar del todo |
| `frecuencia_dias` | decimal | Promedio de días entre recolecciones efectivas (ver explicación detallada más abajo) | `(última_fecha − primera_fecha) / (n_recolecciones − 1)` | Valor bajo (~1) = se recolecta seguido; valor alto = pasan varios días entre recolección y recolección |
| `cuadrante` | texto | Clasificación de la causa probable de la saturación, cruzando `tasa_saturacion` y `frecuencia_dias` contra la mediana de cada una dentro de la muestra | Ver sección 1 (umbrales) | 3 valores posibles: `"Subdimensionado (satura pese a recolección frecuente)"`, `"Aumentar frecuencia resolvería"`, `"OK / bajo riesgo"` |

**Sobre `frecuencia_dias`:** es el rango total de días que cubren las recolecciones de ese contenedor en la ventana, dividido entre la cantidad de "saltos" entre recolecciones (`n_recolecciones - 1`). Ejemplo: 30 recolecciones repartidas entre el día 1 y el día 30 de la ventana → `frecuencia_dias = 29/29 = 1` (recolección diaria). 13 recolecciones entre el día 1 y el día 28 → `frecuencia_dias = 27/12 ≈ 2.25` (cada ~2.25 días en promedio). No es un promedio de gaps calculado gap por gap, pero da el mismo resultado salvo huecos irregulares al inicio/fin de la ventana.

La hoja "Resumen por cuadrante" agrega estas mismas columnas (`tasa_saturacion`, `frecuencia_dias`) como promedio por grupo, más la columna `contenedores` (cantidad de `gid` en ese cuadrante).

## 3. Decisiones de limpieza

| Decisión | Motivo | Filas/valores afectados |
|---|---|---|
| Se filtró `Municipio == "B"` y `Fecha` entre 2026-07-04 y 2026-08-02 (últimos 30 días con datos) | Pedido explícito del usuario | De 3.176.629 filas totales a 38.864 |
| Se usaron solo filas con `Levantado == "S"` y `Porcentaje_llenado` no nulo como "recolección efectiva" | Criterio confirmado con el usuario (ver entrevista) | De 38.864 filas del subconjunto a 36.886 |
| Se excluyeron contenedores con menos de 3 recolecciones efectivas en la ventana | Con 1-2 datos no se puede estimar una frecuencia de recolección representativa; incluirlos generaría ranking ruidoso | 8 de 1.417 contenedores con al menos 1 dato |

## 4. Hallazgos y conclusiones

- **La mayoría de los contenedores de Municipio B se recolectan a diario.** La frecuencia efectiva promedio (mediana) es de 1 día entre recolecciones — cómo se llegó: se calculó el intervalo promedio entre fechas consecutivas con `Levantado == "S"` por `gid`. Por qué importa: significa que, para la mayoría de los contenedores saturados, **el problema no se resuelve aumentando la frecuencia** (ya es diaria) — es un problema de capacidad/subdimensionamiento.
- **889 de 1.409 contenedores evaluados (63%) están en la zona de riesgo del cuadrante** (saturación por encima de la mediana), de los cuales **509 se recolectan con frecuencia alta (≤1 día) y aun así se saturan** — estos son los casos más urgentes, porque agregar más recolecciones no cambiaría el resultado; lo que se necesita es más capacidad (contenedor adicional o de mayor volumen).
- **380 contenedores se saturan y además se recolectan con baja frecuencia (>1 día en promedio, hasta 8.7 días)** — en estos casos, aumentar la frecuencia de recolección es una palanca directa y probablemente más barata que agregar capacidad.
- **El peor contenedor identificado (gid 181516, calle Ing. Carlos María Maggiolo 740, circuito B_103)** se satura en el 92% de sus recolecciones efectivas (12 de 13 visitas en 30 días), con una frecuencia real de recolección de 2.3 días — es decir, se satura casi siempre pese a no estar en el grupo de recolección diaria; sería una prioridad para revisar tanto capacidad como frecuencia.

## 5. Recomendaciones

- **Priorizar aumento de capacidad (no de frecuencia)** en los 509 contenedores del cuadrante "Subdimensionado" — son colectados a diario y aun así llegan al 100%. Agregar más recolecciones no resolvería el problema.
- **Evaluar aumentar la frecuencia de recolección** en los 380 contenedores del cuadrante "Aumentar frecuencia resolvería" antes de invertir en capacidad adicional, ya que es probablemente la intervención más económica.
- **Cruzar este ranking con la columna `Condicion`** (no usada en este análisis) en un próximo paso, para ver si los contenedores más saturados también acumulan reportes de "Basura Afuera" o "Requiere Mantenimiento" — daría una segunda señal de urgencia.
- **Revisar el criterio de umbral "alto/bajo" del cuadrante** con el equipo de operaciones: hoy es relativo (mediana de la muestra); si existe un umbral operativo conocido (ej. "más de 1 de cada 5 recolecciones al 100% es inaceptable"), conviene fijarlo como valor absoluto en vez de relativo.

## 6. Fuentes y metodología

- **Origen de los datos:** `db/GOL_reportes/historico_llenadoGol.rds`, generado por `db/GOL_reportes/funciones_db_golReportesDiarios.R` a partir de `archivos/GOL_reportes/*.csv` (reportes de llenado/levante por viaje GOL).
- **Período cubierto por el informe:** 2026-07-04 a 2026-08-02 (últimos 30 días con datos disponibles), Municipio B.
- **Herramientas usadas:** R (`dplyr`, `writexl`, `sf`, `jsonlite`), scripts `PorcentajeLlenado.R` (Excel), `generar_informe_html.R` + `armar_html.R` (HTML).
- **Salida:**
  - `informes/salidas/peores_contenedores_MunicipioB.xlsx` (hojas: "Peores contenedores", "Todos los contenedores", "Resumen por cuadrante").
  - `informe_peores_contenedores_MunicipioB.html` (informe standalone, autocontenido): mapa Leaflet con los 1.409 contenedores evaluados (color y tamaño = tasa de saturación, escala secuencial de un solo hue rojo con tamaño en raíz cuadrada, según la skill de dataviz) + tabla de los 889 contenedores en riesgo (sin la columna `cuadrante`, con filtro de texto y orden por columna). Las coordenadas se transforman de `the_geom` (EPSG:32721, mismo CRS que usa `vistas/App_informe_llenado/App.R`) a lat/lon (EPSG:4326) con `sf`. La librería Leaflet (JS+CSS) está **embebida localmente** en el HTML (copiada de `informes/_vendor/leaflet/`, que a su vez viene del paquete R `leaflet` instalado en la máquina) en vez de cargarse desde un CDN — un CDN externo (`unpkg.com`) quedaba bloqueado por política de red/CSP. El mapa base (imágenes de fondo) usa teselas de **CARTO Positron** (`basemaps.cartocdn.com/light_all`, atribución OpenStreetMap + CARTO) en vez de las teselas propias de `tile.openstreetmap.org` — se cambió porque el dominio de OSM quedaba bloqueado en el entorno del usuario; solo se necesita internet para bajar estas imágenes de fondo (la librería Leaflet ya está embebida localmente, ver arriba).
- **Limitaciones conocidas:**
  - El análisis no distingue si un contenedor fue reemplazado físicamente (mismo `gid`, otro objeto) durante la ventana.
  - No se cruzó con datos de planificación de circuitos (`db/planificados/`), que definen la frecuencia *programada* (vs. la efectiva calculada acá); un contenedor con baja frecuencia efectiva podría deberse a que no estaba programado para recolección diaria, no a un incumplimiento de ruta. Sería un enriquecimiento natural de este análisis.
  - El umbral de "saturación alta" es relativo a la muestra (mediana), no un valor de negocio fijo.
