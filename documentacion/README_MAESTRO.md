# Entorno: APP_nuevoinforme (verificado: 2026-11-18)

Repositorio de código de reporting operativo de la División Limpieza y Gestión de Residuos (IM). Incluye tareas batch, informes y una app Shiny publicada en shinyapps.io.

Esta documentación vive en `documentacion\` y cubre solo este entorno. Cada tarea tiene su ficha en `tareas\`. Las fichas de Jupyter están en su propio entorno.

## Tareas

| Tarea | Ubicación | Estado de documentación |
|---|---|---|
| App Shiny de llenado (publicada) | `vistas\App_informe_llenado\` | [Ficha](tareas/app_informe_llenado.md) |
| Pipeline de datos de la app | `vistas\App_informe_llenado\limpieza_datos.R` | Incluida en la ficha anterior |
| Perfilado de fuentes RDS | `vistas\App_informe_llenado\perfilado_datos.R` | [Ficha](tareas/perfilado_datos.md) (escrito, sin ejecutar) |
| Informe diario y motor de negocio | `informes\` | Pendiente |
| Módulos de reporting (7) | `vistas\` | Pendiente |
| Visores de flota y pesadas | `Visor_vehiculos.R`, `Visor_hogares_sustentables.R`, `Pesadas_Intra.R`, `prueba_api.R` | Pendiente |
| Carga incremental de CSV | `cargaDeDatos.R` | Pendiente |
| Batch de limpieza urbana | `scripts\` | Pendiente |
| Envío de correos masivos | `COMPRAS\` | Pendiente |

## Entornos de ejecución

- **Local Windows:** desarrollo y ejecución de los batch. Depende de `xlwings` y `pywin32`, que solo funcionan en Windows con Excel (ver `requirements.txt`).
- **shinyapps.io:** publicación de la app Shiny. Cuenta `datoseindicadores`, app `App_informe_llenado` (según `rsconnect\shinyapps.io\`).

## Flujo de datos de la app Shiny

1. Los batch locales generan RDS en `db\` y `UNA_POR_CIRCUITO\rds\`.
2. `limpieza_datos.R` se corre en local. Lee esos RDS y escribe pins en el repositorio de datos `APP_nuevoinforme-data` (carpeta `data\`).
3. `App.R` lee los pins desde la URL raw de GitHub. Así la app publicada no depende de archivos locales.

Ver el detalle en la ficha de la tarea.

## Reglas

- Cada dato lleva `verificado: AAAA-MM-DD`. Lo no confirmado se marca `POR CONFIRMAR`.
- No se guardan tokens ni credenciales. Solo nombres de variables de entorno.
- Los cambios se registran en [CHANGELOG.md](CHANGELOG.md).
- Catálogos: [variables](catalogo/variables.md) y [fuentes de datos](catalogo/fuentes.md).

## Pendientes

- Confirmar el comando exacto de despliegue (`rsconnect`) y la frecuencia de actualización de datos.
- `APP_nuevoinforme-data` vive dentro de OneDrive. `limpieza_datos.R` lo menciona como fuente de conflictos al borrar y reemplazar `data\`.
- Credenciales hardcodeadas según el README del proyecto (pendiente, ver `docs\improvements.md`).
