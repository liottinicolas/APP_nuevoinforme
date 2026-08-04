# Estadística práctica para análisis de datos

No hace falta cálculo avanzado. Con estadística descriptiva y algunas pruebas básicas alcanza para no confundir una fluctuación con una tendencia real.

## Antes de afirmar que algo "cambió" o "es distinto"

Preguntarse:
- **¿El tamaño de muestra alcanza?** Una diferencia entre 5 clientes y 8 clientes no es evidencia de nada. Cuanto más chica la muestra, más cautela.
- **¿La diferencia es grande en términos prácticos, no solo estadísticos?** Un resultado puede ser "estadísticamente significativo" pero irrelevante para el negocio (ej. 0.1% de diferencia en una muestra enorme). Reportar siempre la magnitud, no solo si "es significativo".
- **¿Podría explicarse por variación normal?** Comparar contra la variabilidad histórica de la métrica, no solo contra un único período anterior.

## Pruebas de hipótesis, en criollo

- **Test de proporciones / chi-cuadrado**: para comparar tasas o porcentajes entre grupos (ej. tasa de conversión A vs B).
- **Test t / Mann-Whitney**: para comparar el promedio de una métrica numérica entre dos grupos (ej. ticket promedio entre dos campañas).
- **p-valor**: la probabilidad de observar una diferencia así de grande (o más) si en realidad no hubiera diferencia real. Un umbral común es 0.05, pero no es una ley física — es una convención. Comunicarlo como "es poco probable que esta diferencia sea azar" en vez de citar el número crudo a una audiencia no técnica.

## Errores comunes a evitar

- **Correlación no es causalidad.** Que dos métricas se muevan juntas no prueba que una cause la otra — puede haber una tercera variable detrás, o pura coincidencia.
- **Comparaciones múltiples.** Si probás 20 segmentos buscando "cuál es distinto", es esperable que alguno parezca significativo solo por azar. Cuantas más comparaciones se hacen, más cautela hace falta con cualquier resultado individual "positivo".
- **Sesgo de selección.** Si los datos no representan bien a la población que se quiere analizar (ej. solo clientes que respondieron una encuesta), las conclusiones no se pueden generalizar sin aclarar esa limitación.
- **Ruido disfrazado de tendencia.** Una serie de 3-4 puntos que sube no es necesariamente una tendencia — comparar contra la volatilidad histórica antes de llamarla así.

## Cuándo no hace falta ningún test formal

Si la diferencia es obvia y grande (una métrica se triplicó, una categoría representa el 80% del total), no hace falta un test estadístico para justificarlo — el criterio es no aplicar rigor estadístico donde no aporta, ni saltearlo donde sí hace falta (diferencias chicas, muestras chicas, decisiones de alto impacto).
