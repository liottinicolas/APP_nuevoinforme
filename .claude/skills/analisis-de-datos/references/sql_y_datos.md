# SQL y obtención de datos

## SQL — de básico a avanzado

**Consultas básicas**
```sql
SELECT columna1, columna2
FROM tabla
WHERE condicion
ORDER BY columna1 DESC
LIMIT 100;
```

**Agregaciones**
```sql
SELECT categoria, COUNT(*) AS cantidad, SUM(monto) AS total
FROM ventas
GROUP BY categoria
HAVING COUNT(*) > 10;
```
`WHERE` filtra filas antes de agrupar; `HAVING` filtra después de agrupar.

**JOINs**
- `INNER JOIN`: solo filas que matchean en ambas tablas.
- `LEFT JOIN`: todas las filas de la izquierda, con NULL donde no hay match a la derecha — útil para no perder registros (ej. clientes sin compras).
- `FULL OUTER JOIN`: todo de ambos lados.
Verificar siempre la cardinalidad esperada del join (1:1, 1:N, N:N) — un join mal pensado puede duplicar filas silenciosamente e inflar sumas y conteos.

**Subconsultas**
```sql
SELECT *
FROM clientes
WHERE id IN (SELECT cliente_id FROM ventas WHERE monto > 1000);
```

**Funciones de ventana (window functions)** — el salto de nivel intermedio a avanzado:
```sql
SELECT
  cliente_id,
  fecha,
  monto,
  ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY fecha) AS nro_compra,
  RANK() OVER (ORDER BY monto DESC) AS ranking_monto,
  SUM(monto) OVER (PARTITION BY cliente_id ORDER BY fecha) AS acumulado,
  LAG(monto) OVER (PARTITION BY cliente_id ORDER BY fecha) AS monto_anterior
FROM ventas;
```
Útiles para: rankings, totales acumulados, comparar una fila con la anterior/siguiente, sin colapsar el detalle de filas como haría un `GROUP BY`.

## Obtención de datos externos

**APIs y JSON**
- Revisar la documentación de la API para entender autenticación (API key, OAuth), límites de rate y paginación.
- Un JSON anidado casi siempre necesita "aplanarse" (normalizar) antes de tratarlo como tabla — en Python, `pandas.json_normalize` es el punto de partida habitual.

**Web scraping básico**
- Preferir siempre una API oficial o un export de datos si existe, antes que scrapear.
- Revisar `robots.txt` y los términos de servicio del sitio antes de scrapear.
- Guardar el HTML crudo o la respuesta cruda cuando sea posible, para poder re-procesar sin volver a pedirle datos al sitio.

## Control de versiones
- Un análisis serio se versiona: usar Git para el código de limpieza/análisis (no necesariamente para los datos crudos, que pueden ser pesados o sensibles).
- Un repo con notebooks o scripts organizados, un README que explique el objetivo del análisis, y commits con mensajes claros, es lo que convierte un análisis puntual en algo mostrable en un portafolio.
