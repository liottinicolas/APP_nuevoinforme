# Tarea: App Shiny de llenado (verificado: 2026-11-18)

Ubicación: `vistas\App_informe_llenado\`

## Objetivo
App Shiny publicada en shinyapps.io. Muestra el mapa de contenedores (GID) y el histórico de llenado. Permite exportar a PDF y Excel.

## Archivos

| Archivo | Rol | ¿Se despliega? |
|---|---|---|
| `App.R` | App activa. Carga datos y arma la interfaz. | Sí |
| `informe_pdf.R` | Informe PDF del historial (se incluye con `source`). | Sí, como dependencia |
| `informe_excel.R` | Exportación a Excel del historial (se incluye con `source`). | Sí, como dependencia |
| `limpieza_datos.R` | Pipeline local: RDS → pins en el repo de datos. | No, se corre en local |
| `App_v2.R` | Versión anterior con Leaflet. Respaldo local. | No (excluido en `.rscignore`) |
| `.rscignore` | Excluye `data\` y `App_v2.R` del despliegue. | — |
| `fonts\` | Fuentes para el PDF. | Sí |
| `rsconnect\` | Metadatos del despliegue en shinyapps.io. | No |
| `documentacion_analisis.md` | Análisis previo del proyecto. | No |

## Paquetes R
shiny, bslib, htmltools, mapgl, sf, pins, dplyr, DT, jsonlite, httr, ggplot2, showtext, openxlsx. En `limpieza_datos.R`: gert, pins, dplyr, here (POR CONFIRMAR: `here` no aparece en la lista de `library()` del archivo).

## Carga de datos (App.R)
- Lee los pins del repo `liottinicolas/APP_nuevoinforme-data` vía `pins::board_url()`.
- Pins que lee: `GID_activos`, `GID_inactivos`, `historico_llenado_web`, `circuitos_periodo`.
- Los datos se preprocesan al cargar: `preprocesar_datos()` convierte a `sf` con CRS 32721.
- Llamada HTTP con `httr::timeout(3)` para comprobar la fuente; POR CONFIRMAR: qué endpoint consulta esa comprobación y la llamada de `httr::timeout(10)` alrededor de la línea 1238.

## Pipeline de datos (limpieza_datos.R)

Se corre en local, desde la raíz del proyecto.

1. Clona o actualiza el repo `APP_nuevoinforme-data` junto al proyecto (carpeta padre).
2. Lee cuatro RDS de entrada (ver [fuentes](../catalogo/fuentes.md)).
3. Borra y reemplaza `data\` del repo de datos. Hay reintentos porque OneDrive puede bloquear la carpeta.
4. Escribe los cuatro pins con `pin_write(type = "rds")`, sin versionado.
5. Escribe `_pins.yaml` con `write_board_manifest()`. Sin ese manifest, la URL devuelve 404.
6. Hace commit y push al repo de datos.

## Despliegue

1. Correr `limpieza_datos.R` en local. Así los datos quedan actualizados en GitHub.
2. Desplegar `App.R` a shinyapps.io desde `vistas\App_informe_llenado\`. POR CONFIRMAR: comando y cuenta exactos (`rsconnect::deployApp`).

## Decisiones tomadas
- Datos en un repo aparte para no llenar el historial de código con copias binarias. Está explicado en el encabezado de `limpieza_datos.R`.
- En producción, la app lee desde GitHub raw. Si se empaqueta `data\`, queda congelada en el servidor (ver `.rscignore`).

## Pendientes
- Confirmar frecuencia de actualización y responsable del pipeline.
- Revisar la comprobación HTTP de `App.R` alrededor de la línea 198 y la llamada de la línea 1238.
