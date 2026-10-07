# Exportación a Excel del Historial de un contenedor.
#
# Lo usa el botón "Descargar Excel" de la pestaña Historial. Escribe los
# registros del período como una tabla de Excel (con filtros y filas
# alternadas), con las mismas columnas que la tabla de la app
# (registros_para_tabla y COLNAMES_REGISTROS en App.R). Las fechas van como
# fechas y el % llenado como número, así se pueden ordenar y filtrar.

generar_excel_historial <- function(archivo, gid, df) {
  t <- registros_para_tabla(df)

  # "Fecha y Hora pasaje" viene como texto ("2026-09-25 05:54:06"); en Excel
  # va como fecha y hora. Se lee en UTC para que Excel muestre la misma hora.
  pasaje <- as.POSIXct(ifelse(nzchar(t$Hora_pasaje), t$Hora_pasaje, NA),
                       format = "%Y-%m-%d %H:%M:%S", tz = "UTC")

  registros <- data.frame(
    t$Fecha,
    t$Circuito_corto,
    t$Posicion,
    t$Direccion,
    t$Levantado,
    t$Turno_levantado,
    pasaje,
    t$Id_viaje_GOL,
    t$Incidencia,
    suppressWarnings(as.numeric(t$Porcentaje_llenado)),
    t$Condicion,
    t$contenedor_activo,
    check.names = FALSE, stringsAsFactors = FALSE
  ) |> setNames(COLNAMES_REGISTROS)

  wb <- openxlsx::createWorkbook()
  hoja <- paste("GID", gid)
  openxlsx::addWorksheet(wb, hoja)
  openxlsx::writeDataTable(
    wb, hoja, registros,
    tableName = paste0("Registros_GID_", gsub("[^A-Za-z0-9]", "_", gid)),
    tableStyle = "TableStyleMedium7",  # verde, como la app
    withFilter = TRUE, bandedRows = TRUE
  )

  filas <- seq_len(nrow(registros)) + 1
  col <- function(nombre) match(nombre, COLNAMES_REGISTROS)
  openxlsx::addStyle(wb, hoja, openxlsx::createStyle(numFmt = "dd/mm/yyyy", halign = "left"),
                     rows = filas, cols = col("Fecha plan."), gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, hoja, openxlsx::createStyle(numFmt = "yyyy-mm-dd hh:mm:ss", halign = "left"),
                     rows = filas, cols = col("Fecha y Hora pasaje"), gridExpand = TRUE, stack = TRUE)

  # "¿Levantado?" con el mismo color que en la app
  col_lev <- col("¿Levantado?")
  celda_lev <- paste0(openxlsx::int2col(col_lev), "2")
  for (valor in names(COLORES_LEVANTADO_EXCEL)) {
    openxlsx::conditionalFormatting(
      wb, hoja, cols = col_lev, rows = filas, type = "expression",
      rule = paste0(celda_lev, '="', valor, '"'),
      style = openxlsx::createStyle(fontColour = COLORES_LEVANTADO_EXCEL[[valor]], textDecoration = "bold")
    )
  }
  # % llenado = 100 resaltado en ámbar
  openxlsx::conditionalFormatting(
    wb, hoja, cols = col("% llenado"), rows = filas, rule = "==100",
    style = openxlsx::createStyle(bgFill = "#F6E8C3")
  )

  openxlsx::setColWidths(wb, hoja, cols = seq_along(COLNAMES_REGISTROS),
                         widths = c(12, 10, 9, 34, 12, 11, 20, 10, 26, 10, 30, 8))
  openxlsx::freezePane(wb, hoja, firstRow = TRUE)
  openxlsx::saveWorkbook(wb, archivo, overwrite = TRUE)
  invisible(archivo)
}

COLORES_LEVANTADO_EXCEL <- c("Sí" = COL_LEVANTADO, "No" = COL_INCIDENCIA, "No pasó" = COL_SIN_REGISTRO)
