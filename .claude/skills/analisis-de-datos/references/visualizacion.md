# Visualización y storytelling

## Qué gráfico usar según la pregunta

| Qué querés mostrar | Gráfico recomendado | Evitar |
|---|---|---|
| Comparar categorías | Barras | Pie chart con más de 4-5 categorías |
| Tendencia en el tiempo | Línea | Barras si hay muchos puntos temporales |
| Distribución de una variable | Histograma o boxplot | — |
| Relación entre dos variables numéricas | Scatter plot | — |
| Composición (parte del todo) | Barras apiladas o treemap | Pie chart con muchas categorías (es difícil comparar ángulos) |
| Ranking | Barras horizontales ordenadas | — |
| Comparar distribuciones entre grupos | Boxplots lado a lado, o violin plot | — |

Reglas generales:
- Empezar el eje Y en cero para gráficos de barras (si no, se exagera la diferencia visualmente).
- Máximo 5-7 categorías/series en un mismo gráfico antes de que se vuelva ilegible — agrupar el resto en "otros" si hace falta.
- Etiquetar ejes y unidades siempre. Un gráfico sin unidades obliga al lector a adivinar.
- El color debe significar algo (categoría, grupo) — no usarlo solo de forma decorativa, y evitar rojo/verde juntos como único diferenciador (daltonismo).

## Formato de salida: preferir HTML interactivo cuando se pueda

Para la mayoría de los entregables de este análisis, generar la visualización como un **archivo o artifact HTML** en lugar de una imagen estática, siempre que el contexto lo permita. Un HTML con los gráficos y los datos embebidos tiene ventajas reales sobre una imagen fija:

- Permite explorar (hover para ver valores exactos, zoom, filtrar por categoría) en vez de solo mirar.
- Un solo archivo puede combinar varios gráficos, tablas y el resumen ejecutivo en un mismo lugar — más cómodo de compartir con alguien no técnico que una carpeta de imágenes sueltas.
- Se puede reabrir y reutilizar más adelante sin volver a correr código.

**Cómo generarlo:**
- Si estás en un entorno con capacidad de mostrar visuales interactivos en el chat (artifacts / widgets), usarla directamente para los gráficos exploratorios — es la forma más rápida de iterar con el usuario.
- Para un entregable que el usuario se va a llevar (reporte final, dashboard para compartir), armar un archivo `.html` autocontenido: un solo archivo con el/los gráfico(s) (por ejemplo con Chart.js, Plotly o D3 vía CDN), sin depender de servicios externos ni de que el usuario tenga Power BI/Tableau instalado para verlo. Esto es especialmente útil para el resumen ejecutivo de la Fase de storytelling: un `reporte_resultados.html` con la narrativa (pregunta → hallazgo → recomendación) y los gráficos correspondientes embebidos.
- Reservar las imágenes estáticas (PNG/SVG) para cuando el destino lo exige (un documento Word/PDF, una presentación, un mail donde no se puede embeber HTML) — en esos casos, generar el gráfico primero y exportarlo a imagen para insertarlo.

No forzar HTML donde no aporta: si el usuario solo pidió un número o una tabla chica, no hace falta envolverlo en un archivo interactivo.

## Herramientas de BI

Si el usuario menciona Power BI o Tableau, orientar la recomendación según lo que ya usa el equipo/empresa (evitar sugerir migrar de herramienta sin que lo pida). Ambas comparten los mismos principios de este documento — la diferencia es de tooling, no de criterio analítico.

## Estructura narrativa (storytelling)

Para presentar hallazgos a una audiencia no técnica, seguir esta estructura en vez de mostrar tablas o código:

1. **Pregunta de negocio** — qué se quería averiguar y por qué importa.
2. **Contexto mínimo** — qué datos se usaron, período, alcance (una o dos frases, no el detalle técnico).
3. **Hallazgo principal** — la conclusión más importante primero, en una frase clara, apoyada por un solo gráfico o número si es posible.
4. **Por qué importa** — qué implica este hallazgo para el negocio.
5. **Recomendación accionable** — qué se sugiere hacer con esta información. Un análisis sin una acción sugerida es solo un dato curioso.

Evitar la tentación de mostrar todo el proceso técnico (cada paso de limpieza, cada gráfico exploratorio) a una audiencia de negocio: eso va en `documentacion_analisis.md` como respaldo, no en la presentación final.
