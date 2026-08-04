---
name: analisis-de-datos
description: >
  Guía completa para analizar datos de principio a fin (CSV, Excel, bases de datos SQL, APIs, o cualquier dataset)
  siguiendo un flujo profesional de analista — primero entender la lógica de negocio preguntando hasta no tener
  ninguna duda, documentar el significado de cada columna en un diccionario de datos, limpiar y explorar la
  información, validar hallazgos con estadística, visualizar y contar la historia de los datos, y registrar de
  forma continua todas las conclusiones y hallazgos de valor en un archivo de documentación. Usar SIEMPRE que el
  usuario pida analizar, explorar, limpiar, cruzar o sacar conclusiones de un dataset, CSV, hoja de cálculo, tabla
  de base de datos, resultado de una query SQL, o cuando mencione "análisis de datos", "EDA", "diccionario de
  datos", "insights", "hallazgos", "dashboard", o quiera entender qué dice la información antes de tomar una
  decisión de negocio, incluso si no lo pide explícitamente con esas palabras.
---

# Análisis de Datos

## Por qué existe esta skill

Cualquiera puede correr un `.describe()` sobre un CSV. Lo que separa un análisis útil de uno inútil es dos cosas: (1) entender qué significan los datos *en el negocio* antes de sacar conclusiones sobre ellos, y (2) dejar un rastro escrito de lo que se aprendió, para que otra persona (muchas veces sin perfil técnico) pueda confiar en las conclusiones sin tener que reconstruir el trabajo.

Esta skill te guía por las cuatro fases de un análisis serio y, sobre todo, te obliga a dos hábitos que son fáciles de saltear bajo presión: **preguntar antes de asumir** y **documentar mientras avanzás**, no al final de memoria.

## Regla de oro: nunca asumas la lógica de negocio

Los datos rara vez se explican solos. Una columna llamada `status` puede tener códigos que solo alguien del negocio conoce. Una fecha puede estar en UTC o en hora local. Un cliente "activo" puede significar cosas distintas según el equipo que lo pregunte. Si asumís el significado y te equivocás, todo el análisis que sigue está construido sobre una base falsa — y eso es peor que no analizar nada, porque genera confianza injustificada.

Por eso, la Fase 0 (más abajo) es obligatoria y va primero, siempre, sin excepción, incluso si el usuario tiene apuro. Es más rápido preguntar 5 minutos ahora que rehacer el análisis después de presentarlo mal.

## El documento vivo: `documentacion_analisis.md`

Desde el primer momento en que tocás los datos, creá (o actualizá) un único archivo de documentación que acompaña todo el análisis: `documentacion_analisis.md`, basado en la plantilla de `assets/plantilla_documentacion.md`. Guardalo en el directorio de trabajo y actualizalo en cada fase — no lo dejes para el final. Si al final tratás de reconstruir de memoria qué significaba cada columna o qué hallazgos fueron relevantes, vas a perder información. Documentá en el momento en que la descubrís.

Si el usuario pide explícitamente el diccionario o el reporte en Excel, generá también una versión `.xlsx` (usar la skill `xlsx` para eso) con las mismas secciones en hojas separadas.

## Flujo de trabajo

| Fase | Qué hace | Detalle |
|---|---|---|
| 0. Entender el negocio | Preguntar hasta no tener dudas | ver abajo |
| 1. Diccionario y limpieza | Documentar columnas, limpiar datos | ver abajo |
| 2. EDA | Estadísticas, segmentos, tendencias | `references/eda.md` |
| 3. SQL y obtención de datos | Queries, APIs, JSON, scraping | `references/sql_y_datos.md` |
| 4. Visualización y storytelling | Elegir gráfico correcto, narrar hallazgos | `references/visualizacion.md` |
| 5. Estadística práctica | Confirmar que un hallazgo es real y no ruido | `references/estadistica.md` |

No hace falta pasar por las fases en orden estricto si el usuario ya tiene una pregunta puntual (ej. "¿por qué cayeron las ventas en marzo?"), pero la Fase 0 y la Fase 1 (documentación) siempre van primero, sin importar el pedido.

---

## Fase 0 — Entender el negocio (obligatoria, siempre primero)

1. **Inspeccioná la estructura antes de preguntar nada.** Cargá el CSV/tabla/query y mirá columnas, tipos de dato, cantidad de filas, valores únicos y una muestra de filas. Si tenés Python disponible, podés correr `scripts/generar_diccionario_base.py` sobre el archivo para obtener un esqueleto técnico automático (nombre de columna, tipo, % de nulos, cardinalidad, ejemplos de valores) — esto te ahorra hacerlo a mano y te da una base para saber qué preguntar.

2. **Identificá qué es ambiguo.** No preguntes por todo — muchas columnas se explican solas (`fecha_nacimiento`, `precio_unitario`). Enfocá las preguntas en lo que de verdad puede cambiar una conclusión:
   - Columnas con nombres poco claros, códigos o abreviaturas (`status`, `tipo_2`, `flag_x`)
   - Reglas de negocio detrás de una métrica (¿qué hace que un cliente sea "activo"? ¿el revenue incluye impuestos?)
   - Granularidad de las filas (¿cada fila es una transacción, un cliente, un día?)
   - Convenciones de fecha/hora/moneda/unidades
   - Qué decisión va a tomar el usuario con este análisis (esto determina qué es relevante y qué no)
   - Valores que se repiten sospechosamente (0, -1, 9999, "N/A", vacíos) — ¿son nulos disfrazados o tienen significado?

3. **Hacé todas las preguntas juntas, no de a una.** Juntá la lista completa de dudas y presentala de una vez (podés usar el tool de preguntas con opciones si el chat lo soporta, o una lista simple). Esto respeta el tiempo del usuario en vez de generar un ida-y-vuelta interminable.

4. **Repreguntá si hace falta.** Si una respuesta abre una duda nueva, seguí preguntando. El objetivo es llegar a un punto donde puedas explicar en tus propias palabras qué representa cada columna relevante y qué pregunta de negocio estás respondiendo, sin ninguna suposición sin confirmar.

5. **Documentá las respuestas apenas las recibís**, en la sección "Contexto de negocio" de `documentacion_analisis.md` — no esperes a terminar el análisis para volcarlas.

Si el usuario no tiene manera de responder (por ejemplo, subió un dataset público sin contexto), decilo explícitamente, dejá constancia en el documento de qué supuestos estás haciendo en su lugar, y marcá esas conclusiones como condicionadas a esos supuestos.

## Fase 1 — Diccionario de datos y limpieza

- Completá la tabla de diccionario de datos en `documentacion_analisis.md`: columna, tipo, **significado de negocio** (lo que aprendiste en la Fase 0), formato/valores posibles, notas.
- Limpiá los datos con pandas (u otra librería según el lenguaje que use el usuario): nulos, duplicados, formatos inconsistentes, tipos de dato incorrectos, outliers evidentes.
- Cada decisión de limpieza que tomes (ej. "se eliminaron 12 filas duplicadas", "los nulos de `email` se dejaron como están porque son clientes sin registro, no un error") se documenta en la sección "Decisiones de limpieza" **con el motivo**, no solo el qué. Esto es lo que le va a permitir a alguien confiar en el análisis sin tener que auditarlo línea por línea.

## Fase 2 — Análisis exploratorio (EDA)

Ver `references/eda.md` para el checklist completo (distribuciones, segmentación, tendencias, outliers, correlaciones).

Regla clave: **cada vez que encuentres algo que valga la pena** —una tendencia, una anomalía, una diferencia entre segmentos, algo que no cuadra— anotalo de inmediato en la sección "Hallazgos y conclusiones" del documento. No confíes en recordarlo todo al final; el valor de un análisis se pierde si los hallazgos intermedios no quedan registrados.

## Fase 3 — SQL y obtención de datos externos

Ver `references/sql_y_datos.md` para patrones de consultas (desde `SELECT`/`WHERE` hasta window functions), y guía de APIs/JSON/web scraping cuando los datos no vienen de un CSV o base de datos tradicional.

## Fase 4 — Visualización y storytelling

Ver `references/visualizacion.md` para la guía de qué gráfico usar según el tipo de pregunta, y la estructura narrativa (pregunta → contexto → hallazgo → por qué importa → recomendación) para presentar resultados a una audiencia no técnica.

## Fase 5 — Estadística práctica

Ver `references/estadistica.md`. Antes de afirmar que algo "cambió" o que un segmento "es distinto" de otro, verificá si la diferencia es estadísticamente significativa o si podría ser ruido — sobre todo con muestras chicas. No hace falta cálculo avanzado, pero sí el criterio para no confundir una fluctuación con una tendencia real.

## IA como copiloto, no como piloto automático

Está bien usar IA (incluida vos mismo, Claude) para acelerar la escritura de queries SQL o la limpieza de datos, pero cada resultado generado con ayuda de IA se verifica contra los datos crudos antes de presentarlo como conclusión — especialmente números que van a sustentar una decisión. Si algo no cierra (una suma que no da, un porcentaje imposible), es señal de una alucinación o un error de lógica, no de un dato raro del negocio.

## Al cerrar el análisis

1. Revisá que `documentacion_analisis.md` esté completo: contexto de negocio, diccionario de datos, decisiones de limpieza, hallazgos, recomendaciones.
2. Si el usuario pidió Excel, generá también la versión `.xlsx` con la skill `xlsx`.
3. Presentá en el chat un resumen ejecutivo corto: pregunta de negocio → hallazgos principales → recomendaciones accionables. El documento completo queda como respaldo, no hace falta repetirlo todo en el chat.
4. Si el usuario está armando un portafolio o quiere mostrar el trabajo a reclutadores, el mismo `documentacion_analisis.md` funciona como base de un caso de estudio — sugeríselo si aplica, pero no lo fuerces si no lo pidió.
