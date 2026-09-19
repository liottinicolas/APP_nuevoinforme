# Pedido: misma lógica que Pedidos/contenedores_levantados_2porsemana.r, pero:
#   - el umbral es 3 levantes (en vez de 2)
#   - en vez de una sola ventana puntual, se calcula para TODO el histórico
#     desde que arrancó el llenado (Fecha mínima con datos)
#   - las semanas son de domingo a sábado (semana "domingo a domingo": arranca
#     el domingo y termina el sábado siguiente, 7 días)
#   - devuelve una tabla larga con una fila por gid y por semana, donde la
#     semana se identifica con un número correlativo (Semana 1, 2, 3, ...) y
#     columnas separadas con las fechas de inicio/fin de esa semana; y una
#     tabla aparte "semanas" que es el diccionario Semana -> fechas.
#
# Criterio (mismo que en PorcentajeLlenado.R y contenedores_levantados_2porsemana.r):
# recolección efectiva = Levantado == "S". Universo: Oficina == "IM" y
# contenedor activo esa semana, es decir que su Estado más reciente dentro de
# esa semana en db/10393_ubicaciones/historico_ubicaciones.rds sea NA/vacío
# (Estado no NA = "Mantenimiento", "Sin instalar", etc., no correspondía
# levantar).
#
# La última semana se excluye si todavía está incompleta (su fecha de fin es
# posterior a la última fecha con datos), para no marcar como "no cumplió"
# contenedores cuya semana en curso todavía no terminó de registrarse.
#
# Parámetros:
#   df             - data.frame opcional con el histórico de llenado ya
#                    cargado. Si es NULL, se lee
#                    db/GOL_reportes/historico_llenadoGol.rds.
#   df_ubicaciones - data.frame opcional con el histórico de ubicaciones ya
#                    cargado. Si es NULL, se lee
#                    db/10393_ubicaciones/historico_ubicaciones.rds.
#
# Devuelve (invisible) una lista con:
#   $semanas             - diccionario Semana -> Fecha_inicio_semana / Fecha_fin_semana,
#                           una fila por semana calculada (domingo a sábado).
#   $resumen             - una fila por gid y por semana, con Semana,
#                           Fecha_inicio_semana, Fecha_fin_semana, Direccion,
#                           Circuito_corto, n_levantes, n_no_levantes,
#                           total_pasajes y cumplio_3_veces.
#   $cumplieron_3_veces  - subconjunto de $resumen con n_levantes >= 3.
#   $no_llegaron_a_3     - subconjunto de $resumen con n_levantes < 3.
#   $resumen_semanal     - una fila por semana (agrupado), con Semana,
#                           Fecha_inicio_semana, Fecha_fin_semana,
#                           n_cumplieron, n_no_cumplieron, total_contenedores
#                           y pct_cumplimiento.
#   $mejor_semana        - fila de $resumen_semanal de la semana con mayor
#                           pct_cumplimiento (la leyenda impresa en consola
#                           se arma a partir de esta fila).
#
# Uso:
#   resultado <- verificar_contenedores_3_veces_historico()
#   resultado$semanas                                    # fechas de cada semana
#   resultado$resumen   %>% filter(Semana == 1)           # detalle de la semana 1
#   resultado$no_llegaron_a_3 %>% filter(Semana == 10)
#   resultado$resumen_semanal                             # cumplieron/no cumplieron por semana
#   resultado$mejor_semana                                # semana con mayor % de cumplimiento

library(dplyr)

verificar_contenedores_3_veces_historico <- function(df = NULL, df_ubicaciones = NULL) {
  # 1. Cargar datos si no se pasaron ya cargados
  if (is.null(df)) {
    df <- readRDS(file.path("db", "GOL_reportes", "historico_llenadoGol.rds"))
  }
  if (is.null(df_ubicaciones)) {
    df_ubicaciones <- readRDS(file.path("db", "10393_ubicaciones", "historico_ubicaciones.rds"))
  }

  # Domingo de la semana a la que pertenece una fecha (%w: domingo = 0)
  inicio_semana <- function(fecha) fecha - as.numeric(format(fecha, "%w"))

  # 2. Universo IM + columna de semana (domingo de esa semana)
  base_llenado <- df %>%
    filter(Oficina == "IM") %>%
    mutate(Fecha_inicio_semana = inicio_semana(Fecha))

  # 3. Gids activos por semana: Estado más reciente dentro de esa semana es NA/vacío
  activos_semana <- df_ubicaciones %>%
    filter(Oficina == "IM") %>%
    mutate(Fecha_inicio_semana = inicio_semana(Fecha)) %>%
    arrange(gid, Fecha_inicio_semana, desc(Fecha)) %>%
    distinct(gid, Fecha_inicio_semana, .keep_all = TRUE) %>%
    filter(is.na(Estado) | trimws(Estado) == "") %>%
    select(gid, Fecha_inicio_semana)

  base_llenado <- base_llenado %>%
    inner_join(activos_semana, by = c("gid", "Fecha_inicio_semana"))

  # 4. Excluir la última semana si todavía está incompleta
  ultima_fecha_con_datos <- max(df$Fecha, na.rm = TRUE)
  base_llenado <- base_llenado %>%
    filter(Fecha_inicio_semana + 6 <= ultima_fecha_con_datos)

  if (nrow(base_llenado) == 0) {
    stop("No hay semanas completas de contenedores IM activos para analizar.")
  }

  # Dirección/circuito más reciente por gid y semana
  ref_ubicacion <- base_llenado %>%
    arrange(gid, Fecha_inicio_semana, desc(Fecha)) %>%
    distinct(gid, Fecha_inicio_semana, .keep_all = TRUE) %>%
    select(gid, Fecha_inicio_semana, Direccion, Circuito_corto)

  # 5. Conteo de levantes efectivos y no efectivos por gid y por semana
  resumen <- base_llenado %>%
    group_by(gid, Fecha_inicio_semana) %>%
    summarise(
      n_levantes = sum(Levantado == "S", na.rm = TRUE),
      n_no_levantes = sum(Levantado == "N", na.rm = TRUE),
      total_pasajes = n(),
      .groups = "drop"
    ) %>%
    mutate(
      Fecha_fin_semana = Fecha_inicio_semana + 6,
      cumplio_3_veces = n_levantes >= 3
    ) %>%
    left_join(ref_ubicacion, by = c("gid", "Fecha_inicio_semana"))

  # 6. Diccionario de semanas: Semana 1 = primera semana con datos, en orden cronológico
  semanas <- resumen %>%
    distinct(Fecha_inicio_semana, Fecha_fin_semana) %>%
    arrange(Fecha_inicio_semana) %>%
    mutate(Semana = row_number()) %>%
    select(Semana, Fecha_inicio_semana, Fecha_fin_semana)

  resumen <- resumen %>%
    left_join(semanas, by = c("Fecha_inicio_semana", "Fecha_fin_semana")) %>%
    select(
      Semana, Fecha_inicio_semana, Fecha_fin_semana, gid, Direccion, Circuito_corto,
      n_levantes, n_no_levantes, total_pasajes, cumplio_3_veces
    ) %>%
    arrange(Semana, cumplio_3_veces, n_levantes)

  cumplieron_3_veces <- resumen %>% filter(cumplio_3_veces)
  no_llegaron_a_3 <- resumen %>% filter(!cumplio_3_veces)

  # 7. Agrupado por semana: cuántos cumplieron y cuántos no, y % de cumplimiento
  resumen_semanal <- resumen %>%
    group_by(Semana, Fecha_inicio_semana, Fecha_fin_semana) %>%
    summarise(
      n_cumplieron = sum(cumplio_3_veces),
      n_no_cumplieron = sum(!cumplio_3_veces),
      total_contenedores = n(),
      .groups = "drop"
    ) %>%
    mutate(pct_cumplimiento = round(100 * n_cumplieron / total_contenedores, 1)) %>%
    arrange(Semana)

  # Mejor semana = mayor % de cumplimiento (desempate: más contenedores cumplieron)
  mejor_semana <- resumen_semanal %>%
    arrange(desc(pct_cumplimiento), desc(n_cumplieron)) %>%
    slice(1)

  cat("Semanas completas analizadas:", nrow(semanas), "\n")
  cat("Rango:", as.character(min(semanas$Fecha_inicio_semana)), "a", as.character(max(semanas$Fecha_fin_semana)), "\n")
  cat("Filas gid x semana:", nrow(resumen), "\n")
  cat("Cumplieron 3 levantes o más:", nrow(cumplieron_3_veces), "\n")
  cat("No llegaron a 3 levantes:", nrow(no_llegaron_a_3), "\n")
  cat(sprintf(
    "\nMejor semana: Semana %d (%s a %s) - %.1f%% de cumplimiento (%d de %d contenedores llegaron a 3 levantes)\n",
    mejor_semana$Semana, mejor_semana$Fecha_inicio_semana, mejor_semana$Fecha_fin_semana,
    mejor_semana$pct_cumplimiento, mejor_semana$n_cumplieron, mejor_semana$total_contenedores
  ))

  invisible(list(
    semanas = semanas,
    resumen = resumen,
    cumplieron_3_veces = cumplieron_3_veces,
    no_llegaron_a_3 = no_llegaron_a_3,
    resumen_semanal = resumen_semanal,
    mejor_semana = mejor_semana
  ))
}

# --- Ejemplo de uso ---
# resultado <- verificar_contenedores_3_veces_historico()
# resultado$semanas                                     # diccionario Semana -> fechas
# resultado$resumen %>% dplyr::filter(Semana == 1)      # detalle semana 1
# resultado$no_llegaron_a_3 %>% dplyr::filter(Semana == 10)
# resultado$resumen_semanal
# resultado$mejor_semana
