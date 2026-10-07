# Camiones usados y contenedores levantados por dia, circuitos CH_101 a CH_109,
# ultimo mes. Solo cuentan los viajes con al menos un contenedor levantado:
# camiones = Id_viaje_GOL distintos entre las filas con Levantado == "S";
# contenedores = cantidad de esas filas.
obtener_camiones_ch <- function(historico_llenado, fecha_fin = Sys.Date() + 1) {
	fecha_inicio <- seq(fecha_fin, by = "-1 month", length.out = 2)[2]

	levantados <- historico_llenado[
		historico_llenado$Circuito_corto %in% sprintf("CH_%d", 101:109) &
			historico_llenado$Levantado %in% "S" &
			historico_llenado$Fecha >= fecha_inicio &
			historico_llenado$Fecha < fecha_fin,
		c("Fecha", "Id_viaje_GOL", "gid")
	]

	resultado <- merge(
		aggregate(Id_viaje_GOL ~ Fecha, data = levantados, FUN = function(x) length(unique(x))),
		aggregate(gid ~ Fecha, data = levantados, FUN = length),
		by = "Fecha"
	)
	names(resultado) <- c("Fecha", "camiones_usados", "contenedores_levantados")
	resultado[order(resultado$Fecha), ]
}

historico_llenado <- readRDS("C:/Users/im4445285/OneDrive/Trabajo IM/APP_nuevoinforme/db/GOL_reportes/historico_llenadoGol.rds")

camiones_ch <- obtener_camiones_ch(historico_llenado)

writexl::write_xlsx(
	camiones_ch,
	sprintf("C:/Users/im4445285/OneDrive/Trabajo IM/APP_nuevoinforme/Pedidos/camiones_ch_101_109_%s.xlsx", Sys.Date())
)

# verrr <- historico_llenado %>% 
#   filter(Circuito_corto %in% sprintf("CH_%d", 101:109)) %>% 
#   filter(Fecha >= "2026-09-05") %>% 
#   group_by(Id_viaje_GOL) %>% 
#   summarise(total = n())
