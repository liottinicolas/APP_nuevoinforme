# 11 · Análisis de servicios, capacidad y flota (`scripts/analisis_servicios/`)

Tipo: Scripts batch R (`data.table` + `openxlsx`), ejecución manual con `Rscript`

## 📖 ¿Qué hace?

Mide el servicio de recolección de los circuitos **B_101, B_102, B_103, todos los de CH y los de C hasta C_109** (C_110–C_116 se excluyen; sus camiones siguen contando en el uso de la flota) en los últimos 12 meses y estima cuánto se puede ampliar con la flota de la IM:

- cuántos servicios (viajes GOL) se hacen por día y turno, qué % de los contenedores asignados se visita y cuántos se levantan;
- cuántos camiones-turno usan esos circuitos y los municipios A, D, E, F, G;
- cuánto cuesta completar lo asignado o subir la frecuencia a 5 o 6 servicios por semana, **con los camiones disponibles en cada turno según la planilla de operaciones** (camiones al inicio de cada turno, compartidos por todos los municipios), hoy y si A, D, E, F, G dejan el sistema.

Sus resultados alimentan el documento para decisores "Servicios de recolección B/CH/C: uso actual y capacidad" (Claude Docs). El registro técnico del análisis (diccionario de datos, decisiones de limpieza, hallazgos) está en [`scripts/analisis_servicios/documentacion_analisis.md`](../../scripts/analisis_servicios/documentacion_analisis.md); el plan original, en `tasks/plan.md`.

## 📊 Entrada (Input)

| Archivo | Qué es | Lo usa |
|---|---|---|
| `db/GOL_reportes/historico_llenadoGol.rds` | Una fila por contenedor asignado a cada viaje GOL (~3,6 M filas) | Los cuatro scripts |
| `db/10393_ubicaciones/historico_ubicaciones.rds` | Posiciones de contenedores por circuito y día (~7,1 M filas) | `analisis_servicios_viajes.R`, `verificar_analisis.R` |
| `db/disponibilidad/disponibilidad_camiones.csv` | Planilla de operaciones "Información", hoja Disponibilidad: por fecha y turno, camiones al inicio, camiones usados, choferes y auxiliares (desde el 23/07/2025) | `analisis_flota.R`, `verificar_analisis.R` |

Los dos RDS los mantiene `cargaDeDatos.R` (ver [01 · Orquestador](01-orquestador-y-infraestructura.md)). La planilla la baja `descargar_disponibilidad()` al correr `analisis_flota.R` (Google Sheets con acceso por enlace; URL en la variable `URL_DISPONIBILIDAD` del `.Renviron` de la raíz, que no se versiona); si la descarga falla se usa la copia local. Si `curl` falla en Windows con `CRYPT_E_NO_REVOCATION_CHECK`, bajarla con `curl --ssl-no-revoke`. El período analizado termina en la **última fecha disponible** en el histórico de llenado, así que conviene actualizar los históricos antes de correr.

## 🔄 Proceso

### Cómo ejecutar

Desde la **raíz del proyecto** (los scripts usan rutas relativas y así se activa `renv`):

```sh
Rscript scripts/analisis_servicios/analisis_servicios_viajes.R   # servicios y calidad
Rscript scripts/analisis_servicios/analisis_capacidad.R          # uso semanal y metas
Rscript scripts/analisis_servicios/analisis_flota.R              # flota y opciones (tablas del documento)
Rscript scripts/analisis_servicios/verificar_analisis.R          # comprobaciones
```

En esta máquina `Rscript` no está en el PATH; la ruta completa es `C:/Users/im4445285/AppData/Local/Programs/R/R-4.6.1/bin/Rscript.exe`. Los tres scripts de análisis son independientes entre sí (cada uno lee los RDS) y se pueden correr en cualquier orden. Los cuatro juntos tardan unos 6 minutos (medido el 2026-10-14).

### Archivos

```
analisis_servicios_funciones.R   base: universo, viajes, circuitos, día-turno, calidad, grúa, Excel
        ▲            ▲            ▲
capacidad_funciones.R            (usa la base)
        ▲            ▲
flota_funciones.R                (usa base + capacidad)

analisis_servicios_viajes.R  → source(base)
analisis_capacidad.R         → source(base, capacidad)
analisis_flota.R             → source(base, capacidad, flota)
verificar_analisis.R         → source(base, capacidad, flota)
```

Los `*_funciones.R` solo definen funciones y constantes; los scripts `analisis_*.R` son los que leen datos y escriben Excel.

### Pasos comunes a los tres análisis

1. **Período:** `hasta` = última fecha del histórico; `desde` = `hasta` menos `MESES_ATRAS` meses + 1 día.
2. **Viajes de grúa:** `marcar_viajes_grua()` marca levantes puntuales sin matrícula, por la forma del viaje (≤ 40 contenedores y posiciones dispersas, o ≥ 3 circuitos con ≤ 2 contenedores cada uno). Se excluyen de todo.
3. **Universo:** `preparar_universo()` filtra los 35 circuitos (sin `CIRCUITOS_C_EXCLUIDOS` = C_110–C_116), el período, contenedores activos y **descarta el sábado nocturno** (no hay turno). Agrega `grupo` (B_10x / CH / C), `visitado` y `levantado`.

### `analisis_servicios_viajes.R` — servicios y calidad

`resumir_viajes()` (una fila por viaje) → `resumir_circuitos()` (circuito-día-turno, uniendo los viajes que lo atendieron y contando cada contenedor una vez) → `resumir_dia_turno()` → `cruzar_posiciones()` (tamaño del circuito según posiciones) → `resumir_calidad()` y `resumir_validacion_grua()`. Parámetro `EXCLUIR_GRUA` para ver los números con los viajes de grúa incluidos.

### `analisis_capacidad.R` — uso semanal y metas

`viajes_por_bloque()` asigna cada viaje a Demanda (B/CH/C) u Oferta (A/D/E/F/G, Oficina IM) → `camiones_dia_turno()` (serie diaria con ceros) → `perfil_semanal()` (media y p90 por día de semana) → `meta_completar_listado()` y `meta_frecuencia()` → `balance_capacidad()`. Parámetros: `MESES_ATRAS`, `FRECUENCIAS_OBJETIVO`, `PERSONAS_POR_CAMION`.

### `analisis_flota.R` — flota y opciones

`productividad_por_turno()` compara el mismo circuito de día y de noche (rendimiento por turno, Wilcoxon pareado) → `uso_flota_actual()` (camiones a la vez por turno) → `lugar_libre()` (camiones libres por turno, hoy o sin A/D/E/F/G) → `asignar_en_flota()` ubica cada necesidad primero de noche, luego mañana y tarde, dividida por el rendimiento de ese turno → `tabla_opciones_flota()` y `resumen_flota_turno()` (tablas del documento) y `tabla_escenarios_flota()` (todas las combinaciones de supuestos).

| Parámetro | Valor | Significado |
|---|---|---|
| `FLOTA` | `disponibilidad_por_turno(planilla, hasta, MESES_DISPONIBILIDAD)` | Camiones disponibles por turno y día de semana: media de camiones al inicio (planilla) en los turnos que trabajaron. Las funciones aceptan también un número fijo (flota fija) para sensibilidad |
| `MESES_DISPONIBILIDAD` | 3 | Meses de la planilla para la media de camiones al inicio (últimamente hay menos camiones que hace un año) |
| `DESCARGAR_PLANILLA` | `TRUE` | Baja la hoja antes de calcular; si falla, usa la copia local |
| `RESERVA_BASE` / `RESERVAS` | 0 / c(0, 0,10) | Reserva extra de camiones fuera de servicio (tablas del documento / sensibilidad). Con la planilla es 0: los camiones al inicio ya excluyen los rotos |
| `TURNOS_BASE` / `TURNOS_POR_CAMION` | 2 / c(1, 2) | Turnos por camión por día (observado hoy / sensibilidad) |
| `FRECUENCIAS_OBJETIVO` | c(5, 6) | Servicios semanales mínimos; 6 es el máximo nocturno sin sábado |
| `PERSONAS_POR_CAMION` | 2 | Chofer + peón |

### `verificar_analisis.R` — comprobaciones

No es un framework de tests: son `stopifnot()` contra los datos crudos y casos conocidos (por ejemplo, el circuito CH_115 del 10/02/2026 repartido entre los viajes 44882 y 44914). Imprime `OK <bloque>` por cada grupo y termina con `Verificación completa: todos los asserts pasaron`. Si un `stopifnot` falla, el script se corta y muestra la condición que no se cumplió. **Correrlo después de cualquier cambio en las funciones.**

## 📤 Salida (Output)

Todos en `salidas/`, con el período en el nombre (`<desde>_<hasta>`); cada ejecución sobrescribe el archivo del mismo período.

| Script | Archivo | Hojas principales | Duración medida |
|---|---|---|---|
| `analisis_servicios_viajes.R` | `analisis_servicios_viajes_<desde>_<hasta>.xlsx` | `Calidad_servicio`, `Resumen_dia_turno`, `Viajes`, `Circuito_dia_turno`, `Resumen_por_circuito`, `Viajes_grua_excluidos`, `Validacion_grua`, `Definiciones` | ~1,5 min |
| `analisis_capacidad.R` | `capacidad_servicios_<desde>_<hasta>.xlsx` | `Resumen_semanal`, `Opciones`, `Balance_dia_turno`, `Perfil_semanal`, `Meta_completar`, `Meta_frecuencia`, `Serie_diaria`, `Definiciones` | ~1,3 min |
| `analisis_flota.R` | `flota_frecuencia_<desde>_<hasta>.xlsx` | `Flota_por_turno`, `Opciones`, `Escenarios`, `Productividad`, `Disponibles`, `Validacion_planilla`, `Uso_flota_actual`, `Lugar_libre`, `Circuitos_a_subir`, `Definiciones` | ~1,5 min |
| `verificar_analisis.R` | — (solo consola) | — | ~1,7 min |

### De qué hoja sale cada tabla del documento para decisores

| Sección del documento | Excel | Hoja |
|---|---|---|
| La flota: camiones al inicio de cada turno | `flota_frecuencia_…` | `Flota_por_turno`, `Disponibles` |
| Validación con la planilla de operaciones | `flota_frecuencia_…` | `Validacion_planilla` |
| Opciones para la decisión | `flota_frecuencia_…` | `Opciones` |
| Rendimiento por turno | `flota_frecuencia_…` | `Productividad` |
| Calidad del servicio actual | `analisis_servicios_viajes_…` | `Calidad_servicio` |
| Gráfico de uso por día y turno | `capacidad_servicios_…` | `Balance_dia_turno` (`demanda_actual`, `oferta_liberable`) |
| Validación de la regla de grúa | `analisis_servicios_viajes_…` | `Validacion_grua` |

El documento **no se actualiza solo**: después de volver a correr los scripts hay que pasar las cifras a mano.

## 🧭 Decisiones de criterio

Tomadas con el usuario durante el análisis; cambiarlas cambia todos los números.

| Decisión | Por qué | Dónde está en el código |
|---|---|---|
| Un viaje GOL = un camión-turno | No hay matrícula; confirmado por el usuario | Todo el módulo |
| Los camiones disponibles son los **camiones al inicio** de cada turno según la planilla de operaciones (media de los últimos 3 meses), no una flota fija con reserva; los camiones-turno de otros municipios **no** son camiones extra | Antes se suponía una flota fija (30, luego 27) con 10 % de reserva = 24 en todos los turnos. La planilla muestra que de noche hay ~27 al inicio y de día menos (~23 de mañana, ~21 de tarde), y que los rotos ya vienen descontados (2026-10-15) | `flota_funciones.R` |
| 1 viaje GOL = 1 camión-turno, y la fecha GOL del nocturno es la del turno | Validado con la planilla: camiones usados y camiones-turno de GOL difieren menos de 1 por turno en promedio y la correlación diaria es 0,93 con la misma fecha (0,67 corriendo un día) | `validar_con_planilla()` |
| Turno y fecha tal cual GOL (el nocturno no pasa al día siguiente) | Pedido del usuario; difiere del "Criterio Adrián" de `informes/informecamiones.R` | `preparar_universo()` |
| Sin sábado nocturno | No hay turno; los pocos registros se descartan y ese turno no cuenta ni como 0 | `es_sabado_noche()`, `grid_dia_turno()` |
| Solo contenedores activos | Pedido del usuario | `preparar_universo()` |
| % completo en dos niveles: viaje y circuito-día-turno | GOL lista filas solapadas cuando dos camiones comparten un circuito | `resumir_viajes()`, `resumir_circuitos()` |
| Excluir viajes de grúa por forma del viaje | Son levantes puntuales; validado: 67 % de sus contenedores tenían motivo de grúa previo vs 2,4 % del resto | `marcar_viajes_grua()` |
| Dimensionar con p90, no con la media | La media deja sin cubrir los días cargados | `perfil_semanal()`, `lugar_libre()` |

## 🔗 Dependencias

- R con el `renv` del proyecto (el lockfile fija R 4.5.1; se ejecutó y verificó con R 4.6.1): `data.table`, `openxlsx` (y `stats` para `wilcox.test`).
- No usa conexiones externas: solo los RDS de `db/`.

## ⚡ Mejoras Futuras

- [ ] La hoja `Opciones` y `balance_capacidad()` de `analisis_capacidad.R` usan la lógica anterior (camiones-turno de A/D/E/F/G como "oferta liberable", sin límite de flota). La vigente es `Opciones` del Excel de flota; conviene renombrar o quitar la del Excel de capacidad para que no se confundan.
- [ ] Los tres scripts leen los mismos RDS por separado; un script único que corra todo leería los 10 M de filas una sola vez.
- [ ] `verificar_analisis.R` depende de viajes concretos del histórico (44882, 44914, 31637, 58569); si el histórico se recorta, esos casos hay que reemplazarlos.
- [ ] Las cifras del documento para decisores se copian a mano; se podría generar una hoja `Documento` con todas juntas.
