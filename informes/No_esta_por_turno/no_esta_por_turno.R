# ------------------------------------------------------------------------------
# Programado / Visitados / Vaciados / "Contenedor No Está" por día y turno
#
# Usa la misma regla de Visitado que informes/informe_diario.R
# (funcion_df_nuevoinformediario): Levantado == "S" o Levantado == "N" con un
# motivo de `motivos_con_visita` (incluye "Contenedor No Está").
#
# Fechas: se usa la Fecha cruda de GOL. El turno Nocturno queda en el día en que
# EMPIEZA (ej. Nocturno 15/11 = noche del domingo 15 a la madrugada del lunes 16).
# NO se aplica el "Criterio de Adrián" (+1 día al Nocturno).
#
# Solo Oficina == "IM" (Fideicomiso no se muestra).
#
# Salida: un Excel en salidas/ con 3 hojas (por día y turno, por día/turno/municipio,
# y el detalle de los contenedores marcados "No Está").
# ------------------------------------------------------------------------------

library(here)
library(dplyr)
library(tidyr)
library(writexl)

# --- Parámetros ---------------------------------------------------------------
# Primer turno incluido (día + turno) y último turno incluido.
# Si fin_fecha es NA, toma hasta el último dato disponible.
inicio_fecha <- as.Date("2026-11-15")
inicio_turno <- "Nocturno"
fin_fecha    <- NA
fin_turno    <- "Nocturno"

turnos   <- c("Matutino", "Vespertino", "Nocturno")
oficinas <- c("IM")   # Solo IM: Fideicomiso queda fuera del informe
motivo_no_esta <- "Contenedor No Está"

motivos_con_visita <- c(
  "Medidas gremiales", "Habilitado tarde (Mantenimiento)", "No Levantado por Feria",
  "Sobrepeso", "Auto", "Calle Cerrada", "Tapa Bloqueda",
  "Persona en el Interior del Cont.", "Sin ticket de cantera",
  "Contenedor Roto (choque, desfonde, etc.)", "Fuego", "Contenedor No Está",
  "Contenedor Fuera de Alcance", "Contenedor Volcado", "Contenedor Cruzado",
  "Buzonera Girada", "Otros"
)

dias_es <- c("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")

# --- Datos --------------------------------------------------------------------
historico_llenado <- readRDS(here("db", "GOL_reportes", "historico_llenadoGol.rds"))
inc_col <- if ("Incidencias" %in% names(historico_llenado)) "Incidencias" else "Incidencia"

if (is.na(fin_fecha)) fin_fecha <- max(as.Date(historico_llenado$Fecha), na.rm = TRUE)

# Clave ordenable día+turno para cortar el rango en un turno exacto
clave_turno <- function(fecha, turno) {
  as.numeric(as.Date(fecha)) * 10 + match(as.character(turno), turnos)
}
desde <- clave_turno(inicio_fecha, inicio_turno)
hasta <- clave_turno(fin_fecha, fin_turno)

base <- historico_llenado %>%
  mutate(
    Fecha     = as.Date(Fecha),
    Turno     = as.character(Turno_levantado),
    Oficina   = trimws(Oficina),
    Municipio = toupper(trimws(Municipio)),
    Incid     = trimws(.data[[inc_col]]),
    Visitado  = case_when(
      Levantado == "S" ~ TRUE,
      is.na(Levantado) ~ FALSE,
      Levantado == "N" & Incid %in% motivos_con_visita ~ TRUE,
      TRUE ~ FALSE
    ),
    Vaciado = Levantado %in% "S",
    No_esta = Incid %in% motivo_no_esta,
    clave   = clave_turno(Fecha, Turno)
  ) %>%
  filter(!is.na(clave), clave >= desde, clave <= hasta, Oficina %in% oficinas)

sin_turno <- historico_llenado %>%
  filter(as.Date(Fecha) >= inicio_fecha, as.Date(Fecha) <= fin_fecha, is.na(Turno_levantado)) %>%
  nrow()
if (sin_turno > 0) message("Aviso: ", sin_turno, " registros del rango sin Turno_levantado quedan afuera.")

# --- Resumen ------------------------------------------------------------------
resumir <- function(df) {
  df %>%
    summarise(
      Programado   = n(),
      Visitados    = sum(Visitado),
      Vaciados     = sum(Vaciado),
      No_esta      = sum(No_esta),
      .groups = "drop"
    ) %>%
    mutate(Pct_No_esta_sobre_visitados = round(100 * No_esta / Visitados, 2))
}

etiquetar <- function(df) {
  df %>%
    mutate(
      Dia   = dias_es[as.POSIXlt(Fecha)$wday + 1],
      Turno = factor(Turno, levels = turnos)
    ) %>%
    relocate(Dia, .after = Fecha)
}

tabla_dia_turno <- base %>%
  group_by(Fecha, Turno) %>%
  resumir() %>%
  etiquetar() %>%
  arrange(Fecha, Turno) %>%
  select(Fecha, Dia, Turno, Programado, Visitados, Vaciados, No_esta,
         Pct_No_esta_sobre_visitados)

# Fila de total del período
total_periodo <- base %>%
  resumir() %>%
  mutate(Fecha = as.Date(NA), Dia = "TOTAL PERÍODO", Turno = NA) %>%
  select(names(tabla_dia_turno))

tabla_dia_turno <- bind_rows(tabla_dia_turno, total_periodo)

tabla_dia_turno_municipio <- base %>%
  group_by(Fecha, Turno, Municipio) %>%
  resumir() %>%
  etiquetar() %>%
  arrange(Fecha, Turno, Municipio) %>%
  select(Fecha, Dia, Turno, Municipio, Programado, Visitados, Vaciados,
         No_esta, Pct_No_esta_sobre_visitados)

detalle_no_esta <- base %>%
  filter(No_esta) %>%
  etiquetar() %>%
  arrange(Fecha, Turno, Municipio, Circuito, Posicion) %>%
  select(Fecha, Dia, Turno, Municipio, Circuito, Posicion, Direccion, gid,
         Fecha_hora_pasaje, Id_viaje_GOL)

# --- Exportar -----------------------------------------------------------------
dir.create(here("salidas"), showWarnings = FALSE)
archivo <- here("salidas", sprintf(
  "No_esta_por_turno_IM_%s_%s_a_%s_%s.xlsx",
  format(inicio_fecha, "%Y%m%d"), inicio_turno, format(fin_fecha, "%Y%m%d"), fin_turno
))

write_xlsx(
  list(
    Dia_y_turno           = tabla_dia_turno %>% mutate(Turno = as.character(Turno)),
    Dia_turno_municipio   = tabla_dia_turno_municipio %>% mutate(Turno = as.character(Turno)),
    Detalle_No_esta       = detalle_no_esta %>% mutate(Turno = as.character(Turno),
                                                       Fecha_hora_pasaje = format(Fecha_hora_pasaje, "%Y-%m-%d %H:%M"))
  ),
  archivo
)

print(as.data.frame(tabla_dia_turno))
message("Tabla exportada en: ", archivo)
