Sys.setenv(FECHA_REPORTE = "2026-02-17")
reticulate::py_run_string('import os; print("PYTHON LEE:", os.environ.get("FECHA_REPORTE"))')
