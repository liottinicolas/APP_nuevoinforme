# Plan de implementación: Análisis de servicios (viajes) por día y turno — B_101/102/103, CH y C

## Resumen
Calcular, a partir del histórico GOL de llenado, cuántos servicios (`Id_viaje_GOL`) se hicieron por día y turno
en los circuitos B_101, B_102, B_103, todos los de CH y los de C hasta C_109 (C_110–C_116 excluidos el 2026-10-15); qué % de cada viaje se completó
(contenedores a los que **se fue**, levantados o no, sobre el total que tenía el viaje), el total de
contenedores del viaje/circuitos y el promedio de contenedores levantados por día y turno.
Entregable: script R reproducible + Excel.

## Fuentes (verificadas el 2026-10-14)
| Nombre pedido | Archivo real | Filas | Rango |
|---|---|---|---|
| historico_llenado | `db/GOL_reportes/historico_llenadoGol.rds` | 3.635.986 | 2025-03-01 → 2026-10-13 |
| historico_posiciones (confirmado) | `db/10393_ubicaciones/historico_ubicaciones.rds` | 7.108.140 | 2025-02-09 → 2026-10-13 |

Universo seleccionado: 35 circuitos (B_101–103 = Oficina IM, CH_101–123, C_101–109). C_110–C_116 se excluyen (decisión del usuario, 2026-10-15); en `viajes_por_bloque()` quedan como bloque `C_excluido`, que cuenta en el uso de la flota.

Camiones disponibles (2026-10-15): camiones al inicio de cada turno de la planilla de operaciones "Información" (hoja Disponibilidad, `db/disponibilidad/disponibilidad_camiones.csv`), media de los últimos 3 meses por turno y día de semana, sin reserva extra. Reemplaza la flota fija (30, luego 27, con 10 % de reserva). La planilla valida a GOL: camiones usados ≈ camiones-turno de GOL (diferencia media < 1, correlación diaria 0,93).

## Definiciones (decididas con el usuario)
- **Servicio** = `Id_viaje_GOL` distinto. Cada viaje tiene una sola Fecha y un solo Turno (verificado).
- **Fecha/turno** = `Fecha` y `Turno_levantado` **tal cual vienen de GOL** (Nocturno NO se pasa al día siguiente).
- **Viajes mixtos**: el viaje cuenta como servicio, pero totales y % se calculan **solo con las filas de los circuitos seleccionados**.
- **Contenedor del viaje** = fila (gid) listada en el viaje con `contenedor_activo == "S"` (inactivos se excluyen y se informa cuántos).
- **Visitado ("se fue")** = `Levantado %in% c("S","N")` o `Fecha_hora_pasaje` no NA.
- **Levantado** = `Levantado == "S"`.
- **% completo — dos niveles**:
  - *Por viaje*: visitados / contenedores listados en el viaje.
  - *Por circuito-día-turno*: gids únicos visitados en cualquier viaje / gids únicos listados en cualquier viaje
    (no penaliza circuitos repartidos entre camiones; GOL lista filas solapadas, ej. viaje 44882 pos 1–50 y 44914 pos 29–50).
- **Promedio levantados por día-turno** = media de levantados por viaje en ese día-turno (+ total del día-turno).

## Decisiones de arquitectura
- Funciones en `scripts/analisis_servicios/analisis_servicios_funciones.R`; el script principal
  `scripts/analisis_servicios/analisis_servicios_viajes.R` las usa. Funciones puras
  (`preparar_universo()`, `resumir_viajes()`, `resumir_circuitos()`, `resumir_dia_turno()`, `cruzar_posiciones()`),
  para poder verificarlas con casos conocidos.
- `data.table` (ya en renv) por volumen (3,6 M + 7,1 M filas). Excel con `openxlsx` (ya en renv).
- Verificación con `scripts/analisis_servicios/verificar_analisis.R` (asserts `stopifnot` sobre viajes reales conocidos);
  el repo no tiene framework de tests.
- Ejecutar con `Rscript` desde la raíz del proyecto (activa renv): `C:/Users/im4445285/AppData/Local/Programs/R/R-4.6.1/bin/Rscript.exe`.

## Lista de tareas
Detalle de cada tarea en `tasks/todo.md`.

### Fase 1: Base
- [x] Tarea 1: Cargar y preparar universo (filtro + flags)
- [x] Tarea 2: Tabla por viaje (servicio)
- [x] Tarea 3: Tabla por circuito-día-turno (unión de viajes)

### Checkpoint 1
- [ ] Casos conocidos (44882/44914) dan los valores esperados; revisión de definiciones con el usuario

### Fase 2: Indicadores y cruce
- [x] Tarea 4: Resumen por día y turno
- [x] Tarea 5: Cruce con historico_ubicaciones (tamaño de circuito)

### Fase 3: Entrega
- [x] Tarea 6: Exportar Excel + resumen por grupo/circuito

### Checkpoint final
- [ ] Excel abre, totales cuadran entre hojas, usuario revisa circuitos de C

## Riesgos y mitigaciones
| Riesgo | Impacto | Mitigación |
|---|---|---|
| 8,5 % de pares viaje-circuito tienen 0 % visitado (circuito listado en el viaje pero hecho por otro camión o no hecho) | Alto: baja el % por viaje | Por eso se reporta también el % por circuito-día-turno; columna que marca circuitos sin ninguna visita |
| Algunos circuitos de C no aplican | Bajo | Columna `grupo` (B_10x / CH / C) y hoja por circuito para filtrar luego |
| 1.962 filas con pasaje pero sin `Levantado` | Bajo | Se cuentan como visitadas por definición; se informa el conteo |
| Turnos con pocos viajes (ej. 1 Matutino) distorsionan promedios | Bajo | Mostrar n de viajes junto a cada promedio |

## Hallazgo (2026-10-14)
- En C (~41 % de circuito-día-turno nocturnos) y B_10x (~27 %) GOL lista solo una parte del circuito (ej. C_101 11 de 101). El % completo se mide sobre lo listado en el viaje; `pct_completo_sobre_posiciones` da la cobertura del circuito entero.

## Exclusión de viajes de grúa (agregado 2026-10-14)
- Sin matrícula, se marcan por forma del viaje (todos sus circuitos): A) <= 40 contenedores y densidad de posiciones <= 0,5; B) <= 40 contenedores en >= 3 circuitos con <= 2 por circuito.
- Validación: en los marcados, 67 % de los contenedores tenían motivo de grúa en la visita previa (<= 7 días) vs 2,4 % en el resto.
- 213 viajes del universo excluidos (2.740 filas), listados en la hoja `Viajes_grua_excluidos`. Parámetro `EXCLUIR_GRUA` en el script.

## Sábado nocturno (2026-10-14)
- Los sábados no hay turno nocturno: se excluye de todas las cuentas (`es_sabado_noche()`, `grid_dia_turno()`); frecuencia máxima nocturna 6/semana; se quitaron la meta "cubrir el sábado" y la frecuencia 7.

## Preguntas resueltas (2026-10-14)
- `historico_posiciones` = `db/10393_ubicaciones/historico_ubicaciones.rds` ✔
- Período: últimos 12 meses respecto de la última fecha disponible (parametrizable) ✔
- Solo contenedores activos (`contenedor_activo == "S"`) ✔
