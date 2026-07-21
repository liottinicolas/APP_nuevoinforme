import os
import sys
import time
from datetime import datetime
from playwright.sync_api import sync_playwright

# Forzar encoding UTF-8 en consolas Windows
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

# Configuración de URLs y Rutas
URL_BASE = "https://intranet.imm.gub.uy/app/limpieza-gestion-operativa/"
DIR_SCRIPT = os.path.dirname(os.path.abspath(__file__))

# Determinar la fecha a descargar (primer argumento, ej: YYYY-MM-DD)
if len(sys.argv) > 1 and sys.argv[1].strip() != "":
    FECHA_DESCARGA = sys.argv[1].strip()
    print(f"📅 Fecha recibida por parámetro: {FECHA_DESCARGA}")
else:
    FECHA_DESCARGA = datetime.now().strftime("%Y-%m-%d")
    print(f"📅 Fecha por defecto (hoy): {FECHA_DESCARGA}")

# Credenciales (argumentos o variables de entorno)
if len(sys.argv) > 3 and sys.argv[2].strip() != "" and sys.argv[3].strip() != "":
    USUARIO = sys.argv[2].strip()
    CONTRASENA = sys.argv[3].strip()
    print("🔑 Credenciales recibidas por parámetros de línea de comandos.")
else:
    USUARIO = os.environ.get("APEX_USUARIO")
    CONTRASENA = os.environ.get("APEX_CONTRASENA")
    print("🔑 Credenciales leídas de variables de entorno.")

# Mapeo de nombres de meses en español para la carpeta
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
    dia_num = partes[2]
    nombre_mes_folder = MESES_ESPANOL.get(mes_num, f"{mes_num}_mes")
    # Para evitar que el desfase de zona horaria de JS reste un día al usar ISO (YYYY-MM-DD),
    # usamos el formato MM/DD/YYYY que se parsea en hora local de forma correcta.
    FECHA_FORMATEADA_WEB = f"{mes_num}/{dia_num}/{anio}"
except Exception:
    anio = datetime.now().strftime("%Y")
    mes_num = datetime.now().strftime("%m")
    nombre_mes_folder = MESES_ESPANOL.get(mes_num, f"{mes_num}_mes")
    FECHA_FORMATEADA_WEB = datetime.now().strftime("%m/%d/%Y")

# Carpetas de destino
CARPETA_DESTINO = os.path.join(DIR_SCRIPT, "GOL_reportes", anio, nombre_mes_folder)
CARPETA_CAPTURAS = os.path.join(DIR_SCRIPT, "capturas")
RUTA_CSV_FINAL = os.path.join(CARPETA_DESTINO, f"{FECHA_DESCARGA}.csv")

def descargar_reporte_limpieza():
    if not USUARIO or not CONTRASENA:
        print("❌ Error: No se definieron credenciales (APEX_USUARIO y APEX_CONTRASENA).")
        sys.exit(1)

    # Crear carpetas si no existen
    os.makedirs(CARPETA_DESTINO, exist_ok=True)
    os.makedirs(CARPETA_CAPTURAS, exist_ok=True)

    with sync_playwright() as p:
        print("🚀 Iniciando navegador...")
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(locale="es-UY")
        page = context.new_page()

        print(f"🔗 Navegando a la app: {URL_BASE}")
        page.goto(URL_BASE)
        page.wait_for_load_state("networkidle")

        # 1. Hacer clic en "Iniciar sesión"
        login_btn = page.locator("button[data-testid='login-button-popup']")
        if login_btn.count() > 0:
            try:
                print("🖱️ Haciendo clic en 'Iniciar sesión' y esperando el popup...")
                with context.expect_page(timeout=15000) as new_page_info:
                    login_btn.first.click()
                popup_page = new_page_info.value
                popup_page.wait_for_load_state("networkidle")
            except Exception as e:
                print(f"❌ Error al abrir el popup de login: {e}")
                page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_popup.png"))
                context.close()
                browser.close()
                sys.exit(1)
        else:
            print("⚠️ No se encontró el botón de Iniciar sesión. Tomando captura...")
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_inicio.png"))
            context.close()
            browser.close()
            sys.exit(1)

        # 2. Hacer clic en "Funcionarios" en el popup si se solicita selección de perfil
        print("⏳ Esperando selección de perfil (Funcionario/Empresa) o formulario SSO en el popup...")
        selector_perfil = "#icon-1, #icon-3, [data-testid='login-page-sign-in-with-Funcionarios'], [data-testid*='Funcionarios'], button:has-text('Funcionarios')"
        selector_sso_user = "#usernameUserInput, input[name='usernameUserInput'], #username, input[name='username'], input[type='password']"
        
        try:
            popup_page.wait_for_selector(f"{selector_perfil}, {selector_sso_user}", timeout=15000)
            
            # Remover banner de cookies si tapa los elementos interactivos
            try:
                popup_page.evaluate("() => { const b = document.getElementById('cookie-consent-banner'); if (b) b.remove(); }")
            except Exception:
                pass

            # Verificar si está la pantalla de selección de perfil
            loc_perfil = popup_page.locator(selector_perfil)
            if loc_perfil.count() > 0 and loc_perfil.first.is_visible():
                print("🖱️ Haciendo clic en 'Funcionario' en el popup...")
                loc_perfil.first.click(force=True)
                popup_page.wait_for_load_state("networkidle")
            else:
                print("ℹ️ Se detectó redirección directa al login SSO (sin paso intermedio de perfil).")
        except Exception as e:
            print(f"⚠️ Advertencia al verificar el perfil ({e}). Se intentará continuar al SSO...")

        # 3. Rellenar credenciales en el SSO
        print("⏳ Esperando login SSO en el popup...")
        try:
            # Remover banner de cookies si reaparece
            try:
                popup_page.evaluate("() => { const b = document.getElementById('cookie-consent-banner'); if (b) b.remove(); }")
            except Exception:
                pass

            selector_sso_user_visible = "#usernameUserInput:visible, input[name='usernameUserInput']:visible, #username:visible, input[name='username']:visible"
            popup_page.wait_for_selector(selector_sso_user_visible, timeout=15000)
            print("🔑 Ingresando credenciales...")
            popup_page.fill(selector_sso_user_visible, USUARIO)
            popup_page.fill("#password", CONTRASENA)
            popup_page.click("#sign-in-button:visible, #loginForm button[type='submit'], button[type='submit']:visible", force=True)
            print("⏳ Enviando credenciales...")
        except Exception as e:
            print(f"❌ Error ingresando credenciales en el SSO: {e}")
            if not popup_page.is_closed():
                popup_page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_sso.png"))
            context.close()
            browser.close()
            sys.exit(1)

        # 4. Esperar redirección en la ventana principal
        print("⏳ Esperando que cargue la app en la ventana principal...")
        try:
            page.wait_for_url("**/limpieza-gestion-operativa/**", timeout=25000)
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(5000) # Tiempo adicional para render
        except Exception as e:
            print(f"❌ Timeout esperando redirección en la ventana principal: {e}")
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_redireccion.png"))
            context.close()
            browser.close()
            sys.exit(1)

        # 5. Abrir menú NL y navegar a Analytics
        print("🖱️ Abriendo menú 'NL'...")
        try:
            page.click("app-user-profile button")
            page.wait_for_selector("[role='menu'], .mat-mdc-menu-panel", timeout=10000)
            page.wait_for_timeout(1000)
            
            # Buscar la opción de Reportes
            items = page.locator("[role='menuitem'], .mat-mdc-menu-item, button[role='menuitem']").all()
            target_item = None
            for item in items:
                text = item.text_content().strip()
                if "reporte" in text.lower() or "analit" in text.lower() or "analytics" in text.lower():
                    target_item = item
                    
            if target_item:
                print(f"🖱️ Haciendo clic en: '{target_item.text_content().strip()}'")
                target_item.click()
            else:
                print("⚠️ Opción de Reportes no encontrada. Intentando clic por texto...")
                page.click("text=Reportes y Analítica")
                
            print("⏳ Esperando navegación a la vista de Analytics...")
            page.wait_for_url("**/analytics**", timeout=15000)
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(5000)
        except Exception as e:
            print(f"❌ Error al abrir menú o navegar a Analytics: {e}")
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_menu.png"))
            context.close()
            browser.close()
            sys.exit(1)

        # 6. Expandir panel "Levantes de un día"
        print("🖱️ Expandiendo sección 'Levantes de un día'...")
        try:
            page.click("text=Levantes de un día")
            page.wait_for_timeout(1500)
            # 7. Rellenar fecha de levante
            selector_fecha = "input[title='fecha de levante']"
            page.wait_for_selector(selector_fecha, timeout=10000)
            print(f"✍️ Completando fecha con: {FECHA_FORMATEADA_WEB}")
            
            # Hacer click, limpiar y presionar secuencialmente
            page.click(selector_fecha)
            page.keyboard.press("Control+A")
            page.keyboard.press("Backspace")
            page.locator(selector_fecha).press_sequentially(FECHA_FORMATEADA_WEB, delay=50)
            
            # Disparar eventos de input y change para Angular
            page.eval_on_selector(selector_fecha, "el => el.dispatchEvent(new Event('input', { bubbles: true }))")
            page.eval_on_selector(selector_fecha, "el => el.dispatchEvent(new Event('change', { bubbles: true }))")
            page.keyboard.press("Tab") # Quitar el foco del input
            page.wait_for_timeout(1000)
            
            # Capturar antes de la descarga
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_formulario_rellenado.png"))
        except Exception as e:
            print(f"❌ Error al expandir o rellenar fecha: {e}")
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_formulario.png"))
            context.close()
            browser.close()
            sys.exit(1)

        # 8. Iniciar descarga del reporte CSV
        print("⏳ Iniciando descarga de CSV...")
        try:
            btn_exportar = page.locator("mat-expansion-panel:has-text('Levantes de un día') button:has-text('Exportar CSV')")
            
            with page.expect_download(timeout=120000) as download_info:
                btn_exportar.click()
                
            download = download_info.value
            print(f"💾 Guardando archivo CSV en: {RUTA_CSV_FINAL}")
            download.save_as(RUTA_CSV_FINAL)
            print("✅ Descarga completada exitosamente!")
        except Exception as e:
            print(f"❌ Error durante la descarga del CSV: {e}")
            page.screenshot(path=os.path.join(CARPETA_CAPTURAS, "limpieza_error_descarga.png"))
            context.close()
            browser.close()
            sys.exit(1)

        context.close()
        browser.close()

if __name__ == "__main__":
    descargar_reporte_limpieza()
