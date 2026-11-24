# =============================================================================
# Consulta puntual: promedio de levantes por día (sin domingos), oficina IM.
# Requiere `historico_llenadoGol` en memoria (lo carga nuevoinforme.R).
# Movido desde el final de nuevoinforme.R para no ejecutarlo con el orquestador.
# =============================================================================

library(dplyr)
library(lubridate)

fecha_inicio <- "2026-05-02"
fecha_fin <- "2026-10-31"

ver <- historico_llenadoGol |>
  mutate(Fecha = as.Date(Fecha)) |>
  filter(
    Levantado == "S",
    Fecha >= fecha_inicio,
    Fecha <= fecha_fin,
    wday(Fecha) != 1,   # 1 = domingo
    Oficina == "IM"
  )

ver |>
  count(Fecha, name = "levantes_dia") |>
  summarise(promedio_diario_sin_domingos = mean(levantes_dia))
