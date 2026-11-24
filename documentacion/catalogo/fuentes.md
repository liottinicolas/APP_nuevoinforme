# Fuentes de datos — APP_nuevoinforme (verificado: 2026-11-18)

| Fuente | Tipo | Ubicación | Quién la usa | Notas |
|---|---|---|---|---|
| `db\DFR\RDS\dfr_E_DF_POSICIONES_RECORRIDO.rds` | RDS local | carpeta del proyecto | `limpieza_datos.R` | Entrada del pipeline. Se genera fuera de la app. |
| `db\DFR\RDS\dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds` | RDS local | carpeta del proyecto | `limpieza_datos.R` | Histórico de inactivos. |
| `db\GOL_reportes\historico_llenadoGol.rds` | RDS local | carpeta del proyecto | `limpieza_datos.R` | Histórico de llenado. |
| `UNA_POR_CIRCUITO\rds\circuitos_periodo.rds` | RDS local | carpeta del proyecto | `limpieza_datos.R` | Circuitos por período. |
| Repo `liottinicolas/APP_nuevoinforme-data` | GitHub (pins) | `data\` del repo | `App.R` | Destino del pipeline y origen de la app publicada. |
| Endpoint de comprobación (`App.R`, línea ~198) | HTTP | POR CONFIRMAR | `App.R` | Timeout de 3 s. |
| Endpoint de consulta (`App.R`, línea ~1238) | HTTP | POR CONFIRMAR | `App.R` | Timeout de 10 s. |

Para el detalle de cada pin y variable, ver [variables](variables.md).
