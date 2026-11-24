# App "Informe de llenado": cómo actualizarla

App publicada: <https://datoseindicadores.shinyapps.io/App_informe_llenado/>

Esta carpeta tiene todo lo necesario para actualizar los datos de la app y volver a
publicarla. No necesitás OneDrive, GitHub ni el resto del proyecto.

> **Cuánto historial muestra la app:**
> - **En la web** (publicada): solo los **últimos 4 meses**. Con más, el servidor se
>   queda sin memoria y la app se desconecta.
> - **En esta PC** (`shiny::runApp("app")`, paso 3): **todo** el historial de
>   `datos/historico_llenado.rds`.
>
> Arriba a la derecha la app siempre dice desde y hasta qué fecha hay datos
> ("Datos del ... al ...").

## Qué hay en la carpeta

| Carpeta o archivo | Qué es |
|---|---|
| `App_informe_llenado_paquete.Rproj` | Abre todo en RStudio. **Empezá siempre por acá.** |
| `actualizar_y_publicar.R` | El script que hace todo (paso 2) |
| `instalar_paquetes.R` | Instala lo que necesita R (una sola vez) |
| `datos/` | Los datos (`.rds`), con el historial completo. El script los actualiza solo. **No borrar.** |
| `app/` | La app que se publica. `app/rsconnect/` indica a qué app se publica: **no borrar.** |
| `descargas/` | El programa que baja los levantes de la intranet y los CSV que va bajando |
| `funciones/` | Código que usa el script. No hace falta abrirlo. |

## 1. Preparar la PC (una sola vez)

### 1.1 Instalar R y RStudio

1. **R** (4.5 o más nuevo): <https://cran.r-project.org/bin/windows/base/>
2. **RStudio**: <https://posit.co/download/rstudio-desktop/>
3. **Python**: ver el paso 1.2.

### 1.2 Instalar Python (paso a paso)

Python se usa solo para el programa que baja los levantes de la intranet.

**Antes de instalar, fijate si ya está:**

1. Abrí **PowerShell**: menú Inicio → escribí `PowerShell` → Enter.
2. Escribí esto y apretá Enter:

   ```powershell
   py --version
   ```

3. Si aparece algo como `Python 3.12.5` (3.10 o más nuevo), **ya está instalado**:
   pasá al paso 1.3. Si dice que no reconoce `py`, o la versión es más vieja que
   3.10, seguí con la instalación.

**Instalación:**

1. Entrá a <https://www.python.org/downloads/> y apretá el botón amarillo
   **"Download Python 3.x.x"**. Se baja un archivo `python-3.x.x-amd64.exe`.
2. Abrí ese archivo (doble clic en la carpeta Descargas).
3. En la **primera pantalla** del instalador, **antes de apretar nada más**:
   - marcá abajo **"Add python.exe to PATH"** (es lo más importante);
   - si aparece **"Use admin privileges when installing py.exe"** y no tenés
     permisos de administrador en la PC, **desmarcalo**.
4. Apretá **"Install Now"** (instalación normal). No hace falta "Customize".
5. Esperá a que termine. Si al final aparece **"Disable path length limit"**, apretalo
   (si pide administrador y no tenés, no pasa nada: ignoralo).
6. Apretá **"Close"**.
7. **Cerrá PowerShell si estaba abierto** y abrilo de nuevo (si no, no ve el Python
   recién instalado). Comprobá:

   ```powershell
   py --version
   ```

   Tiene que mostrar la versión. Si dice que no reconoce `py`, probá con
   `python --version`. Si tampoco anda, reiniciá la PC y probá otra vez.

**Si la PC es de la IMM y no te deja instalar** (pide contraseña de administrador o
está bloqueado): pedí a Informática que instale **Python 3.12** "con la opción Add
python.exe to PATH". También puede servir instalarlo desde **Microsoft Store**
(buscar "Python 3.12"), que no pide administrador.

### 1.3 Instalar Playwright (lo usa el programa que baja los levantes)

En **PowerShell** corré estos dos comandos, uno por vez (cada uno tarda un par de
minutos):

```powershell
py -m pip install playwright
```

```powershell
py -m playwright install chromium
```

El primero instala Playwright; el segundo baja el navegador que usa para entrar a la
intranet. Si `py` no anda pero `python` sí, usá `python` en lugar de `py` en los dos.
Si sale un error de permisos, agregá `--user` al primero:
`py -m pip install --user playwright`.

### 1.4 Instalar los paquetes de R y configurar shinyapps.io

1. Abrí `App_informe_llenado_paquete.Rproj` con doble clic. Se abre RStudio.
2. En la **consola** (abajo a la izquierda) escribí y apretá Enter:

   ```r
   source("instalar_paquetes.R")
   ```

   Tarda unos minutos. Tiene que terminar con `✅ Están todos los paquetes.`

3. **Si en la carpeta hay un archivo `token_shinyapps.R`, salteá este punto y el 4:**
   el script configura la cuenta solo la primera vez que lo corrés. Ese archivo es
   secreto: no lo compartas ni lo subas a ningún lado.

   Si no está, pegá en la consola el comando con el token de shinyapps.io que te
   pasaron y apretá Enter. Tiene esta forma:

   ```r
   rsconnect::setAccountInfo(name = "datoseindicadores", token = "...", secret = "...")
   ```

   Queda guardado en la PC. **No lo guardes en ningún archivo** ni lo pegues en el código.
4. Comprobá que quedó bien:

   ```r
   rsconnect::accounts()
   ```

   Tiene que aparecer `datoseindicadores` y `shinyapps.io`.

## 2. Actualizar y publicar la app (cada vez)

1. Abrí `App_informe_llenado_paquete.Rproj` con doble clic.
2. En la consola:

   ```r
   source("actualizar_y_publicar.R")
   ```

3. Escribí tu **usuario** y tu **contraseña de la IMM** cuando aparezca la ventana.
   Se usan para la intranet y el GeoServer. No se guardan.
4. Esperá. En la consola vas a ver "PASO 1 de 5", "PASO 2 de 5", etc.:
   1. Baja de la intranet los levantes que faltan, uno por día, hasta ayer.
   2. Los suma a `datos/historico_llenado.rds`.
   3. Baja del GeoServer los contenedores activos e inactivos.
   4. Prepara los datos para la app (los últimos 4 meses).
   5. Publica la app. Si pregunta si querés actualizar la app existente, contestá `Y`.
      Tarda entre 5 y 15 minutos.
5. Al final se abre el navegador con la app. Revisá:
   - arriba a la derecha dice **"Datos del ... al ..."**: la segunda fecha tiene que
     ser la de ayer, y la primera, unos 4 meses antes;
   - el mapa muestra puntos;
   - en **Historial**, al buscar un GID aparecen datos;
   - en **Circuitos** aparece la tabla.

Si pasaron varios días sin actualizar, no pasa nada: el script baja todos los días que
faltan.

## 3. Probar la app sin publicarla (opcional)

```r
shiny::runApp("app")
```

En esta PC la app lee **todo** el historial de `datos/historico_llenado.rds` (no solo
los 4 meses que se publican). Los contenedores salen de `app/data/`, que se arma en el
paso 4. La primera carga tarda un poco más. Para cerrarla, apretá **Esc** en la consola.

## 4. Si algo falla

| Mensaje o problema | Qué hacer |
|---|---|
| `Abrí App_informe_llenado_paquete.Rproj ...` | Cerrá RStudio, abrí el `.Rproj` con doble clic y volvé a correr. |
| `Falta configurar la cuenta 'datoseindicadores'` | Hacé el paso 1.4. |
| `Este script se corre desde RStudio` | Abrilo con RStudio, no con R solo. |
| `No encontré Python con Playwright` | Hacé los pasos 1.2 y 1.3. Si igual falla, cerrá y abrí RStudio de nuevo. |
| `Falló la descarga del ...` | La intranet no respondió o la contraseña está mal. El script sigue y publica con lo que pudo bajar. En `descargas/capturas/` hay una imagen de dónde se trabó. Probá entrar a la intranet desde el navegador y volvé a correr más tarde: retoma desde el día que falló. |
| `GeoServer: usuario o contraseña incorrectos (401)` | Revisá usuario y contraseña. Si están bien, tu usuario no tiene permiso en el GeoServer. Abrí `actualizar_y_publicar.R`, cambiá `DESCARGAR_CONTENEDORES <- TRUE` por `FALSE`, guardá y volvé a correr: se publica con los contenedores de la última vez (cambian poco). |
| `No encontré la capa ...` o `Error descargando ...` | Se dejan los contenedores de la última vez y el script sigue. |
| `No se pudo borrar app/data` | Cerrá la app si la tenés abierta (paso 3) y volvé a correr. |
| Falla el paso 5 (publicar) | Los datos quedaron actualizados. Para publicar sin volver a bajar nada, en `actualizar_y_publicar.R` poné `DESCARGAR_LEVANTES <- FALSE` y `DESCARGAR_CONTENEDORES <- FALSE`, guardá y volvé a correr. Después volvelos a `TRUE`. |
| La app publicada muestra un error gris | En <https://www.shinyapps.io> → Applications → `App_informe_llenado` → **Logs**. |
