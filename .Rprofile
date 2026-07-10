# Configurar ruta limpia de virtualenvs para reticulate sin espacios ni OneDrive
user_profile <- Sys.getenv("USERPROFILE")
if (user_profile != "") {
  sys_virtualenvs <- file.path(user_profile, ".virtualenvs")
  sys_virtualenvs <- gsub("\\\\", "/", sys_virtualenvs)
  Sys.setenv(WORKON_HOME = sys_virtualenvs)
  
  venv_python <- file.path(sys_virtualenvs, "r-reticulate", if (.Platform$OS.type == "windows") "Scripts/python.exe" else "bin/python")
  if (file.exists(venv_python)) {
    Sys.setenv(RETICULATE_PYTHON = venv_python)
  }
}

source("renv/activate.R")
