import os
import sys
from datetime import datetime
from playwright.sync_api import sync_playwright

# Configuración de URLs y Rutas
URL_BASE = "https://apex.imm.gub.uy/apex/r/prod/cons-exp"
URL_INICIAL = f"{URL_BASE}/consultascsv"
QUERY_ID = "10393"  # ID de la consulta que quieres descargar (ej: 10393 o 10450)
QUERY_PARAM = "%_DU_RM_CL_%"  # Parámetro de búsqueda para la consulta

# Obtener la ruta absoluta de la carpeta 'archivos' donde reside este script
DIR_SCRIPT = os.path.dirname(os.path.abspath(__file__))

# Determinar la fecha a descargar (primer argumento)
if len(sys.argv) > 1 and sys.argv[1].strip() != "":
    FECHA_DESCARGA = sys.argv[1].strip()
    print(f"📅 Fecha recibida por parámetro: {FECHA_DESCARGA}")
else:
    FECHA_DESCARGA = datetime.now().strftime("%Y-%m-%d")
    print(f"📅 Fecha por defecto (hoy): {FECHA_DESCARGA}")

# Mapeo de nombres de meses en español
MESES_ESPANOL = {
    "01": "01_enero",
    "02": "02_febrero",
    "03": "03_marzo",
    "04": "04_abril",
    "05": "05_mayo",
    "06": "06_junio",
    "07": "07_julio",
    "08": "08_agosto",
    "09": "09_setiembre",
    "10": "10_octubre",
    "11": "11_noviembre",
    "12": "12_diciembre"
}

try:
    partes = FECHA_DESCARGA.split("-")
    anio = partes[0]
    mes_num = partes[1]
    nombre_mes_folder = MESES_ESPANOL.get(mes_num, f"{mes_num}_mes")
except Exception:
    anio = datetime.now().strftime("%Y")
    mes_num = datetime.now().strftime("%m")
    nombre_mes_folder = MESES_ESPANOL.get(mes_num, f"{mes_num}_mes")

# Carpetas de destino con estructura AAAA/MM_mes/
CARPETA_DESTINO = os.path.join(DIR_SCRIPT, f"{QUERY_ID}_ubicaciones", anio, nombre_mes_folder)
CARPETA_CAPTURAS = os.path.join(DIR_SCRIPT, "capturas")
RUTA_CSV_FINAL = os.path.join(CARPETA_DESTINO, f"{FECHA_DESCARGA}.csv")

# Credenciales (argumentos o variables de entorno)
if len(sys.argv) > 3 and sys.argv[2].strip() != "" and sys.argv[3].strip() != "":
    USUARIO = sys.argv[2].strip()
    CONTRASENA = sys.argv[3].strip()
    print("🔑 Credenciales recibidas por parámetros de línea de comandos.")
else:
    USUARIO = os.environ.get("APEX_USUARIO")
    CONTRASENA = os.environ.get("APEX_CONTRASENA")
    print("🔑 Credenciales leídas de variables de entorno.")

# Selectores CSS típicos de Oracle APEX
SELECTOR_USUARIO = "#P101_USERNAME"   # Campo de usuario en APEX
SELECTOR_PASSWORD = "#P101_PASSWORD"  # Campo de contraseña en APEX
SELECTOR_LOGIN_BTN = "button[type='submit']" # Botón de iniciar sesión

def descargar_reporte_apex():
    if not USUARIO or not CONTRASENA:
        print("❌ Error: Las variables de entorno APEX_USUARIO y APEX_CONTRASENA deben estar definidas.")
        print("Puedes definirlas en tu sesión de terminal antes de correr el script:")
        print("  Windows (PowerShell): $env:APEX_USUARIO='tu_usuario'; $env:APEX_CONTRASENA='tu_pass'")
        print("  Windows (CMD): set APEX_USUARIO=tu_usuario && set APEX_CONTRASENA=tu_pass")
        sys.exit(1)

    # Crear carpetas si no existen
    os.makedirs(CARPETA_CAPTURAS, exist_ok=True)

    print("🚀 Iniciando navegador controlado...")
    
    with sync_playwright() as p:
        # Cambiar headless=False si deseas ver lo que hace el navegador en tiempo real para depurar
        browser = p.chromium.launch(headless=True)
        
        # Crear un contexto de navegador que acepte descargas
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()
        
        print(f"🔗 Navegando a la URL inicial (lista de consultas): {URL_INICIAL}")
        page.goto(URL_INICIAL)
        page.wait_for_load_state("networkidle")
        
        # Función auxiliar para comprobar si un selector existe y es visible en pantalla
        def campo_visible(selector):
            try:
                loc = page.locator(selector)
                return loc.count() > 0 and loc.first.is_visible()
            except Exception:
                return False

        is_apex_login = campo_visible(SELECTOR_USUARIO)
        selector_sso_user = "#usernameUserInput:visible, input[name='usernameUserInput']:visible, #username:visible, input[name='username']:visible"
        is_sso = campo_visible(selector_sso_user)
        selector_generic_user = "input[type='text']:visible, input[type='email']:visible"
        is_generic_login = campo_visible(selector_generic_user) and campo_visible("input[type='password']:visible")

        if is_apex_login or is_sso or is_generic_login:
            print("🔑 Detectada pantalla de inicio de sesión...")
            try:
                page.evaluate("() => { const b = document.getElementById('cookie-consent-banner'); if (b) b.remove(); }")
            except Exception:
                pass

            if is_apex_login:
                print("-> Modo: Oracle APEX Estándar")
                page.fill(f"{SELECTOR_USUARIO}:visible", USUARIO)
                page.fill(f"{SELECTOR_PASSWORD}:visible", CONTRASENA)
                page.click("button[type='submit']:visible, #P101_LOGIN", force=True)
            elif is_sso:
                print("-> Modo: SSO Montevideo (GUB.UY)")
                page.fill(selector_sso_user, USUARIO)
                page.fill("input[type='password']:visible", CONTRASENA)
                page.click("#sign-in-button:visible, button[type='submit']:visible, input[type='submit']:visible, #loginForm button", force=True)
            else:
                print("-> Modo: Formulario de Login Genérico Detectado")
                page.fill(selector_generic_user, USUARIO)
                page.fill("input[type='password']:visible", CONTRASENA)
                page.click("button[type='submit']:visible, input[type='submit']:visible", force=True)
                
            print("⏳ Enviando credenciales y esperando redirección...")
            try:
                # Esperar a volver a la app de APEX con una sesión activa
                page.wait_for_url("**/cons-exp/**session=*", timeout=15000)
            except Exception:
                page.wait_for_load_state("networkidle")
        else:
            print("ℹ️ Sesión ya activa o redirección directa.")

        # Tomar captura de pantalla de la página de aterrizaje inicial (ej: inicio)
        page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "pantalla_inicial.png"))
        print(f"📸 Captura de la página inicial guardada como '{os.path.join(CARPETA_CAPTURAS, 'pantalla_inicial.png')}'")

        # Extraer el ID de sesión dinámico desde la URL actual
        import urllib.parse
        parsed_url = urllib.parse.urlparse(page.url)
        params = urllib.parse.parse_qs(parsed_url.query)
        session_id = params.get('session', [None])[0]

        if not session_id:
            print("❌ Error: No se pudo extraer la sesión activa de la URL:", page.url)
            sys.exit(1)
            
        print(f"🔑 Sesión activa de APEX detectada: {session_id}")

        # Navegar a la página consultascsv usando la sesión activa
        url_lista = f"{URL_BASE}/consultascsv?session={session_id}"
        print(f"🔗 Navegando a la lista de consultas: {url_lista}")
        page.goto(url_lista)
        page.wait_for_load_state("networkidle")

        # Tomar captura de la lista de consultas
        page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "pantalla_lista_consultas.png"))
        print(f"📸 Captura de la lista de consultas guardada como '{os.path.join(CARPETA_CAPTURAS, 'pantalla_lista_consultas.png')}'")

        # Buscar el enlace a la consulta específica en la lista para heredar su checksum (cs)
        selector_enlace = f"a[href*='p4_csql_id={QUERY_ID}']"
        
        try:
            print(f"⏳ Buscando enlace para QUERY_ID={QUERY_ID} en la página...")
            # Esperar a que el selector esté presente en el DOM
            page.wait_for_selector(selector_enlace, timeout=10000)
            link_locator = page.locator(selector_enlace)
            
            print(f"🖱️ Enlace encontrado. Haciendo clic...")
            link_locator.first.click()
            page.wait_for_load_state("networkidle")

            # Esperar que cargue el campo de parámetros
            print("⏳ Esperando que cargue el campo de parámetro 'f04'...")
            page.wait_for_selector("input[name='f04']", timeout=10000)

            # Guardar captura de la página de la consulta
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "pantalla_consulta.png"))
            print(f"📸 Captura de la consulta guardada como '{os.path.join(CARPETA_CAPTURAS, 'pantalla_consulta.png')}'")

            # Completar el parámetro de búsqueda
            print(f"✍️ Completando el campo de parámetros con: {QUERY_PARAM}")
            page.fill("input[name='f04']", QUERY_PARAM)
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "pantalla_consulta_rellena.png"))
            print(f"📸 Captura con campo completo guardada como '{os.path.join(CARPETA_CAPTURAS, 'pantalla_consulta_rellena.png')}'")

            # 1. Hacer clic en "Ejecutar" para procesar la consulta en el servidor
            boton_ejecutar = page.locator("#B_EJECUTAR")
            print("🖱️ Haciendo clic en el botón 'Ejecutar' para procesar la consulta...")
            boton_ejecutar.click()
            
            # 2. Esperar a que la página procese y aparezca el botón verde de "Descargar"
            print("⏳ Esperando que el servidor procese la consulta y aparezca el botón 'Descargar'...")
            # Le damos hasta 120 segundos (2 minutos) para procesar la consulta en el backend
            selector_descarga = "button:has-text('Descargar')"
            page.wait_for_selector(selector_descarga, timeout=120000)
            
            # Guardar captura de pantalla de la página lista para descargar
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "pantalla_lista_para_descargar.png"))
            print("📸 Captura guardada como 'pantalla_lista_para_descargar.png'")
            
            # 3. Hacer clic en el botón "Descargar" real para iniciar la transferencia del archivo
            boton_descargar = page.locator(selector_descarga)
            with page.expect_download(timeout=30000) as download_info:
                print("🖱️ Haciendo clic en 'Descargar' para iniciar la transferencia...")
                boton_descargar.click()

            download = download_info.value
            print(f"📥 Descarga iniciada: {download.suggested_filename}")
            
            os.makedirs(CARPETA_DESTINO, exist_ok=True)
            download.save_as(RUTA_CSV_FINAL)
            print(f"✅ Archivo guardado exitosamente en: {RUTA_CSV_FINAL}")

        except Exception as e:
            print(f"❌ Error durante el proceso: {e}")
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "pantalla_error.png"))
            print(f"📸 Se ha guardado una captura de pantalla en '{os.path.join(CARPETA_CAPTURAS, 'pantalla_error.png')}' para depuración.")
            
        finally:
            context.close()
            browser.close()

if __name__ == "__main__":
    descargar_reporte_apex()

# para ejecutar esto en la consola pongo (desde la raíz del proyecto):
# $env:APEX_USUARIO="im4445285"; $env:APEX_CONTRASENA="Nico1919*"; python archivos/descargar_datos_10393_ubicaciones.py
# POR AHORA SOLO ME DESCARGA UBICACIONES
