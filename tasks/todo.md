# Tareas: Análisis de servicios por día y turno (B_101–103, CH, C)

Ver definiciones en `tasks/plan.md`. Comando R: `C:/Users/im4445285/AppData/Local/Programs/R/R-4.6.1/bin/Rscript.exe` desde la raíz.

## Tarea 1: Cargar y preparar universo
**Descripción:** Leer `historico_llenadoGol.rds`, filtrar B_101/102/103 + Municipio CH + Municipio C, agregar `grupo`, `activo`, `visitado`, `levantado`. Parámetros de fecha desde/hasta (default: todo).

**Criterios de aceptación:**
- [x] `preparar_universo()` devuelve solo los 35 circuitos esperados (sin C_110–C_116) con columnas `grupo`, `visitado`, `levantado`
- [x] Conteos por circuito coinciden con el perfilado (ej. B_101 = 33.338 filas sin filtrar inactivos)
- [x] Se informa en consola cuántas filas inactivas se excluyen y cuántas tienen pasaje sin `Levantado`

**Verificación:**
- [x] `verificar_analisis.R` pasa los asserts de la tarea 1

**Dependencias:** Ninguna
**Archivos:** `scripts/analisis_servicios/analisis_servicios_funciones.R`, `scripts/analisis_servicios/verificar_analisis.R`
**Tamaño:** S

## Tarea 2: Tabla por viaje (servicio)
**Descripción:** Una fila por `Id_viaje_GOL`: Fecha, Turno, grupo(s), circuitos (lista), n_circuitos, total contenedores, visitados, levantados, no levantados, % completo, % levantado, n circuitos sin ninguna visita.

**Criterios de aceptación:**
- [x] Viaje 44882 → 91 contenedores (CH_115 pos 1–50 + CH_114 entero sin visitar), 28 visitados, 31 %
- [x] Viaje 44914 → 22 contenedores, 22 visitados, 100 %
- [x] Una sola fila por viaje; sin viajes con Fecha/Turno duplicados

**Verificación:**
- [x] Asserts en `verificar_analisis.R`

**Dependencias:** Tarea 1
**Archivos:** `analisis_servicios_viajes.R`, `verificar_analisis.R`
**Tamaño:** S

## Tarea 3: Tabla por circuito-día-turno
**Descripción:** Unir los viajes de un mismo circuito/Fecha/Turno por gid único: viajes que lo atendieron, gids listados, visitados, levantados, % completo del circuito.

**Criterios de aceptación:**
- [x] El circuito/día/turno de 44882+44914 → 2 viajes, 50 gids, 50 visitados, 100 %
- [x] gid visitado en cualquier viaje cuenta una sola vez

**Verificación:**
- [x] Asserts en `verificar_analisis.R`

**Dependencias:** Tarea 1
**Archivos:** `analisis_servicios_viajes.R`, `verificar_analisis.R`
**Tamaño:** S

## Checkpoint 1 (después de Tareas 1–3)
- [x] `verificar_analisis.R` pasa completo
- [ ] Revisar con el usuario 3–4 viajes reales elegidos por él

## Tarea 4: Resumen por día y turno
**Descripción:** Por Fecha × Turno (y por grupo): n servicios, total contenedores, visitados, levantados, % completo ponderado y promedio por viaje, promedio de levantados por viaje, n circuitos atendidos y % circuitos completos.

**Criterios de aceptación:**
- [x] Σ servicios del resumen = n viajes de la tabla de Tarea 2 (sin contar dos veces viajes mixtos entre grupos en el total)
- [x] Σ levantados del resumen = Σ levantados de la tabla por viaje
- [x] Incluye columna n_viajes junto a cada promedio

**Verificación:**
- [x] Asserts de cuadre en `verificar_analisis.R`

**Dependencias:** Tareas 2, 3
**Archivos:** `analisis_servicios_viajes.R`, `verificar_analisis.R`
**Tamaño:** S

## Tarea 5: Cruce con historico_ubicaciones (posiciones)
**Descripción:** (Requiere confirmar que es el archivo correcto.) Tamaño del circuito por Fecha según posiciones (excluyendo Estado Mantenimiento/Sin instalar) vs gids listados en GOL; % completo alternativo sobre el tamaño real del circuito.

**Criterios de aceptación:**
- [x] Columna `contenedores_segun_posiciones` y `dif_vs_gol` en la tabla por circuito-día-turno
- [x] Se informa % de circuito-días sin match en posiciones

**Verificación:**
- [x] Manual: B_101 en 2026-10-13 → 109 en ambas fuentes (111 posiciones − 2 en Mantenimiento)

**Dependencias:** Tarea 3
**Archivos:** `analisis_servicios_viajes.R`
**Tamaño:** S

## Tarea 6: Exportar Excel
**Descripción:** `salidas/analisis_servicios_viajes_<fecha>.xlsx` con hojas: Resumen_dia_turno, Viajes, Circuito_dia_turno, Resumen_por_circuito (promedios del período), Definiciones.

**Criterios de aceptación:**
- [x] Archivo se genera con las 5 hojas, encabezados con filtro y % con formato
- [x] Hoja Definiciones explica cada métrica (texto del plan)
- [x] Resumen_por_circuito permite filtrar por grupo (para revisar los C que no van)

**Verificación:**
- [x] Script completo corre de punta a punta sin errores
- [x] Manual: abrir Excel y comparar totales entre hojas

**Dependencias:** Tareas 4, 5
**Archivos:** `analisis_servicios_viajes.R`
**Tamaño:** S

## Checkpoint final
- [x] Todos los asserts pasan
- [ ] Excel revisado por el usuario
- [x] Circuitos de C excluidos: C_110 a C_116 (2026-10-15)
