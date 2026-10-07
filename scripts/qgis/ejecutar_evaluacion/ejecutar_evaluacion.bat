@echo off
TITLE Preinforme de Cumplimiento Intradomiciliario (Standalone)
COLOR 0A

SET QGIS_PATH=C:\Program Files\QGIS 3.30.0\bin\python-qgis.bat
SET SCRIPT_DIR=%~dp0

echo ======================================================================
echo  EJECUCIÓN DE EVALUACIÓN DE CUMPLIMIENTO INTRADOMICILIARIO (GOL)
echo ======================================================================
echo.

"%QGIS_PATH%" "%SCRIPT_DIR%ejecutar_evaluacion_cli.py" %*

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ======================================================================
    echo  PROCESO FINALIZADO CON ÉXITO.
    echo ======================================================================
) else (
    echo.
    echo [X] Ocurrió un error durante la ejecución. Verifique los mensajes arriba.
)

pause
