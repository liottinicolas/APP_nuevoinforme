# 📘 Guía Completa de Uso: Evaluación de Cumplimiento Intradomiciliario (GOL)

Esta guía explica en detalle cómo funciona el programa, su arquitectura, las diferentes formas de ejecutarlo (con o sin QGIS) y cómo interpretar sus resultados.

---

## 📂 1. Estructura de la Carpeta `ejecutar_evaluacion`

Toda la herramienta y sus componentes necesarios se encuentran dentro de esta misma carpeta:

```text
ejecutar_evaluacion/
│
├── 🚀 ejecutar_evaluacion.bat       # Archivo ejecutable directo para Windows (doble clic)
├── 💻 ejecutar_evaluacion_cli.py   # Script ejecutor Standalone en consola (sin abrir QGIS)
├── 📘 GUIA_USO_EVALUACION.md        # Esta guía de uso paso a paso
│
├── 📁 evaluar_cumplimiento/         # Paquete Python del algoritmo modular
│   ├── __init__.py                 # Inicializador del paquete (v0.1.15)
│   ├── metadata.txt                # Configuración de instalación como QGIS Plugin
│   ├── thresholds.py               # Cargador dinámico de mínimos por zona
│   ├── thresholds_mezclado.json    # Configuración JSON editable de mínimos por zona
│   ├── visor_downloader.py         # Descargador resiliente de la API Visor Intranet IMM
│   ├── html_report.py              # Generador del informe HTML con mapas Leaflet JS
│   └── algorithm.py                # Motor de procesamiento QGIS con optimización R-Tree (QgsSpatialIndex)
│
└── 📁 informes/                    # Carpeta por defecto donde se guardan los reportes HTML generados
```

---

## ⚙️ 2. ¿Cómo funciona el programa por dentro?

El programa evalúa la recolección de residuos urbanos analizando la presencia espacial de camiones (puntos GPS) dentro de polígonos de zonas operativas.

1. **Carga y reparación de Zonas:** Lee la capa vectorial de zonas (`.gpkg` o `.shp`), valida y repara geometrías inválidas en memoria (`makeValid()`).
2. **Indexación Espacial $O(\log N)$:** Construye un árbol **`QgsSpatialIndex` (R-Tree)** con las geometrías de las zonas. Esto permite descartar el 95%+ de las comprobaciones espaciales innecesarias, logrando velocidades **10x a 25x mayores**.
3. **Descarga o lectura GPS:** 
   - Puede leer una capa de puntos GPS ya guardada en tu equipo.
   - O bien, puede conectarse automáticamente a la **API de Visor de Intranet IMM** descargando las posiciones por bloques con **reintentos exponenciales** ante caídas de servidor y guardar el resultado en un GeoPackage.
4. **Evaluación de Mínimos por Zona:** Compara el tiempo acumulado en minutos, cantidad de puntos y movimiento contra el perfil asignado en `thresholds_mezclado.json`.
5. **Generación del Reporte HTML e Interfaz Leaflet:** Produce un informe `.html` independiente con tableros KPI, resumen de zonas y mapas interactivos con fondo OpenStreetMap/Carto.

---

## 🖱️ 3. Forma 1: Ejecutar por Doble Clic (Sin abrir QGIS)

Esta es la forma más fácil y rápida:

1. Entra en la carpeta `ejecutar_evaluacion`.
2. Haz **doble clic** en el archivo **`ejecutar_evaluacion.bat`**.
3. Se abrirá una ventana de consola que te guiará paso a paso:
   - **Paso 1:** Ingrese la ruta de su archivo de Zonas (`.gpkg` o `.shp`).
   - **Paso 2:** Indique si desea descargar posiciones de Intranet (ingresando la planilla ODS) o usar una capa GPS local de su computadora.
   - **Paso 3:** Presione `ENTER` para confirmar la carpeta de salida.
4. **¡Listo!** El programa procesará todo en segundo plano y **abrirá el informe HTML automáticamente en su navegador web** (Chrome, Edge o Firefox).

---

## 💻 4. Forma 2: Ejecutar desde la Consola de Comandos (CMD / PowerShell)

Puedes automatizar la ejecución pasando parámetros directos sin responder preguntas:

```bash
"C:\Program Files\QGIS 3.30.0\bin\python-qgis.bat" "ejecutar_evaluacion_cli.py" ^
  --zonas "C:\MisCapas\Zonas.gpkg" ^
  --gps "C:\MisCapas\GPS.gpkg" ^
  --servicio "Mezclado" ^
  --fecha-desde "2026-10-01" ^
  --fecha-hasta "2026-10-05" ^
  --html-salida "informes\Informe_Octubre.html"
```

---

## 🗺️ 5. Forma 3: Ejecutar dentro de QGIS (vía Caja de Herramientas)

Si prefieres usar la interfaz visual de QGIS:

1. Copia la subcarpeta `evaluar_cumplimiento` a la ruta de Plugins de QGIS:
   `%APPDATA%\QGIS\QGIS3\profiles\default\python\plugins\`
2. Abre QGIS.
3. En la **Caja de herramientas de procesado** (*Processing Toolbox*), busca el grupo **GOL** -> **Evaluar cumplimiento intradomiciliario**.
4. Selecciona las capas del mapa en los menús desplegables y presiona **Ejecutar**.

---

## 🛠️ 6. ¿Cómo cambiar los Mínimos por Zona?

No necesitas editar código Python. Simplemente abre el archivo JSON:
`evaluar_cumplimiento/thresholds_mezclado.json`

Puedes modificar los minutos requeridos, puntos totales o puntos en movimiento para cualquier ID de zona:

```json
{
  "zonas": {
    "7": { "nombre": "COMPLEJO HABITACIONAL TOBAS", "minutos": 3, "puntos_totales": 15, "puntos_movimiento": 4 },
    "17": { "nombre": "CARRASCO 1", "minutos": 60, "puntos_totales": 20, "puntos_movimiento": 10 }
  }
}
```

---

## 📊 7. ¿Dónde se ven los Resultados?

- **Informe HTML Interactivo:** Se guarda en la carpeta `informes/` y se abre automáticamente en el navegador.
- **Interactividad en el HTML:** Puedes hacer clic en los enlaces a mapas Leaflet, filtrar por turno/fecha/zona, cambiar selecciones de validación manual, exportar a PDF o descargar datos en CSV y JSON.

---

## 📊 8. Forma 4: Ejecutar directamente desde R / RStudio

Para integrarlo directamente en tus scripts de R:

```R
source("scripts/ejecutar_evaluacion.R")

# Ejemplo 1: Evaluando con capas locales en tu equipo
ejecutar_evaluacion(
  capa_zonas = "C:/MisCapas/Zonas.gpkg",
  capa_gps = "C:/MisCapas/GPS_Puntos.gpkg",
  servicio = "Mezclado",
  fecha_desde = "2026-10-01",
  fecha_hasta = "2026-10-05"
)

# Ejemplo 2: Descargando de la API Visor Intranet automáticamente
ejecutar_evaluacion(
  capa_zonas = "C:/MisCapas/Zonas.gpkg",
  descargar_gps = TRUE,
  ods_matriculas = "C:/MisCapas/Matriculas.ods",
  gps_descargado_gpkg = "C:/MisCapas/GPS_Descargado.gpkg",
  servicio = "Mezclado",
  fecha_desde = "2026-10-01",
  fecha_hasta = "2026-10-05"
)
```

