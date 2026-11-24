# =============================================================================
# Flota y frecuencia: ¿cuánta frecuencia extra entra con la flota disponible?
#   - Los camiones disponibles salen de la planilla de operaciones (camiones al
#     inicio de cada turno), o de un número fijo de flota para sensibilidad.
#   - De noche se usa primero el lugar libre; lo que no entra va a Matutino y
#     luego a Vespertino, con la productividad diurna medida (congestión).
# Requiere analisis_servicios_funciones.R y capacidad_funciones.R
# =============================================================================

# Planilla "Información", hoja Disponibilidad (operaciones): una fila por fecha y
# turno con camiones al inicio, camiones usados, choferes y auxiliares.
# La URL (export CSV, gid=0) se lee de la variable de entorno URL_DISPONIBILIDAD,
# definida en el .Renviron de la raíz del proyecto (no se versiona: el repo es
# público y la planilla se abre con solo tener el enlace).
URL_DISPONIBILIDAD <- Sys.getenv("URL_DISPONIBILIDAD")
RUTA_DISPONIBILIDAD <- "db/disponibilidad/disponibilidad_camiones.csv"

# Baja la hoja a RUTA_DISPONIBILIDAD; si falla, sigue con la copia local.
# Se baja a un temporal: download.file trunca el destino aunque la descarga falle.
# En Windows la red de la IM no deja verificar la revocación del certificado
# (CRYPT_E_NO_REVOCATION_CHECK); R_LIBCURL_SSL_REVOKE_BEST_EFFORT lo tolera.
descargar_disponibilidad <- function(ruta = RUTA_DISPONIBILIDAD, url = URL_DISPONIBILIDAD) {
  dir.create(dirname(ruta), showWarnings = FALSE, recursive = TRUE)
  if (!nzchar(url)) {
    message("Falta URL_DISPONIBILIDAD en .Renviron; se usa la copia local: ", ruta)
    return(invisible(ruta))
  }
  Sys.setenv(R_LIBCURL_SSL_REVOKE_BEST_EFFORT = "TRUE")
  tmp <- tempfile(fileext = ".csv")
  ok <- tryCatch(download.file(url, tmp, quiet = TRUE, mode = "wb", method = "libcurl") == 0,
                 error = function(e) FALSE, warning = function(w) FALSE)
  ok <- ok && file.exists(tmp) && startsWith(readLines(tmp, n = 1, warn = FALSE), "FECHA")
  if (ok) file.copy(tmp, ruta, overwrite = TRUE)
  else message("No se pudo descargar la planilla de disponibilidad; se usa la copia local: ", ruta)
  invisible(ruta)
}

leer_disponibilidad <- function(ruta = RUTA_DISPONIBILIDAD) {
  s <- fread(ruta)
  setnames(s, c("Fecha", "turno_letra", "inicio", "usados", "choferes", "auxiliares"))
  s[, Fecha := as.Date(Fecha, "%d/%m/%Y")]
  s[, Turno := c(M = "Matutino", V = "Vespertino", N = "Nocturno")[toupper(turno_letra)]]
  s[, turno_letra := NULL]
  s[!is.na(Fecha) & !is.na(Turno)]
}

# Camiones disponibles por turno y día de semana = media de camiones al inicio
# en los turnos que trabajaron (usados > 0) de los últimos `meses` hasta `hasta`.
# Un turno sin datos (sábado nocturno) queda con 0 disponibles.
disponibilidad_por_turno <- function(planilla, hasta, meses = 3) {
  desde <- seq(hasta, by = sprintf("-%d months", meses), length.out = 2)[2] + 1
  x <- planilla[Fecha >= desde & Fecha <= hasta & usados > 0]
  x[, dia_semana := dia_semana(Fecha)]
  r <- x[, .(disponibles = mean(inicio), dias = .N), by = .(Turno, dia_semana)]
  r <- r[CJ(Turno = TURNOS, dia_semana = factor(DIAS_SEMANA, DIAS_SEMANA)), on = .(Turno, dia_semana)]
  r[is.na(disponibles), `:=`(disponibles = 0, dias = 0L)]
  setattr(r, "periodo", c(desde, hasta))
  r[]
}

# Disponibles por turno y día: `flota` es un número (flota fija) o la salida de
# disponibilidad_por_turno(). La reserva descuenta camiones fuera de servicio
# (con la planilla ya vienen descontados: reserva 0).
disponibles_tabla <- function(flota, reserva) {
  if (is.numeric(flota)) {
    CJ(Turno = TURNOS, dia_semana = factor(DIAS_SEMANA, DIAS_SEMANA))[, disp := floor(flota * (1 - reserva))][]
  } else {
    flota[, .(Turno, dia_semana, disp = floor(disponibles * (1 - reserva)))]
  }
}

etiqueta_flota <- function(flota) {
  if (is.numeric(flota)) as.character(flota) else "Camiones al inicio (planilla de operaciones)"
}

# Validación: camiones usados según la planilla vs camiones-turno de GOL (todos
# los viajes IM sin grúa) por turno, en días hábiles y fines de semana.
validar_con_planilla <- function(planilla, vb, desde, hasta) {
  g <- vb[bloque %in% c("Demanda", "Oferta", "C_excluido"), .(gol = .N), by = .(Fecha, Turno)]
  x <- g[planilla[Fecha >= desde & Fecha <= hasta & usados > 0], on = .(Fecha, Turno)]
  x[is.na(gol), gol := 0L]
  x[, tipo_dia := fifelse(format(Fecha, "%u") %in% c("6", "7"), "Fin de semana", "Día hábil")]
  r <- x[, .(
    turnos = .N,
    usados_planilla_media = mean(usados), camiones_gol_media = mean(gol),
    usados_planilla_p90 = as.numeric(quantile(usados, 0.9, names = FALSE)),
    camiones_gol_p90 = as.numeric(quantile(gol, 0.9, names = FALSE)),
    diferencia_media = mean(gol - usados),
    correlacion_diaria = cor(usados, gol),
    inicio_planilla_media = mean(inicio)
  ), by = .(Turno, tipo_dia)]
  r[, Turno := factor(Turno, TURNOS)]
  setorder(r, Turno, tipo_dia)
  r[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Productividad por turno de B_101-103, CH y C_101-109, comparando el MISMO circuito de día y de
# noche (controla tamaño y geografía del circuito).
#   ritmo      = contenedores visitados por hora (primer a último pasaje)
#   visitados  = contenedores visitados por camión-turno
# factor_* = mediana entre circuitos de (valor diurno / valor nocturno).
# -----------------------------------------------------------------------------
productividad_por_turno <- function(universo, llenado, min_viajes = 3) {
  pasajes <- as.data.table(llenado)[Id_viaje_GOL %in% universo$Id_viaje_GOL & !is.na(Fecha_hora_pasaje),
                                    .(ini = min(Fecha_hora_pasaje), fin = max(Fecha_hora_pasaje)), by = Id_viaje_GOL]
  ppal <- universo[, .N, by = .(Id_viaje_GOL, Circuito_corto)][order(-N)][!duplicated(Id_viaje_GOL)]
  v <- universo[, .(visitados = sum(visitado)), by = .(Id_viaje_GOL, Turno)]
  v <- ppal[, .(Id_viaje_GOL, Circuito_corto)][v, on = "Id_viaje_GOL"]
  v <- pasajes[v, on = "Id_viaje_GOL"]
  v[, horas := as.numeric(difftime(fin, ini, units = "hours"))]
  v <- v[visitados >= 10 & horas > 0.25 & horas < 14]   # viajes con recorrido medible
  v[, ritmo := visitados / horas]

  por_turno <- v[, .(viajes = .N, prom_horas = median(horas), prom_visitados = as.numeric(median(visitados)),
                     prom_ritmo = median(ritmo)), by = Turno]

  pc <- v[, .(n = .N, ritmo = median(ritmo), visitados = as.numeric(median(visitados))), by = .(Circuito_corto, Turno)][n >= min_viajes]
  noc <- pc[Turno == "Nocturno", .(Circuito_corto, ritmo_noc = ritmo, vis_noc = visitados)]
  par <- noc[pc[Turno != "Nocturno"], on = "Circuito_corto", nomatch = 0]
  factores <- par[, .(
    circuitos_pareados  = .N,
    factor_ritmo        = median(ritmo / ritmo_noc),
    factor_visitados    = median(visitados / vis_noc),
    p_valor_ritmo       = if (.N >= 5) suppressWarnings(wilcox.test(ritmo, ritmo_noc, paired = TRUE)$p.value) else NA_real_
  ), by = Turno]
  factores <- rbind(data.table(Turno = "Nocturno", circuitos_pareados = NA_integer_, factor_ritmo = 1,
                               factor_visitados = 1, p_valor_ritmo = NA_real_), factores)
  r <- factores[por_turno, on = "Turno"]
  r[, Turno := factor(Turno, TURNOS)]
  setorder(r, Turno)
  r[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Uso de flota de la IM por turno y día de semana (todos los municipios IM),
# en la situación actual. p90 = referencia para el lugar libre.
# -----------------------------------------------------------------------------
uso_flota_actual <- function(vb, desde, hasta) {
  # vb = viajes_por_bloque(): Demanda + Oferta + C_excluido = todos los viajes IM (Otro = Fideicomiso).
  # analizados = B_101-103, CH y C_101-109 · C110_116 = circuitos de C fuera del análisis
  # quedan = analizados + C110_116: lo que sigue usando camiones si A/D/E/F/G dejan el sistema.
  grid <- grid_dia_turno(desde, hasta)
  x <- vb[bloque %in% c("Demanda", "Oferta", "C_excluido"),
          .(total_IM = .N, analizados = sum(bloque == "Demanda"), C110_116 = sum(bloque == "C_excluido"),
            AG = sum(bloque == "Oferta")),
          by = .(Fecha, Turno)][grid, on = .(Fecha, Turno)]
  x[is.na(total_IM), `:=`(total_IM = 0L, analizados = 0L, C110_116 = 0L, AG = 0L)]
  x[, quedan := analizados + C110_116]
  x[, dia_semana := dia_semana(Fecha)]
  r <- x[, .(
    IM_media = mean(total_IM), IM_p90 = as.numeric(quantile(total_IM, 0.9, names = FALSE)), IM_max = as.numeric(max(total_IM)),
    analizados_media = mean(analizados), analizados_p90 = as.numeric(quantile(analizados, 0.9, names = FALSE)),
    C110_116_media = mean(C110_116),
    quedan_media = mean(quedan), quedan_p90 = as.numeric(quantile(quedan, 0.9, names = FALSE)),
    AG_media = mean(AG), AG_p90 = as.numeric(quantile(AG, 0.9, names = FALSE))
  ), by = .(Turno, dia_semana)]
  r[, Turno := factor(Turno, TURNOS)]
  setorder(r, Turno, dia_semana)
  r[, Turno := as.character(Turno)][]
}

# -----------------------------------------------------------------------------
# Lugar libre por turno y día con la flota disponible (número o planilla).
#   situacion "actual":    todos los municipios IM siguen operando
#   situacion "escenario": A/D/E/F/G dejan el sistema (quedan los analizados y C_110-C_116)
#   turnos_por_camion = 1: un camión usado de noche no sirve ese día de día
#   El sábado no hay turno nocturno: no existe esa fila ni aporta lugar libre.
# Usa el p90 del uso para no contar como libre lo que se usa en días cargados.
# -----------------------------------------------------------------------------
lugar_libre <- function(uso, flota, reserva, turnos_por_camion, situacion) {
  u <- disponibles_tabla(flota, reserva)[copy(uso), on = .(Turno, dia_semana)]
  u[, usado := if (situacion == "actual") IM_p90 else quedan_p90]
  noche <- u[Turno == "Nocturno", .(dia_semana, usado_noche = usado)]
  u <- noche[u, on = "dia_semana"]
  u[is.na(usado_noche), usado_noche := 0]   # sábado: sin turno nocturno
  u[, libre := if (turnos_por_camion >= 2) pmax(0, disp - usado)
               else fifelse(Turno == "Nocturno", pmax(0, disp - usado), pmax(0, disp - usado - usado_noche))]
  u[, Turno := factor(Turno, TURNOS)]
  setorder(u, Turno, dia_semana)
  u[, .(Turno = as.character(Turno), dia_semana, flota_disponible = disp, usado_p90 = usado, libre)]
}

# -----------------------------------------------------------------------------
# Escenario de frecuencia: lleva cada circuito analizado con menos de
# `frecuencia_objetivo` servicios semanales a ese valor. La necesidad se mide
# en camiones-turno nocturnos (camiones_por_servicio de meta_frecuencia); lo
# que no entra de noche pasa a Matutino y luego a Vespertino, dividido por el
# factor de productividad de ese turno (de día un camión rinde menos).
# -----------------------------------------------------------------------------
escenario_frecuencia <- function(frecuencia, libre, factores, frecuencia_objetivo) {
  necesidad <- necesidad_frecuencia(frecuencia, frecuencia_objetivo)
  circuitos <- sum(frecuencia$frecuencia_actual_semanal < frecuencia_objetivo)
  cbind(data.table(frecuencia_objetivo, circuitos_a_subir = circuitos), asignar_en_flota(necesidad, libre, factores))
}

necesidad_frecuencia <- function(frecuencia, frecuencia_objetivo) {
  sum(pmax(0, frecuencia_objetivo - frecuencia$frecuencia_actual_semanal) * frecuencia$camiones_por_servicio)
}

# -----------------------------------------------------------------------------
# Asigna una necesidad semanal dentro del lugar libre de la flota.
#   necesidad_noct: camiones-turno medidos con productividad nocturna; va primero
#     a la noche, lo que no entra a Matutino y luego a Vespertino, dividido por
#     el factor de productividad de ese turno.
#   fijo_mat / fijo_vesp: camiones-turno que ya son diurnos (p. ej. completar lo
#     asignado en viajes diurnos); ocupan su turno antes que lo anterior.
# Lo no cubierto se expresa en equivalentes nocturnos.
# -----------------------------------------------------------------------------
asignar_en_flota <- function(necesidad_noct, libre, factores, fijo_mat = 0, fijo_vesp = 0) {
  libre_sem <- libre[, .(libre = sum(libre)), by = Turno]
  lib <- function(t) libre_sem[Turno == t, libre]
  fac <- function(t) factores[Turno == t, factor_visitados]

  fm <- min(fijo_mat, lib("Matutino")); fv <- min(fijo_vesp, lib("Vespertino"))
  resto_fijo <- (fijo_mat - fm) * fac("Matutino") + (fijo_vesp - fv) * fac("Vespertino")
  lib_m <- lib("Matutino") - fm; lib_v <- lib("Vespertino") - fv

  noche <- min(necesidad_noct, lib("Nocturno")); resto <- necesidad_noct - noche
  mat   <- min(resto / fac("Matutino"), lib_m);  resto <- resto - mat * fac("Matutino")
  vesp  <- min(resto / fac("Vespertino"), lib_v); resto <- resto - vesp * fac("Vespertino")

  necesidad <- necesidad_noct + fijo_mat * fac("Matutino") + fijo_vesp * fac("Vespertino")
  sin_cubrir <- resto + resto_fijo
  data.table(
    necesidad_eq_nocturno = necesidad,
    camiones_nocturno = noche, camiones_matutino = mat + fm, camiones_vespertino = vesp + fv,
    camiones_total = noche + mat + fm + vesp + fv,
    sin_cubrir_eq_nocturno = sin_cubrir,
    pct_cubierto = if (necesidad > 0) 1 - sin_cubrir / necesidad else 1
  )
}

# -----------------------------------------------------------------------------
# Opciones para la decisión DENTRO de la flota: camiones-turno extra por turno
# de cada opción, hoy y si A/D/E/F/G dejan el sistema. Tabla "Opciones" del
# documento. completar = salida de meta_completar_listado().
# -----------------------------------------------------------------------------
tabla_opciones_flota <- function(uso, frecuencia, completar, factores, flota, reserva,
                                 turnos_por_camion, personas_por_camion = 2) {
  cm <- function(t) completar[Turno == t, sum(camiones_extra_media)]
  cn <- cm("Nocturno"); cmat <- cm("Matutino"); cv <- cm("Vespertino")
  f5 <- necesidad_frecuencia(frecuencia, 5); f6 <- necesidad_frecuencia(frecuencia, 6)
  n5 <- sum(frecuencia$frecuencia_actual_semanal < 5); n6 <- sum(frecuencia$frecuencia_actual_semanal < 6)
  ops <- data.table(
    opcion = c("1. Mantener el nivel actual", "2. Completar lo asignado",
               "3a. Mínimo 5 servicios por semana", "3b. Mínimo 6 servicios por semana",
               "2 + 3a", "2 + 3b"),
    noct = c(0, cn, f5, f6, cn + f5, cn + f6),
    mat  = c(0, cmat, 0, 0, cmat, cmat),
    vesp = c(0, cv, 0, 0, cv, cv),
    circuitos_a_subir = c(0, 0, n5, n6, n5, n6)
  )
  r <- rbindlist(lapply(c("actual", "escenario"), function(sit) {
    lb <- lugar_libre(uso, flota, reserva, turnos_por_camion, sit)
    ops[, cbind(data.table(situacion = sit, circuitos_a_subir),
                asignar_en_flota(noct, lb, factores, mat, vesp)), by = opcion]
  }))
  setcolorder(r, c("situacion", "opcion"))
  r[, personas_turno_extra := camiones_total * personas_por_camion]
  r[, situacion := fifelse(situacion == "actual", "Hoy (todos los municipios)", "A/D/E/F/G dejan el sistema")]
  r[, flota := etiqueta_flota(flota)]
  r[, reserva := reserva]
  r[, turnos_por_camion := turnos_por_camion][]
}

# -----------------------------------------------------------------------------
# Uso de la flota por turno en un día típico con turno (promedio de los días
# indicados): camiones a la vez de toda la IM, de los circuitos analizados, de
# C_110-C_116 y de A/D/E/F/G, y
# cuántos de los camiones disponibles quedan libres hoy y sin A/D/E/F/G.
# -----------------------------------------------------------------------------
resumen_flota_turno <- function(uso, flota, reserva, dias = c("Lun", "Mar", "Mie", "Jue", "Vie")) {
  u <- disponibles_tabla(flota, reserva)[uso, on = .(Turno, dia_semana)]
  r <- u[dia_semana %in% dias, .(
    flota_disponible = mean(disp),
    IM_media = mean(IM_media), IM_p90 = mean(IM_p90),
    analizados_media = mean(analizados_media), analizados_p90 = mean(analizados_p90),
    C110_116_media = mean(C110_116_media), quedan_p90 = mean(quedan_p90),
    AG_media = mean(AG_media)
  ), by = Turno]
  r[, libre_hoy := pmax(0, flota_disponible - IM_p90)]
  r[, libre_sin_AG := pmax(0, flota_disponible - quedan_p90)]
  r[, dias_considerados := paste(dias, collapse = ", ")][]
}

# -----------------------------------------------------------------------------
# Todas las combinaciones de supuestos en una tabla.
# -----------------------------------------------------------------------------
tabla_escenarios_flota <- function(uso, frecuencia, factores, flota, reservas, turnos_por_camion,
                                   frecuencias_objetivo) {
  combos <- CJ(situacion = c("actual", "escenario"),
               reserva = reservas, turnos_por_camion = turnos_por_camion,
               frecuencia_objetivo = frecuencias_objetivo, sorted = FALSE)
  r <- combos[, {
    lb <- lugar_libre(uso, flota, reserva, turnos_por_camion, situacion)
    escenario_frecuencia(frecuencia, lb, factores, frecuencia_objetivo)[, frecuencia_objetivo := NULL]
  }, by = .(situacion, reserva, turnos_por_camion, frecuencia_objetivo)]
  r[, situacion := fifelse(situacion == "actual", "Actual (todos los municipios)", "A/D/E/F/G dejan el sistema")]
  r[, flota := etiqueta_flota(flota)]
  setcolorder(r, c("situacion", "flota", "reserva", "turnos_por_camion", "frecuencia_objetivo"))
  r[]
}

DEFINICIONES_FLOTA <- data.table(
  Concepto = c("Camiones disponibles", "Reserva", "Turnos por camión", "Lugar libre", "Situación actual",
               "Escenario", "Sábado nocturno", "Productividad diurna", "Necesidad", "Asignación",
               "pct_cubierto", "Limitaciones"),
  Definicion = c(
    "Camiones al inicio de cada turno según la planilla de operaciones (hoja Disponibilidad): media de los turnos que trabajaron en los últimos 3 meses, por turno y día de semana (redondeada hacia abajo). Reemplaza al supuesto anterior de flota fija (30 y luego 27 camiones con 10 % de reserva). La hoja Escenarios también muestra la sensibilidad con reserva extra.",
    "Fracción adicional de camiones fuera de servicio. Con la planilla es 0 en las tablas del documento, porque los camiones al inicio ya excluyen los que no están en condiciones.",
    "1 = un camión usado de noche no puede salir ese mismo día de día; 2 = puede hacer dos turnos con distinta cuadrilla. Hoy la IM hace ~58 camiones-turno por día hábil (planilla y GOL coinciden) con 21 a 27 camiones al inicio de cada turno: ~2 turnos por camión.",
    "Camiones disponibles menos el uso p90 de GOL de ese turno y día de semana (no se cuenta como libre lo que se usa en días cargados).",
    "Todos los municipios IM siguen operando: el uso incluye A/D/E/F/G.",
    "A/D/E/F/G dejan el sistema: siguen usando camiones los 35 circuitos analizados (B_101-103, CH y C_101-109, columnas analizados_*) y C_110-C_116 (C110_116_media), que están fuera del análisis pero se siguen atendiendo; quedan_* = la suma de los dos. Los turnos de A/D/E/F/G se liberan.",
    "No hay turno nocturno los sábados: no se cuenta ni como uso ni como lugar libre. La frecuencia máxima nocturna es 6 por semana.",
    "Contenedores visitados por camión-turno de día / de noche, comparando el mismo circuito (mediana entre circuitos). Refleja congestión y turnos más cortos.",
    "Camiones-turno nocturnos por semana para llevar cada circuito con menos de la frecuencia objetivo a ese valor (camiones_por_servicio × servicios que faltan).",
    "Primero la noche hasta llenar el lugar libre; lo que falta va a Matutino y después a Vespertino, dividido por su factor de productividad (de día hacen falta más camiones para lo mismo).",
    "Parte de la necesidad que entra en la flota; lo que no entra queda en sin_cubrir_eq_nocturno.",
    "Modelo semanal agregado: no arma recorridos ni horarios por circuito. Supone personal suficiente (el de A/D/E/F/G en el escenario) y que cualquier circuito se puede hacer en cualquier turno."
  )
)
