# Documentación de análisis: Servicios de recolección por día y turno — B_101–103, CH y C

_Última actualización: 2026-10-14 (cifras alineadas con el documento para decisores)_

## 1. Contexto de negocio

**Objetivo del análisis:** dimensionar cuántos servicios (viajes) se usan hoy por día y turno en los circuitos
B_101–103, CH y C_101–109 (C_110–C_116 excluidos), para estimar personas, camiones y viajes necesarios si en el futuro otros municipios dejan
este tipo de recolección y ese personal pasa a cubrir o aumentar estos servicios.

**Preguntas de negocio a responder:**
- ¿Cuántos servicios se usan por día y por turno (y por día de la semana)?
- ¿Qué % de cada viaje / circuito se completa y cuántos contenedores se levantan?
- ¿Cuántos recursos (camiones, personas, viajes) harían falta para cubrir el 100 % / aumentar el servicio?

**Entrevista realizada (preguntas y respuestas):**

| Pregunta | Respuesta | Quién la respondió |
|---|---|---|
| ¿`historico_posiciones` es `historico_ubicaciones.rds`? | Sí | Usuario |
| Período de análisis | Últimos 12 meses | Usuario |
| ¿Contenedores inactivos? | Solo activos | Usuario |
| ¿Nocturno se pasa al día siguiente? | No, fecha GOL tal cual | Usuario |
| ¿% completo por viaje o por circuito? | Ambos niveles | Usuario |
| ¿Viajes que mezclan circuitos? | Solo filas de los circuitos seleccionados | Usuario |
| ¿Excluir levantes puntuales con grúa? | Sí, detectados por posiciones dispersas | Usuario |
| Escenario a estimar | Municipios A, D, E, F, G dejan este sistema; su personal y camiones se reasignan a B_101–103, CH y C_101–109 | Usuario |
| Dotación por servicio | Se cuenta por camión; generalmente chofer + peón (≈ 2 personas por camión-turno) | Usuario |
| ¿1 viaje = 1 camión-turno? | Sí | Usuario |
| Metas de "cubrir/aumentar" | (1) completar el 100 % de lo listado en los viajes; (2) más frecuencia (5 o 6 por semana) | Usuario |
| ¿Incluir el sábado nocturno? | No: los sábados no hay turno nocturno; se excluye de todo el análisis y de todas las cuentas (2026-10-14) | Usuario |
| ¿Cuántos camiones hay disponibles? | Los camiones al inicio de cada turno según la planilla de operaciones "Información" (hoja Disponibilidad), media de los últimos 3 meses por turno y día de semana; sin reserva extra porque los rotos ya vienen descontados (2026-10-15). Reemplaza la flota fija (30, luego 27) con 10 % de reserva | Usuario |
| ¿Qué circuitos de C se excluyen? | C_110 a C_116 (2026-10-15). Quedan C_101–C_109: 35 circuitos en total. Siguen siendo de la IM, así que sus camiones cuentan en el uso de la flota. Otros circuitos a los que se les saca una parte no se ajustan por ahora | Usuario |

**Supuestos asumidos sin confirmar:**
- La oferta liberable es solo la de Oficina IM en A, D, E, F, G; el Fideicomiso del municipio B (B_01–07) no entra en el escenario — impacto si es incorrecto: la oferta estaría subestimada.
- Un camión liberado puede hacer cualquier turno (no se modela la restricción de turno del personal) — impacto: si el personal diurno no puede pasar a nocturno, la oferta útil es menor; por eso se muestra oferta y demanda por turno.

## 2. Diccionario de datos

Fuente principal: `db/GOL_reportes/historico_llenadoGol.rds` (una fila = un contenedor listado en un viaje GOL).

| Columna | Tipo de dato | Significado de negocio | Valores posibles / formato | Notas |
|---|---|---|---|---|
| Fecha | Date | Fecha del viaje en GOL | 2025-03-01 → 2026-10-13 | Nocturno no se desplaza |
| Circuito | chr | Circuito completo | `<MUN>_DU_RM_CL_<nnn>` | Todos los municipios usan el mismo código de tipo `DU_RM_CL` |
| Circuito_corto | chr | Municipio + número | `CH_101`, `B_102`… | |
| Posicion | num | Orden del contenedor en el recorrido | 1..n | Base de la detección de grúa |
| Levantado | chr | Resultado de la visita | S / N / NA (no visitado) | |
| Turno_levantado | factor | Turno del viaje | Matutino / Vespertino / Nocturno | Un viaje = un turno |
| Fecha_hora_pasaje | POSIXct | Hora en que se pasó por el contenedor | | NA = no se fue |
| Incidencia | chr | Motivo de no levante | ~20 valores | Motivos de grúa: ver `MOTIVOS_GRUA` |
| contenedor_activo | chr | Contenedor activo | S / N | Se excluyen N |
| Id_viaje_GOL | num | Identificador de viaje = **servicio** | | No hay matrícula ni dotación |
| gid | chr | Id del contenedor | | |
| Municipio, Oficina | chr | Municipio y operador | IM / Fideicomiso | B_101–103 son IM |

Fuente secundaria: `db/10393_ubicaciones/historico_ubicaciones.rds` (posiciones diarias por circuito; `Estado` Mantenimiento / Sin instalar se excluyen).

## 3. Decisiones de limpieza

| Decisión | Motivo | Filas/valores afectados |
|---|---|---|
| Período 2025-10-15 → 2026-10-14 | Pedido del usuario (12 meses) | universo 500.403 filas (35 circuitos) |
| Excluir C_110 a C_116 | Decisión del usuario (2026-10-15); siguen contando en el uso de la flota | 7 circuitos |
| Excluir contenedores inactivos | Pedido del usuario | 4.109 filas |
| Excluir viajes de grúa probables (reglas A/B) | Son levantes puntuales, no servicios de circuito | 207 viajes, 2.078 filas |
| Excluir el sábado nocturno | No hay turno nocturno los sábados (decisión del usuario); no se cuenta ni como turno con 0 | 18 viajes de los circuitos analizados (184 en todo el sistema) |
| Contar como visitado si hay hora de pasaje aunque `Levantado` sea NA | Se fue al contenedor | 41 filas |

## 4. Hallazgos y conclusiones

- **Los circuitos seleccionados se trabajan casi solo de noche** — viajes por día con servicio: Nocturno 19,1 vs Matutino 1,8 y Vespertino 1,6. En los otros municipios dominan Matutino (26,2) y Vespertino (12,9), con 9,0 nocturnos. — Por qué importa: el personal que se libere viene mayormente de turnos diurnos; cubrir estos circuitos implica pasarlos a nocturno o reprogramar circuitos a turno diurno.
- **Los sábados no hay turno nocturno en todo el sistema** — solo 184 viajes registrados así en 12 meses (18 en los circuitos analizados), que se excluyen. Por eso 6 servicios por semana es el máximo nocturno por circuito.
- **La oferta liberable es diurna y la demanda es nocturna** — A/D/E/F/G usa en promedio por día hábil unos 22 camiones matutinos, 13 vespertinos y 6 nocturnos; los circuitos analizados (B_101–103, CH y C_101–109) usan ~14 nocturnos y menos de 1 diurno, y C_110–C_116 otros ~3 nocturnos. — Por qué importa: reasignar implica pasar personal a turno nocturno o mover circuitos analizados a turno diurno.
- **Frecuencia actual de los circuitos analizados**: cada circuito tiene servicio entre 3,4 y 5,9 días por semana (mediana 4,5).
- **526 viajes (2,4 %) mezclan circuitos de demanda y de oferta**; para contar camiones se asignan al bloque con más contenedores.
- **En C y B_10x los viajes muchas veces traen solo una parte del circuito** (C 41 %, B_10x 27 %, CH 4 % de circuito-día-turno nocturnos; C sigue en 41 % sin C_110–C_116, sin viajes de grúa; viaje parcial = más de 20 contenedores menos que el circuito según posiciones). — El "100 % completo" sobre lo listado no es cobertura total del circuito.
- **Viajes de grúa**: 67 % de sus contenedores tenían motivo de grúa en la visita previa vs 2,4 % en el resto; se excluyen.

### Capacidad (camiones-turno; 1 viaje = 1 camión-turno; sin viajes de grúa)

> **Corrección de enfoque (2026-10-14):** los camiones-turno de A/D/E/F/G NO son camiones adicionales: los camiones son compartidos por todos los municipios y turnos (cada camión hace ~2 turnos/día). Desde el 2026-10-15 los disponibles salen de la planilla de operaciones: camiones al inicio de cada turno, ~26 de noche, ~23 de mañana y ~21 de tarde (días hábiles, media de los últimos 3 meses). Si A/D/E/F/G dejan el sistema se liberan turnos de esos mismos camiones (~6 por noche, ~22 de mañana, ~20 de tarde) y personal (~513 personas-turno/semana). Las opciones se calculan dentro de la flota (`tabla_opciones_flota`, hoja `Opciones` del Excel de flota). Las cifras de "oferta liberable" de abajo se conservan solo como uso de camiones-turno de A/D/E/F/G.

- **Demanda actual de los circuitos analizados (sin C_110–C_116): ~94 camiones-turno por semana** (93,7), 88,7 de ellos nocturnos. — Verificado: la suma del perfil semanal coincide con el conteo crudo de viajes / semanas. Con C_110–C_116 eran 113,7: esos 7 circuitos usan ~20 camiones-turno por semana, que siguen contando en el uso de la flota.
- **Oferta liberable A/D/E/F/G: ~257 camiones-turno por semana** (≈ 513 personas-turno con chofer + peón): 145 matutinos, 78 vespertinos, 34 nocturnos. Por día hábil: ~22 matutinos, ~13 vespertinos, ~6 nocturnos.
- **Meta "completar lo listado": +17 camiones-turno/semana** (antes +25), casi todo nocturno (15,1; ~2,5 por noche).
- **Meta frecuencia por circuito** (mediana hoy 4,3 C, 4,5 B_10x, 5,1 CH días/semana): llevar los 23 circuitos que no llegan a 5/semana = +12,6 camiones-turno/semana; los 35 a 6/semana (máximo nocturno) = +29,7. C y CH aportan casi lo mismo (13,1 y 13,6 de los 29,7): C tiene menos frecuencia y más camiones por servicio (0,86 vs 0,51 en CH).
- **Opciones dentro de la flota (reserva 10 %, 2 turnos/camión), camiones-turno extra por semana noche + mañana + tarde**: completar lo asignado hoy 2 + 9 + 13 = 24, sin A/D/E/F/G 15 + 1 + 1 = 17; mínimo 5/semana hoy 2 + 9 + 7 = 18, sin A/D/E/F/G 13; mínimo 6/semana hoy 2 + 9 + 34 = 45, sin A/D/E/F/G 30 (todo de noche); completar + 6/semana hoy 56 y **cubre el 79 %**, sin A/D/E/F/G 36 + 14 + 1 = 51 (entra completo). Con los camiones al inicio de la planilla, hoy la noche admite ~2 camiones-turno extra por semana, la mañana ~9 y la tarde ~45: casi todo el aumento va de tarde.

### Camiones disponibles (planilla de operaciones) y turnos diurnos

- **Camiones disponibles = camiones al inicio de cada turno (planilla de operaciones, 2026-10-15)**: media de los últimos 3 meses en días hábiles: 26 de noche, 23 de mañana y 21 de tarde. Antes se suponía una flota fija (30, luego 27) con 10 % de reserva = 24 en todos los turnos; la planilla muestra que de día hay menos camiones y que los rotos ya vienen descontados. Hay menos camiones que hace un año: el promedio al inicio pasó de ~30 (ago–sep 2025) a 23–25 (jun–sep 2026).
- **La planilla valida a GOL**: camiones usados (planilla) vs camiones-turno de GOL por turno, misma fecha: diferencia media menor a 1 camión en todos los turnos, p90 iguales ±1 y correlación diaria 0,93 (0,67 corriendo un día). Confirma 1 viaje = 1 camión-turno y que la fecha GOL del nocturno es la del turno. Por día hábil: 58 camiones-turno en la planilla y 59 en GOL, con 21–27 camiones al inicio de cada turno → ~2 turnos por camión.
- **Lugar libre hoy (días hábiles, contra el uso p90)**: noche 0, mañana 0, tarde ~4 camiones por día; en la semana entran ~2 extra de noche y ~9 de mañana (sobre todo fines de semana).
- **Congestión diurna medida (mismo circuito, día vs noche, Wilcoxon pareado p < 0,001)**: un camión matutino visita el 70 % de lo que visita uno nocturno (18,0 vs 23,1 contenedores/hora, 60 vs 95 por turno) y uno vespertino el 62 % (14,4/hora, 53 por turno). El vespertino (15:05–18:40) coincide con la salida del trabajo.
- **Frecuencia con los camiones de la planilla, 2 turnos por camión**: hoy, mínimo 5/semana (23 circuitos) = 2 nocturnos + 9 matutinos + 7 vespertinos = 18 camiones-turno/semana; mínimo 6/semana (35 circuitos) = 2 + 9 + 34 = 45 (vs 30 si todo fuera nocturno: +51 % por el rendimiento diurno). Si A/D/E/F/G dejan el sistema, 5/semana y 6/semana entran enteros de noche (13 y 30).
- Si un camión solo pudiera hacer 1 turno por día, hoy se cubriría solo el 28 % de la meta de 6/semana (66 % de la de 5/semana); no es la operación actual.

## 5. Recomendaciones

- **Decidir primero el turno**: la noche está llena (26 camiones usados en 9 de cada 10 noches, con ~26 al inicio); el aumento va de tarde salvo que A/D/E/F/G dejen el sistema y liberen ~6 camiones por noche.
- **Prioridad 1 – completar lo listado (~2,5 camiones por noche, 17 por semana)**: es el aumento más barato y no cambia la programación.
- **Prioridad 2 – frecuencia mínima 5/semana en los 23 circuitos que no la alcanzan (~13 camiones-turno/semana en equivalente nocturno)**: con los camiones de hoy entra casi todo de día (2 nocturnos + 9 matutinos + 7 vespertinos), y de tarde el rendimiento es el más bajo (62 % del nocturno).
- **Prioridad 3 – subir frecuencia en C**: es el municipio con menor frecuencia y mayor cobertura parcial de circuito; C_110–C_116 ya quedan fuera; falta ajustar los circuitos a los que se les saca una parte.
- **Dimensionar con p90, no con la media**, y sumar una reserva por ausentismo y flota en mantenimiento (no está en los datos).
- **Validar con operaciones** antes de decidir: cantidad de camiones físicos (sin matrícula solo se ven camiones-turno) y si los circuitos C/B parciales son levante selectivo planificado.

## 6. Fuentes y metodología

- **Origen de los datos:** históricos RDS del proyecto (GOL reportes diarios y 10393 ubicaciones) y la planilla de operaciones "Información", hoja Disponibilidad (camiones al inicio y usados por turno), en `db/disponibilidad/disponibilidad_camiones.csv`.
- **Período cubierto:** 2025-10-15 → 2026-10-14 (camiones disponibles: últimos 3 meses de la planilla).
- **Herramientas usadas:** R 4.6.1 + data.table + openxlsx; scripts en `scripts/analisis_servicios/`:
  - `analisis_servicios_viajes.R` → `salidas/analisis_servicios_viajes_<desde>_<hasta>.xlsx` (servicios, % completo, levantados; hojas `Calidad_servicio` y `Validacion_grua` = tablas del documento para decisores)
  - `analisis_capacidad.R` → `salidas/capacidad_servicios_<desde>_<hasta>.xlsx` (oferta vs demanda, metas; hojas `Resumen_semanal` y `Opciones` = tablas del documento para decisores)
  - `analisis_flota.R` → `salidas/flota_frecuencia_<desde>_<hasta>.xlsx` (flota, productividad por turno, escenarios de frecuencia, camiones disponibles y validación con la planilla; parámetros MESES_DISPONIBILIDAD, RESERVAS, TURNOS_POR_CAMION, FRECUENCIAS_OBJETIVO)
  - `verificar_analisis.R` → comprobaciones contra datos crudos (todas pasan)
- **Limitaciones conocidas:** sin matrícula: se cuentan camiones-turno, no camiones físicos (validados contra los camiones usados de la planilla de operaciones); dotación supuesta 2 personas por camión; detección de grúa heurística; la productividad (contenedores por camión) se asume igual a la actual; no se modela ausentismo ni flota en mantenimiento.
