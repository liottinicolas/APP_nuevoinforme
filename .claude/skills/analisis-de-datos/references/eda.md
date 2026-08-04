# Análisis Exploratorio de Datos (EDA) — checklist

Usar esta lista como guía, no como trámite: el objetivo es encontrar lo que responde la pregunta de negocio, no correr las 10 celdas por rutina.

## 1. Panorama general
- Forma del dataset (filas, columnas)
- Tipos de dato por columna — ¿coinciden con lo esperado? (una fecha guardada como texto, un ID numérico que en realidad es categórico)
- Mapa de nulos: qué columnas tienen faltantes y en qué proporción. Un patrón de nulos (ej. siempre faltan juntos `telefono` y `direccion`) suele significar algo, no es aleatorio.
- Duplicados: filas completas repetidas, o duplicados por clave de negocio (mismo cliente, mismo pedido).

## 2. Variables numéricas
- Media, mediana, desvío estándar, mínimo, máximo, percentiles (25/50/75).
- Diferencia grande entre media y mediana → posible asimetría o outliers.
- Histograma o boxplot para ver la forma de la distribución.
- Outliers: definirlos con criterio (IQR, z-score, o conocimiento de negocio) antes de decidir si se excluyen o no. Un outlier no siempre es un error — a veces es el dato más interesante.

## 3. Variables categóricas
- Conteo de valores únicos y su frecuencia.
- Categorías con muy pocas observaciones (¿agrupar en "otros" o dejarlas?).
- Inconsistencias de formato: "Buenos Aires" vs "buenos aires" vs "CABA" — estandarizar antes de agrupar.

## 4. Relaciones entre variables
- Comparar segmentos (por categoría, por período, por región) usando la misma métrica — ¿hay diferencias que valen la pena investigar?
- Matriz de correlación para variables numéricas — recordar que correlación no implica causalidad (ver `estadistica.md`).
- Cruces de dos categóricas (tablas de contingencia) cuando la pregunta de negocio lo amerita.

## 5. Series de tiempo (si hay columna de fecha)
- Tendencia general a lo largo del tiempo.
- Estacionalidad (¿se repite un patrón semanal, mensual?).
- Quiebres o cambios abruptos — marcarlos y, si es posible, cruzarlos con eventos conocidos del negocio (campaña, cambio de precio, feriado).

## 6. Registrar hallazgos en el momento
Cada punto de esta lista que arroje algo interesante (no solo "todo normal") se anota de inmediato en `documentacion_analisis.md`, sección "Hallazgos y conclusiones", con:
- Qué se encontró
- Cómo se llegó a esa conclusión (qué se calculó o graficó)
- Por qué le importaría al negocio
