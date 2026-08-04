# 04 · Motor del Informe Diario (`informes/`)

Tipo: R scripts — lógica de negocio central del proyecto

## 📖 ¿Qué hace?

Es el corazón analítico del sistema: cruza histórico de ubicaciones de contenedores, histórico de llenado GOL y planificación de circuitos (rotación de 42 días) para producir los resúmenes de Programado/Visitados/Vaciados/Planificados que alimentan todos los reportes de `vistas/`. También calcula los viajes de camiones por turno aplicando el "Criterio de Adrián".

## 📊 Entrada (Input)

- `db/10393_ubicaciones/historico_ubicaciones.rds`
- `db/GOL_reportes/historico_llenadoGol.rds`
- `db/planificados/versiones_planificacion.rds` (+ plantillas referenciadas)
- `vistas/informediario/data/tabla_solo{IM,FID}_resumen_pordia_municipio_turno_completo.rds` (usado por `informecamiones.R`)

## 🔄 Proceso

### `informe_diario.R` — motor principal
```r
funcion_obtener_planificados()        # mapea cada fecha real a una fecha de plantilla módulo 42 días
funcion_df_nuevoinformediario()       # motor: cálculo incremental de resúmenes por día/municipio/turno
```
Detecta si ya hay resúmenes guardados y calcula solo las fechas faltantes (o recalcula todo si se solicita); clasifica Visitado/No visitado según catálogo de `motivos_con_visita`/`motivos_sin_visita`; genera resúmenes por día, por día+municipio, y por día+municipio+turno (grilla completa rellenada de ceros), separados para IM y Fideicomiso.

### `informecamiones.R` — viajes por turno
```r
funcion_contar_viajes_por_diayturno()          # agrupa por Fecha/Turno_levantado, cuenta n_distinct(Id_viaje_GOL)
aplicar_criterio_adrian_y_guardar()            # Turno Nocturno -> Fecha + 1 día
aplicar_criterio_adrian_visitados_y_guardar()  # idem para datos de visitados/vaciados
```
El **"Criterio de Adrián"** (nombre de un integrante del equipo) es la regla de negocio: si `Turno_levantado == "Nocturno"`, se suma 1 día a la `Fecha` del registro, para que el turno noche cierre el ciclo operativo del día calendario siguiente.

### `pruebaplani.R` — prototipo
```r
generar_planificados_vectorizado(fecha_inicio, fecha_fin)
```
Versión vectorizada de prueba de la planificación cíclica de 42 días a partir del Excel `informes/planificados/planificacion.xlsx`; precursora de `funcion_obtener_planificados()`, que en producción lee RDS versionados en vez del Excel directo.

## 📤 Salida (Output)

- `vistas/informediario/data/tabla_solo{IM,FID}_resumen_pordia.rds`, `..._pordiaymunicipio.rds`, `..._pordia_municipio_turno_completo.rds`
- `vistas/informe_levantes_camiones_porturno_IM_FID/data/*_criterioadrian.rds` (5 archivos: viajes por camión y visitados/vaciados, para IM/Fideicomiso/combinado)
- `scripts/visitados/datos_vaciados_camiones.xlsx` (Excel consolidado multi-hoja)

## 🔗 Dependencias

- R: `dplyr`, `lubridate`, `readxl`, `tidyr`, `writexl`, `openxlsx`, `here`

## ⚡ Mejoras Futuras

- [ ] `informe_diario.R` tiene secciones grandes de código comentado/experimental mezclado con el activo — dificulta el mantenimiento de una lógica ya de por sí densa. Limpiar código muerto o moverlo a una rama/archivo de referencia.
- [ ] El manejo de locale `es_UY.UTF-8` vía `try()` silencioso puede fallar sin aviso en Windows — agregar un log explícito si el `try()` falla.
- [ ] El filtro de Fideicomiso al Municipio "B" y turnos Matutino/Nocturno está hardcodeado — documentar la regla de negocio en el propio código como comentario, ya que no es evidente por qué se excluye el turno Vespertino.
- [ ] `informecamiones.R` tiene un filtro de fecha hardcodeado (`Fecha > "2026-01-01"`) — parametrizar o documentar por qué esa fecha de corte.
- [ ] `pruebaplani.R` es un prototipo que no persiste resultados — considerar eliminarlo o marcarlo explícitamente como archivo de referencia histórica, ya que su lógica ya fue migrada a `informe_diario.R`.

## 📌 Notas

Este es el módulo más denso y de mayor riesgo del proyecto en términos de mantenibilidad: concentra la lógica de negocio que determina qué cuenta como "visitado" o "vaciado", de la cual dependen prácticamente todos los reportes en `vistas/`.
