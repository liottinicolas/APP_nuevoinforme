# Instructivo: actualizar y publicar la app "Informe de llenado"

App publicada: <https://datoseindicadores.shinyapps.io/App_informe_llenado/>

> **¿La va a actualizar otra persona desde su propia PC, sin este proyecto?**
> No sigas este instructivo. Armá un paquete independiente (carpeta + `.zip` con la
> app, los `.rds` y un script) y mandale el `.zip`:
>
> ```r
> source("vistas/App_informe_llenado/armar_paquete.R")
> armar_paquete()   # deja App_informe_llenado_paquete.zip en el Escritorio
> ```
>
> Adentro tiene su propio `LEEME.md`. Esa forma publica la app con los datos adentro
> y no usa OneDrive ni GitHub. Al volver, publicá desde acá como siempre y la app
> vuelve a leer los datos de GitHub.
>
> **Para que el zip lleve el token de shinyapps.io** (así la otra persona no lo pega):
> copiá `vistas/App_informe_llenado/token_shinyapps_EJEMPLO.R` como
> `token_shinyapps.R` en la misma carpeta, reemplazá la última línea por el comando
> de shinyapps.io (Tokens → Show → Show Secret → Copy to clipboard) y volvé a correr
> `armar_paquete(sobrescribir = TRUE)`. `token_shinyapps.R` está en `.gitignore`:
> el repo es **público** y ese archivo no se tiene que subir nunca. Si el zip lleva el
> token, mandalo solo por un canal privado.

Este instructivo es para actualizar la app sin ayuda. Seguí los pasos en orden.

## 0. Resumen

Un solo script hace todo: baja los datos nuevos, los sube a GitHub y **vuelve a
publicar la app** con `rsconnect::deployApp`. Hay que publicar siempre: la app
publicada no toma sola los datos nuevos, recién los lee cuando se vuelve a publicar.

```r
source("vistas/App_informe_llenado/actualizar_datos_app.R")
```

**Cuánto historial muestra la app:**
- **En la web**: solo los **últimos 4 meses** (lo recorta `limpieza_datos.R`). Con más,
  shinyapps.io se queda sin memoria (1 GB) y la app se desconecta.
- **En tu PC** (`shiny::runApp(...)`, paso 3): **todo** el historial de
  `db/GOL_reportes/historico_llenadoGol.rds`.

Arriba a la derecha la app siempre dice desde y hasta qué fecha hay datos
("Datos del ... al ...").

## 1. Lo que necesitás tener (una sola vez)

Si trabajás en la PC de siempre (la del proyecto), esto ya está. Si es otra PC,
revisá cada punto.

1. **R 4.6** y **RStudio** instalados.
2. Las carpetas `APP_nuevoinforme` y `APP_nuevoinforme-data` en tu OneDrive, con los
   datos (`.rds` y CSV). Ver paso 1.2.
3. **Usuario y contraseña de la IMM** con acceso a la intranet (reportes GOL) y al
   GeoServer (`geoserver-ed.imm.gub.uy`). El script los pide en una ventana; no se
   guardan en ningún archivo.
4. **Python del proyecto** (entorno `r-reticulate` con Playwright). Se usa solo para
   descargar los reportes de levantes. Si no está, ver "Si algo falla".
5. **Permiso para escribir en GitHub** en el repositorio
   `liottinicolas/APP_nuevoinforme-data` (lo da el dueño del repo, agregándote como
   colaborador). Sin esto, los datos se actualizan en la PC pero no llegan a la app.
6. **La cuenta `datoseindicadores` de shinyapps.io configurada en la PC** (paso 1.1).

### 1.1 Configurar la cuenta de shinyapps.io (una sola vez por PC)

En la PC de siempre ya está configurada. Para comprobarlo, abrí el proyecto (paso 2.1)
y escribí en la consola:

```r
rsconnect::accounts()
```

Si aparece `datoseindicadores` con `shinyapps.io`, ya está. Si no aparece (PC nueva):

1. Conseguí el comando con el token de la cuenta `datoseindicadores`. Es el mismo
   token que usa todo el equipo. Hay dos formas:
   - pedírselo al responsable de la app por un canal privado; o
   - entrar a <https://www.shinyapps.io> con la cuenta `datoseindicadores`, ir a tu
     nombre (arriba a la derecha) → **Tokens** → **Show** → **Show Secret** →
     **Copy to clipboard**.

   El comando tiene esta forma:

   ```r
   rsconnect::setAccountInfo(name = "datoseindicadores", token = "...", secret = "...")
   ```

2. Pegalo en la consola de RStudio y apretá Enter. Queda guardado en la PC y no hay
   que repetirlo.
3. **No guardes el token ni el secret en ningún archivo del proyecto** (OneDrive y
   GitHub los ven todos). Tampoco los pegues en el código.
4. Comprobá con `rsconnect::accounts()` que ahora aparece `datoseindicadores`.

### 1.2 Tener los datos (`.rds` y CSV) en tu PC (una sola vez)

Los datos **no están en GitHub**: están solo en la carpeta de OneDrive del responsable
de la app. Son unos 850 MB. El script usa estos:

| Archivo o carpeta | Qué es |
|---|---|
| `db/GOL_reportes/historico_llenadoGol.rds` | Histórico de levantes (unos 110 MB) |
| `db/GOL_reportes/archivos_aplicados_historico_llenadoGol.rds` | Lista de CSV ya sumados al histórico (evita duplicar) |
| `archivos/GOL_reportes/` | CSV diarios de levantes. El script mira el último para saber desde qué día descargar. |
| `db/DFR/RDS/*.rds` | Contenedores activos e inactivos (se vuelven a bajar en cada corrida) |
| `UNA_POR_CIRCUITO/rds/circuitos_periodo.rds` | Frecuencia de cada circuito |
| `archivos/10393_ubicaciones/` y `db/10393_ubicaciones/` | Ubicaciones de camiones (`cargaDeDatos.R` también las procesa) |

Por eso se comparte la carpeta entera, no archivos sueltos:

1. **El responsable** comparte en OneDrive, con permiso de **edición**, las dos
   carpetas: `Trabajo IM\APP_nuevoinforme` y `Trabajo IM\APP_nuevoinforme-data`
   (clic derecho → **Compartir** → escribir el correo → **Puede editar**).
2. **Vos**, en OneDrive en el navegador → **Compartido** → en cada carpeta,
   **Agregar acceso directo a Mis archivos**. Poné **las dos en la misma carpeta**:
   `limpieza_datos.R` busca `APP_nuevoinforme-data` al lado de `APP_nuevoinforme`.
3. Esperá a que OneDrive termine de sincronizar (icono de la nube sin flechas). En el
   Explorador, clic derecho en cada carpeta → **Conservar siempre en este dispositivo**.
   Si no, OneDrive deja archivos "solo en línea" y git o R fallan al leerlos.
4. Abrí `APP_nuevoinforme.Rproj` desde esa carpeta.

Como la carpeta es compartida, lo que actualices vos también le llega al responsable de
la app. **No corran el script dos personas a la vez.**

## 2. Actualizar y publicar la app

1. Abrí el archivo `APP_nuevoinforme.Rproj` con doble clic. Se abre RStudio en la
   carpeta del proyecto.
   - La primera vez puede tardar: `renv` prepara los paquetes. Si en la consola aparece
     "One or more packages recorded in the lockfile are not installed", no es un error.
2. En la **consola** de RStudio (abajo a la izquierda), escribí y apretá Enter:

   ```r
   source("vistas/App_informe_llenado/actualizar_datos_app.R")
   ```

3. Cuando aparezca la ventana, escribí tu **usuario** y tu **contraseña de la IMM**.
   La pide dos veces: una para la intranet (paso 1) y otra para el GeoServer (paso 3).
4. Esperá. Tarda entre 10 y 25 minutos. En la consola vas a ver "PASO 1 de 5",
   "PASO 2 de 5", etc.
   - Al terminar el paso 4 tiene que decir `✅ ¡GitHub actualizado!` o
     `ℹ️ No hubo cambios en los datos`.
   - El paso 5 publica la app. Si pregunta si querés actualizar la app existente,
     contestá que sí (`Y`).
5. Al final se abre el navegador con la app y en la consola aparece
   `✅ Listo. Datos subidos y app publicada`.
6. Revisá en la app:
   - arriba a la derecha dice **"Datos del ... al ..."**: la segunda fecha tiene que
     ser la de ayer, y la primera, unos 4 meses antes;
   - el mapa muestra puntos;
   - en **Historial**, al buscar un GID aparecen datos;
   - en **Circuitos** aparece la tabla.

**De dónde salen los datos:**

| Dato en la app | Archivo en la PC | De dónde viene |
|---|---|---|
| Historial de llenado (levantes) | `db/GOL_reportes/historico_llenadoGol.rds` | Reportes GOL de la intranet (CSV diarios en `archivos/GOL_reportes/`) |
| Contenedores activos | `db/DFR/RDS/dfr_E_DF_POSICIONES_RECORRIDO.rds` | GeoServer de la IMM (capas DFR) |
| Contenedores inactivos | `db/DFR/RDS/dfr_C_DF_POSICIONES_RECORRIDO_HISTORICO.rds` | GeoServer de la IMM (capas DFR) |
| Frecuencia de cada circuito | `UNA_POR_CIRCUITO/rds/circuitos_periodo.rds` | Pipeline completo (`nuevoinforme.R`). El script mínimo usa el último que haya; cambia muy poco. |

## 3. Probar la app en tu PC (opcional)

Sirve para ver si la app funciona antes de publicar, por ejemplo si alguien cambió el código.

1. Con el proyecto abierto en RStudio, en la consola:

   ```r
   shiny::runApp("vistas/App_informe_llenado")
   ```

2. Se abre la app en una ventana. La primera carga tarda entre 1 y 2 minutos: lee el
   historial completo de `db/` y los contenedores de GitHub. Hasta entonces el mapa
   queda vacío. Arriba a la derecha vas a ver todo el período que hay en la PC.
3. Revisá lo mismo que en el punto 6 del paso 2.
4. Para cerrarla: apretá **Esc** en la consola (o el botón rojo "Stop").

## 4. Publicar solo la app, sin bajar datos

Usalo si el script se cortó en el paso 5 o si los datos ya están en GitHub y solo
falta publicar.

1. Revisá qué archivos se van a subir (esto no publica nada):

   ```r
   rsconnect::listDeploymentFiles("vistas/App_informe_llenado")
   ```

   Tienen que aparecer **solo** estos archivos:

   ```
   App.R
   fonts/BarlowSemiCondensed-Bold.ttf
   fonts/BarlowSemiCondensed-SemiBold.ttf
   fonts/OFL.txt
   informe_excel.R
   informe_pdf.R
   ```

   Si aparece una carpeta `data/`, **pará**: no publiques. Borrá o mové esa carpeta
   `vistas/App_informe_llenado/data/` (es una copia local de los datos; si se sube, la
   app queda con datos congelados).

2. Publicá:

   ```r
   rsconnect::deployApp(
     appDir      = "vistas/App_informe_llenado",
     appName     = "App_informe_llenado",
     account     = "datoseindicadores",
     forceUpdate = TRUE
   )
   ```

   Tarda entre 5 y 15 minutos (instala los paquetes en el servidor).

## 5. Si algo falla

| Mensaje o problema | Qué hacer |
|---|---|
| `Este script se corre desde la raíz del proyecto` | Cerrá RStudio, abrí `APP_nuevoinforme.Rproj` con doble clic y volvé a correr. |
| `Esta PC no tiene configurada la cuenta 'datoseindicadores'` | Hacé el paso 1.1 y volvé a correr. |
| `Se requieren credenciales de usuario y contraseña` | Cancelaste la ventana. Volvé a correr y escribí usuario y contraseña de la IMM. |
| `Falló la descarga de reportes de levante para la fecha: ...` | La intranet no respondió o la contraseña está mal. Probá entrar a la intranet desde el navegador. Si entrás bien, volvé a correr el script más tarde. |
| Error con `virtualenv_python` o `r-reticulate` | Falta el Python del proyecto. En la consola: `reticulate::virtualenv_create("r-reticulate")` y después `reticulate::virtualenv_install("r-reticulate", "playwright")`; en una terminal: `%USERPROFILE%\.virtualenvs\r-reticulate\Scripts\python -m playwright install chromium`. |
| Error 401 en el paso 3 (GeoServer) | Usuario o contraseña mal escritos, o el usuario no tiene permiso en el GeoServer. |
| `No se pudo borrar ... (probablemente OneDrive la tiene bloqueada)` | Pausá OneDrive (icono de la nube → Pausar sincronización → 2 horas) y volvé a correr. |
| `Error al sincronizar con GitHub` | Los datos quedaron bien en la PC pero no se subieron, y el script **igual publica la app** con los datos viejos. Casi siempre es falta de permiso en GitHub (punto 5 de la sección 1). En una terminal: `cd "%USERPROFILE%\OneDrive\Trabajo IM\APP_nuevoinforme-data"` y `git push`. Si pide usuario, entrá con la cuenta de GitHub que tiene permiso. Después publicá de nuevo (paso 4). |
| `unable to append ... Invalid argument` (git) | Lo causa OneDrive. En el Explorador de archivos, clic derecho en la carpeta `APP_nuevoinforme-data` → **Conservar siempre en este dispositivo**, y volvé a correr. |
| La app publicada no muestra los datos nuevos | Revisá en <https://github.com/liottinicolas/APP_nuevoinforme-data/commits> que haya un commit de hoy. Si está, publicá de nuevo (paso 4). Si no está, mirá la fila `Error al sincronizar con GitHub`. |
| La app publicada muestra un error gris o no carga | En <https://www.shinyapps.io> → Applications → `App_informe_llenado` → **Logs**. Si el problema empezó después de un cambio de código, volvé a publicar la versión anterior del código. |
| El paso 5 (`deployApp`) falla instalando un paquete | Copiá el mensaje de error y guardalo. No cambies el código. Volvé a intentar el paso 4 más tarde: a veces es un problema momentáneo del servidor. |

## 6. Qué archivos importan (y cuáles no tocar)

Dentro de `vistas/App_informe_llenado/`:

| Archivo | Para qué sirve | ¿Se sube con `deployApp`? |
|---|---|---|
| `App.R` | La app (pantallas, mapa, tablas) | Sí |
| `informe_pdf.R`, `informe_excel.R` | Descargas del Historial en PDF y Excel | Sí |
| `fonts/` | Tipografía del PDF | Sí |
| `rsconnect/` | Dice a qué app de shinyapps.io se publica. **No borrar.** | No (lo usa `deployApp`) |
| `.rscignore` | Lista de archivos que `deployApp` no sube | No |
| `actualizar_datos_app.R` | El script de este instructivo | No |
| `limpieza_datos.R` | Sube los datos a GitHub (lo llama `actualizar_datos_app.R`) | No |
| `INSTRUCTIVO.md` | Este archivo | No |
| `App_v2.R`, `perfilado_datos.R`, `documentacion_analisis.md` | Respaldo y documentación. No hacen falta. | No |
