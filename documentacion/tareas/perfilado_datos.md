# Tarea: Perfilado de fuentes RDS (verificado: 2026-11-18)

Archivo: `vistas\App_informe_llenado\perfilado_datos.R`

## Qué hace
Perfila las cuatro fuentes RDS que alimentan el pipeline de la app de llenado. Corre en local, junto al pipeline `limpieza_datos.R`.

## Qué calcula
Por fuente: filas y, por columna, clase, nulos, valores distintos. Para numéricas, mínimo y máximo. Si hay 50 valores distintos o menos, el conteo por valor. Las fechas no se perfilan. Las geometrías solo se marcan.

## Qué muestra (qué deja)
- `documentacion\catalogo\perfil\app_<fuente>_<fecha>.json`, una por fuente.

## Entradas
Las cuatro rutas de `FUENTES` en el script. Son las mismas que lee `limpieza_datos.R`:
- `db\DFR\RDS\dfr_E_DF_POSICIONES_RECORRIDO.rds`
- `db\DFR\RDS\dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds`
- `db\GOL_reportes\historico_llenadoGol.rds`
- `UNA_POR_CIRCUITO\rds\circuitos_periodo.rds`

## Salidas
Los JSON de la carpeta `perfil\`. Se regeneran en cada corrida con la fecha del día.

## Variables usadas
Ver el [catálogo de variables](../catalogo/variables.md) y las [fuentes](../catalogo/fuentes.md).

## Cómo se corre
1. Desde la raíz del proyecto, con `source("vistas/App_informe_llenado/perfilado_datos.R")`.
2. Ejecutar `main()`.

## Estado
Escrito, pero no ejecutado. R no estaba disponible en el entorno donde se preparó. Hay que correrlo una vez y revisar la salida. Es la primera prueba pendiente de esta tarea.

## Pendientes
- Primera ejecución y revisión del JSON generado.
- Decidir si también se perfilan los pins del repo de datos, o solo las fuentes RDS de entrada.
- Si se agrega un sistema de alertas como en Jupyter, definir la lista de valores esperados por columna.
