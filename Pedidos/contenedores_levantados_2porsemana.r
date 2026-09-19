# Pedido: verificar qué contenedores de IM se levantaron 2 veces (o más) y
# cuáles no llegaron a esa cantidad, entre dos fechas determinadas.
#
# Criterio (mismo usado en informes/Porcentaje_llenado_peorescasos/PorcentajeLlenado.R):
# recolección efectiva = Levantado == "S". Se cuentan los levantes efectivos
# por contenedor (gid) dentro de la ventana [fecha_inicio, fecha_fin] y se
# compara contra 2.
#
# Universo: solo contenedores con Oficina == "IM" (se excluye Fideicomiso) y
# que además estén activos, es decir que su Estado más reciente en
# db/10393_ubicaciones/historico_ubicaciones.rds dentro de la ventana sea
# NA/vacío (mismo criterio "Solo_activos" que exportar_resumen_contenedores()
# en funciones_utiles.R: Estado no NA = "Mantenimiento", "Sin instalar", etc.,
# contenedores que no correspondía levantar). Se consideran únicamente los gid
# que tienen al menos un registro (pasaje de camión, haya levantado o no) en
# la ventana pedida.
#
# Parámetros:
#   fecha_inicio    - fecha "YYYY-MM-DD" de inicio de la ventana (inclusive).
#   fecha_fin       - fecha "YYYY-MM-DD" de fin de la ventana (inclusive).
#   df              - data.frame opcional con el histórico de llenado ya
#                      cargado. Si es NULL, se lee
#                      db/GOL_reportes/historico_llenadoGol.rds.
#   df_ubicaciones  - data.frame opcional con el histórico de ubicaciones ya
#                      cargado. Si es NULL, se lee
#                      db/10393_ubicaciones/historico_ubicaciones.rds.
#
# Devuelve (invisible) una lista con:
#   $resumen             - un registro por gid (solo activos) con n_levantes,
#                           n_no_levantes, total_pasajes, Direccion y
#                           Circuito_corto (más recientes en la ventana) y
#                           cumplio_2_veces.
#   $cumplieron_2_veces  - subconjunto de $resumen con n_levantes >= 2.
#   $no_llegaron_a_2     - subconjunto de $resumen con n_levantes < 2.
#
# Uso:
#   resultado <- verificar_contenedores_2_levantes("2026-09-01", "2026-09-07")
#   resultado$cumplieron_2_veces
#   resultado$no_llegaron_a_2

library(dplyr)

verificar_contenedores_2_levantes <- function(fecha_inicio, fecha_fin, df = NULL, df_ubicaciones = NULL) {
  # 1. Cargar datos si no se pasaron ya cargados
  if (is.null(df)) {
    df <- readRDS(file.path("db", "GOL_reportes", "historico_llenadoGol.rds"))
  }
  if (is.null(df_ubicaciones)) {
    df_ubicaciones <- readRDS(file.path("db", "10393_ubicaciones", "historico_ubicaciones.rds"))
  }

  fecha_min <- as.Date(fecha_inicio)
  fecha_max <- as.Date(fecha_fin)

  # 2. Ventana de fechas + universo IM
  en_ventana <- df %>%
    filter(Fecha >= fecha_min, Fecha <= fecha_max, Oficina == "IM")

  if (nrow(en_ventana) == 0) {
    stop("No hay registros de contenedores IM entre ", fecha_min, " y ", fecha_max, ".")
  }

  # Gids activos: Estado más reciente en la ventana es NA/vacío
  gids_activos <- df_ubicaciones %>%
    filter(Fecha >= fecha_min, Fecha <= fecha_max, Oficina == "IM") %>%
    arrange(gid, desc(Fecha)) %>%
    distinct(gid, .keep_all = TRUE) %>%
    filter(is.na(Estado) | trimws(Estado) == "") %>%
    pull(gid)

  en_ventana <- en_ventana %>% filter(gid %in% gids_activos)

  if (nrow(en_ventana) == 0) {
    stop("No hay registros de contenedores IM activos (Estado NA) entre ", fecha_min, " y ", fecha_max, ".")
  }

  # Dirección/circuito más reciente por contenedor, para identificar filas
  ref_ubicacion <- en_ventana %>%
    arrange(gid, desc(Fecha)) %>%
    distinct(gid, .keep_all = TRUE) %>%
    select(gid, Direccion, Circuito_corto)

  # 3. Conteo de levantes efectivos y no efectivos por contenedor
  resumen <- en_ventana %>%
    group_by(gid) %>%
    summarise(
      n_levantes = sum(Levantado == "S", na.rm = TRUE),
      n_no_levantes = sum(Levantado == "N", na.rm = TRUE),
      total_pasajes = n(),
      .groups = "drop"
    ) %>%
    mutate(cumplio_2_veces = n_levantes >= 2) %>%
    left_join(ref_ubicacion, by = "gid") %>%
    select(gid, Direccion, Circuito_corto, n_levantes, n_no_levantes, total_pasajes, cumplio_2_veces) %>%
    arrange(cumplio_2_veces, n_levantes)

  cumplieron_2_veces <- resumen %>% filter(cumplio_2_veces)
  no_llegaron_a_2 <- resumen %>% filter(!cumplio_2_veces)

  cat("Ventana analizada:", as.character(fecha_min), "a", as.character(fecha_max), "\n")
  cat("Contenedores IM con registros en la ventana:", nrow(resumen), "\n")
  cat("Cumplieron 2 levantes o más:", nrow(cumplieron_2_veces), "\n")
  cat("No llegaron a 2 levantes:", nrow(no_llegaron_a_2), "\n")

  invisible(list(
    resumen = resumen,
    cumplieron_2_veces = cumplieron_2_veces,
    no_llegaron_a_2 = no_llegaron_a_2
  ))
}

# --- Ejemplo de uso ---
# resultado <- verificar_contenedores_2_levantes("2026-09-04", "2026-09-10")
# resultado$cumplieron_2_veces
# no_llegaron <- resultado$no_llegaron_a_2
