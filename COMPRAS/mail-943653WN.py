"""
GUÍA DE USO — Envío de correos por el webmail de la IM (Zimbra)
================================================================

Cada ejecución pide el código 2FA de la app de autenticación (una vez por llamada).

1) ELEGIR DESDE QUÉ CUENTA SALE EL CORREO
   Pasá `identidad_id` + `remitente` + `nombre_remitente` de la misma fila.
   ¡Ojo! Zimbra usa la dirección de la IDENTIDAD; si el id no coincide con el
   remitente, el correo sale igual desde la cuenta del id.

   | Identidad            | identidad_id                          | remitente                               | nombre_remitente             |
   |----------------------|---------------------------------------|-----------------------------------------|------------------------------|
   | Contable Limpieza    | 143fc742-ea5e-49ab-b5dd-a475a4d17ac4  | contable.limpieza@imm.gub.uy            | Contable Limpieza            |
   | No domiciliarios     | 9835e787-818b-4ab5-9d38-50fe40b662a5  | recoleccion.nodomiciliarios@imm.gub.uy  | recoleccion no domiciliarios |
   | Nicolás (default)    | f8c2e9a7-3d51-4b5a-a283-d1abed4b118b  | nicolas.liotti@imm.gub.uy               | Nicolas Liotti               |

   Si no pasás identidad_id, sale desde tu cuenta (nicolas.liotti).
   Para ver/actualizar esta lista:  python -c "import mail; mail.listar_identidades()"

2) ELEGIR LA FUNCIÓN
   - enviar_correo_individual(destinatarios=[...], ...)
       Un correo SEPARADO por cada dirección: nadie ve a quién más se le mandó.
       Es la opción recomendada para envíos a varias personas.
   - enviar_correo(destinatario=[...], cc=[...], cco=[...], ...)
       UN solo correo: los de `destinatario` y `cc` se ven entre sí; los de `cco` no.

3) PARÁMETROS DEL MENSAJE
   - asunto:  texto del asunto.
   - cuerpo:  texto plano, o HTML si ponés es_html=True (ej. "<p>Hola <strong>...</strong></p>").
   - pausa_segundos (solo enviar_correo_individual, por defecto 5): espera entre un correo
     y el siguiente para no disparar límites anti-spam. Ej: pausa_segundos=10.
     Tiempo total aprox. = cantidad de correos × pausa (35 correos × 5 s ≈ 3 min).

   - destinatarios desde archivo:  destinatarios=leer_correos()  lee COMPRAS/correos.txt
     (una dirección por línea; saca espacios, duplicados y líneas sin "@").
     Para otro archivo:  leer_correos("otra_lista.txt")
     Para probar:        leer_correos("correosPrueba.txt")  (¡que tenga solo tus direcciones!)

4) FORMATO DEL CUERPO HTML (tamaño de letra, colores, etc.)
   Usá estilos INLINE (style="..." dentro de cada etiqueta): Gmail/Outlook suelen
   ignorar los bloques <style>, pero respetan el style inline.
   El style del <body> aplica a todo el correo; en un <p>/<strong> lo cambiás solo para ese texto.

   Ejemplo:
       <html>
         <body style="font-family: Arial, sans-serif; font-size: 16px; color: #222; line-height: 1.5;">
           <p>A quien corresponda,</p>
           <p>Solicitamos ... del mes de <strong style="color: #0b5394;">Setiembre del 2026</strong>.</p>
           <p style="font-size: 18px; font-weight: bold;">Plazo: 15 de octubre</p>
           <p>Desde ya, gracias.</p>
           <p style="font-size: 14px; color: #666;">Contable Limpieza<br>Intendencia de Montevideo</p>
         </body>
       </html>

   | Querés...                  | Poné en style="..."                                        |
   |----------------------------|------------------------------------------------------------|
   | Letra más grande           | font-size: 16px;  (normal ≈ 13-14px; 18-20px para destacar) |
   | Cambiar la fuente          | font-family: Arial, sans-serif;                            |
   | Color de texto             | color: #0b5394;  (o color: red;)                           |
   | Negrita                    | font-weight: bold;  o la etiqueta <strong>...</strong>     |
   | Cursiva                    | etiqueta <em>...</em>                                      |
   | Subrayado                  | text-decoration: underline;                                |
   | Más espacio entre líneas   | line-height: 1.5;                                          |
   | Resaltado de fondo         | background-color: #fff2cc;                                 |
   | Centrar                    | text-align: center;                                        |

   Otras etiquetas útiles:
     <br>                                   salto de línea dentro de un párrafo
     <h2 style="font-size: 20px;">...</h2>  título
     <ul><li>Uno</li><li>Dos</li></ul>      lista con viñetas
   Acordate de es_html=True, y probá primero con correosPrueba.txt para ver cómo queda.

5) CÓMO EJECUTAR (desde la carpeta COMPRAS/)
   - Descomentá uno de los ejemplos del bloque `if __name__ == "__main__":` al final
     del archivo, ajustá destinatarios/asunto/cuerpo y corré:   python mail.py
   - O desde otro script:   from mail import enviar_correo_individual
   Ver también COMPRAS/README.md.

6) DÓNDE QUEDA LA COPIA ENVIADA
   Al enviar como otra identidad, la copia se guarda según Webmail > Preferencias >
   Cuentas > "Guardar una copia de los mensajes enviados en..." (por defecto suele
   ser la carpeta Enviados de la cuenta delegante, ej. contable.limpieza).
"""

import time
from pathlib import Path

import requests

CARPETA = Path(__file__).resolve().parent

# --- CONFIGURACIÓN CON EL SERVIDOR DEL CERTIFICADO ---
EMAIL = "nicolas.liotti@imm.gub.uy"  # Tu usuario completo según el archivo [cite: 4]
PASSWORD = "Nico1919*"

# Los puertos SMTP (25/465/587) están cerrados desde esta red, pero el webmail
# (HTTPS/443) sí funciona. Por eso enviamos usando la misma API SOAP/JSON que
# usa el webmail de Zimbra en vez de conectar directo por SMTP.
SOAP_ENDPOINT = "https://webmail.montevideo.gub.uy/service/soap"
# ----------------------  --------


def _autenticar(session):
    """Hace el login SOAP contra Zimbra (con el paso de 2FA si la cuenta lo pide) y devuelve el authToken válido."""
    auth_payload = {
        "Header": {"context": {"_jsns": "urn:zimbra"}},
        "Body": {
            "AuthRequest": {
                "_jsns": "urn:zimbraAccount",
                "account": {"_content": EMAIL, "by": "name"},
                "password": {"_content": PASSWORD},
            }
        },
    }
    auth_resp = session.post(SOAP_ENDPOINT, json=auth_payload, timeout=15)
    if not auth_resp.ok:
        print("Respuesta de Zimbra (auth):", auth_resp.text)
    auth_resp.raise_for_status()
    auth_data = auth_resp.json()
    if "Fault" in auth_data.get("Body", {}):
        raise RuntimeError(f"Error de autenticación en Zimbra: {auth_data['Body']['Fault']}")

    auth_response = auth_data["Body"]["AuthResponse"]
    auth_token = auth_response["authToken"][0]["_content"]

    # Esta cuenta tiene 2FA habilitado: el AuthRequest inicial solo da un token
    # "pendiente" que hay que validar con el código de la app de autenticación
    # antes de que sirva para cualquier otra operación (ej. enviar un correo).
    if auth_response.get("twoFactorAuthRequired", {}).get("_content") == "true":
        codigo = input("Ingresá el código de la app de autenticación (2FA): ").strip()
        segundo_payload = {
            "Header": {"context": {"_jsns": "urn:zimbra", "authToken": [{"_content": auth_token}]}},
            "Body": {
                "AuthRequest": {
                    "_jsns": "urn:zimbraAccount",
                    "account": {"_content": EMAIL, "by": "name"},
                    "password": {"_content": PASSWORD},
                    "twoFactorCode": {"_content": codigo},
                }
            },
        }
        tfa_resp = session.post(SOAP_ENDPOINT, json=segundo_payload, timeout=15)
        if not tfa_resp.ok:
            print("Respuesta de Zimbra (2FA):", tfa_resp.text)
        tfa_resp.raise_for_status()
        tfa_data = tfa_resp.json()
        if "Fault" in tfa_data.get("Body", {}):
            raise RuntimeError(f"Error validando el código 2FA: {tfa_data['Body']['Fault']}")
        auth_token = tfa_data["Body"]["AuthResponse"]["authToken"][0]["_content"]

    return auth_token


def listar_identidades():
    """Consulta las identidades configuradas en la cuenta (Preferencias > Cuentas en el webmail) con su id y dirección."""
    session = requests.Session()
    auth_token = _autenticar(session)

    payload = {
        "Header": {"context": {"_jsns": "urn:zimbra", "authToken": [{"_content": auth_token}]}},
        "Body": {"GetIdentitiesRequest": {"_jsns": "urn:zimbraAccount"}},
    }
    resp = session.post(SOAP_ENDPOINT, json=payload, timeout=15)
    resp.raise_for_status()
    data = resp.json()
    if "Fault" in data.get("Body", {}):
        raise RuntimeError(f"Error consultando identidades: {data['Body']['Fault']}")

    identidades = data["Body"]["GetIdentitiesResponse"]["identity"]
    for ident in identidades:
        attrs = ident.get("_attrs", {})
        print(
            f"- {ident.get('name')} (id={ident.get('id')}) "
            f"-> {attrs.get('zimbraPrefFromAddress')} / {attrs.get('zimbraPrefFromDisplay')}"
        )
    return identidades


def leer_correos(archivo="correos.txt"):
    """Lee una lista de direcciones (una por línea) desde un .txt de la carpeta COMPRAS.

    Ignora líneas vacías o sin "@", saca espacios y duplicados (respeta el orden del archivo).
    """
    ruta = Path(archivo)
    if not ruta.is_absolute():
        ruta = CARPETA / ruta
    with open(ruta, encoding="utf-8") as f:
        direcciones = [linea.strip() for linea in f if "@" in linea]
    return list(dict.fromkeys(direcciones))


def _a_lista(valor):
    if not valor:
        return []
    return [valor] if isinstance(valor, str) else list(valor)


def _enviar_mensaje(session, auth_token, destinatarios, asunto, cuerpo, es_html, cc, cco, identidad_id, remitente_final, nombre_final):
    """Arma y manda un único SendMsgRequest ya autenticado. Uso interno."""
    copiados = _a_lista(cc)
    copiados_ocultos = _a_lista(cco)

    e = (
        [{"t": "t", "a": d} for d in destinatarios]
        + [{"t": "c", "a": d} for d in copiados]
        + [{"t": "b", "a": d} for d in copiados_ocultos]
        + [{"t": "f", "a": remitente_final, "p": nombre_final}]
    )

    m = {
        "e": e,
        "su": {"_content": asunto},
        "mp": [
            {"ct": "text/html" if es_html else "text/plain", "content": {"_content": cuerpo}}
        ],
    }
    if identidad_id:
        m["idnt"] = identidad_id

    send_payload = {
        "Header": {"context": {"_jsns": "urn:zimbra", "authToken": [{"_content": auth_token}]}},
        "Body": {"SendMsgRequest": {"_jsns": "urn:zimbraMail", "m": m}},
    }
    send_resp = session.post(SOAP_ENDPOINT, json=send_payload, timeout=15)
    if not send_resp.ok:
        print("Respuesta de Zimbra (send):", send_resp.text)
    send_resp.raise_for_status()
    result = send_resp.json()
    if "Fault" in result.get("Body", {}):
        raise RuntimeError(f"Error al enviar el correo: {result['Body']['Fault']}")

    resumen = f'Correo enviado desde {remitente_final} a {", ".join(destinatarios)} — Asunto: "{asunto}"'
    if copiados:
        resumen += f" — CC: {', '.join(copiados)}"
    if copiados_ocultos:
        resumen += f" — CCO: {', '.join(copiados_ocultos)}"
    print(resumen)
    return result


def enviar_correo(
    destinatario,
    asunto,
    cuerpo,
    es_html=False,
    cc=None,
    cco=None,
    identidad_id=None,
    remitente=None,
    nombre_remitente=None,
):
    """Envía UN correo, todos los destinatarios juntos en el mismo mensaje.

    `destinatario`, `cc` y `cco` aceptan un string o una lista de direcciones.
    Si están todos en `destinatario`/`cc`, cada uno ve las direcciones de los demás
    (usá `cco` o `enviar_correo_individual` si no querés que se vean entre sí).

    Para enviar desde otra identidad (Preferencias > Cuentas), pasá `identidad_id`
    (usá listar_identidades() para verlos) junto con `remitente`/`nombre_remitente`
    con la dirección y nombre de esa identidad.
    """
    session = requests.Session()
    auth_token = _autenticar(session)
    remitente_final = remitente or EMAIL
    nombre_final = nombre_remitente or "Nicolás Liotti"
    destinatarios = _a_lista(destinatario)

    return _enviar_mensaje(
        session, auth_token, destinatarios, asunto, cuerpo, es_html, cc, cco,
        identidad_id, remitente_final, nombre_final,
    )


def enviar_correo_individual(
    destinatarios,
    asunto,
    cuerpo,
    es_html=False,
    identidad_id=None,
    remitente=None,
    nombre_remitente=None,
    pausa_segundos=10,
):
    """Manda el MISMO correo a cada destinatario por separado (uno no ve la dirección del otro).

    Se autentica una sola vez y hace un SendMsgRequest por cada dirección en `destinatarios`.
    Espera `pausa_segundos` entre un envío y el siguiente para no disparar límites anti-spam.
    """
    session = requests.Session()
    auth_token = _autenticar(session)
    remitente_final = remitente or EMAIL
    nombre_final = nombre_remitente or "Nicolás Liotti"

    lista = _a_lista(destinatarios)
    resultados = []
    for i, destinatario in enumerate(lista, start=1):
        if i > 1 and pausa_segundos:
            time.sleep(pausa_segundos)
        print(f"[{i}/{len(lista)}] ", end="")
        resultados.append(
            _enviar_mensaje(
                session, auth_token, [destinatario], asunto, cuerpo, es_html,
                None, None, identidad_id, remitente_final, nombre_final,
            )
        )
    return resultados


 # if __name__ == "__main__":
 #    enviar_correo(
 #        destinatario="nicolas.liotti@imm.gub.uy",
 #        asunto="Prueba de envío",
 #        cuerpo="Este es un correo de prueba.",
 #        identidad_id="9835e787-818b-4ab5-9d38-50fe40b662a5",
 #        remitente="recoleccion.nodomiciliarios@imm.gub.uy",
 #        nombre_remitente="recoleccion no domiciliarios",
 #    )
 
 # otra forma
# --
#  enviar_correo(
#     destinatario="a@x.com",
#     cc=["b@x.com", "c@x.com"],
#     cco="d@x.com",
#     asunto="...",
#     cuerpo="...",
# )
#     
    
if __name__ == "__main__":
    # Ejemplos listos para usar: descomentá UNO, ajustalo y corré `python mail.py`.
    # Están comentados para que ejecutar el archivo no mande nada por accidente.

    # --- Ejemplo 1: un correo separado a cada dirección de correos.txt, desde Contable Limpieza ---
    # (para probar primero, usá destinatarios=["nicolasliotti92@gmail.com"])

    enviar_correo_individual(
        # para enviar lista rel / destinatarios=leer_correos(), /  # ← correos.txt (lista real)
        destinatarios=leer_correos(),  # ← correosPrueba.txt (solo tus direcciones)
        asunto="Aclaraciones",
        cuerpo="""
            <html>
                <body style="font-family: sans-serif; font-size: 18px;">
                    A quién corresponda<br>
                    El mail enviado es genérico pero dirigido a cada empresa por separado.<br>
                    Se va a generar automáticamente el primer día hábil del mes y tendrá como asunto la documentación en general del mes anterior.<br>
                    Los proveedores que ya enviaron toda la documentación no es necesario que la vuelvan a mandar.<br>
                    Saludos cordiales
                </body>
            </html>
        """,
        es_html=True,
        identidad_id="143fc742-ea5e-49ab-b5dd-a475a4d17ac4",  # Contable Limpieza
        remitente="contable.limpieza@imm.gub.uy",
        nombre_remitente="Contable Limpieza",
    )

    # --- Ejemplo 2: un solo correo con CC/CCO, desde Contable Limpieza ---
    # enviar_correo(
    #     destinatario="a@imm.gub.uy",
    #     cc=["b@imm.gub.uy"],
    #     cco=["c@imm.gub.uy"],
    #     asunto="...",
    #     cuerpo="<p>...</p>",
    #     es_html=True,
    #     identidad_id="143fc742-ea5e-49ab-b5dd-a475a4d17ac4",  # Contable Limpieza
    #     remitente="contable.limpieza@imm.gub.uy",
    #     nombre_remitente="Contable Limpieza",
    # )

    # --- Ejemplo 3: desde recoleccion.nodomiciliarios ---
    # enviar_correo_individual(
    #     destinatarios=["nicolas.liotti@imm.gub.uy"],
    #     asunto="Prueba de envío",
    #     cuerpo="Este es un correo de prueba.",
    #     identidad_id="9835e787-818b-4ab5-9d38-50fe40b662a5",  # No domiciliarios
    #     remitente="recoleccion.nodomiciliarios@imm.gub.uy",
    #     nombre_remitente="recoleccion no domiciliarios",
    # )

    # --- Ejemplo 4: desde tu cuenta personal (sin identidad_id) ---
    # enviar_correo_individual(
    #     destinatarios=["nicolasliotti92@gmail.com"],
    #     asunto="Prueba",
    #     cuerpo="Hola",
    # )
    pass


# --- CÓDIGO ANTERIOR: búsqueda y conteo de remitentes de la bandeja de entrada ---
# import imaplib
# import email
# from email.header import decode_header
#
# IMAP_SERVER = "imap.imm.gub.uy"
# IMAP_PORT = 993
#
# try:
#     print("Conectando al servidor de la IM...")
#     mail = imaplib.IMAP4_SSL(IMAP_SERVER, IMAP_PORT)
#     mail.login(EMAIL, PASSWORD)
#     mail.select("inbox")
#
#     # Buscamos TODOS los correos de la bandeja de entrada
#     print("Buscando correos... (Esto puede demorar unos segundos si tenés muchos)")
#     status, messages = mail.search(None, 'ALL')
#     mail_ids = messages[0].split()
#
#     print(f"Se encontraron {len(mail_ids)} correos en total. Procesando remitentes...")
#
#     lista_remitentes = []
#
#     # Recorremos cada correo para extraer el 'From' (Remitente)
#     for num in mail_ids:
#         # Solo descargamos el encabezado (HEADER) para que sea muchísimo más rápido
#         status, data = mail.fetch(num, '(BODY[HEADER.FIELDS (FROM)])')
#
#         for response_part in data:
#             if isinstance(response_part, tuple):
#                 # Parseamos el encabezado
#                 msg = email.message_from_bytes(response_part[1])
#                 from_header = msg['From']
#
#                 if from_header:
#                     # Decodificar por si el nombre tiene tildes o caracteres raros
#                     decoded_parts = decode_header(from_header)
#                     remitente_limpio = ""
#                     for part, encoding in decoded_parts:
#                         if isinstance(part, bytes):
#                             remitente_limpio += part.decode(encoding or "utf-8", errors="ignore")
#                         else:
#                             remitente_limpio += part
#
#                     # Limpiamos espacios y saltos de línea molestos
#                     remitente_limpio = remitente_limpio.strip().replace("\r", "").replace("\n", "")
#                     lista_remitentes.append(remitente_limpio)
#
#     # Cerrar conexión con Zimbra de forma limpia
#     mail.logout()
#     print("Conexión con el servidor cerrada.")
#
#     # --- MAGIA DEL CONTEO Y ORDENADO ---
#     # Counter cuenta cuántas veces aparece cada remitente y .most_common() los ordena de mayor a menor
#     conteo_remitentes = Counter(lista_remitentes).most_common()
#
#     # --- CREACIÓN DEL EXCEL ---
#     print("Generando el archivo Excel con el ranking...")
#     wb = openpyxl.Workbook()
#     sheet = wb.active
#     sheet.title = "Ranking de Correos"
#
#     # Ponemos los títulos de las columnas
#     sheet["A1"] = "Remitente / Dirección"
#     sheet["B1"] = "Cantidad de Mails"
#
#     # Aplicamos un formato negrita simple a los encabezados
#     sheet["A1"].font = openpyxl.styles.Font(bold=True)
#     sheet["B1"].font = openpyxl.styles.Font(bold=True)
#
#     # Volcamos los datos fila por fila
#     # El bucle empieza en la fila 2 para no pisar los títulos
#     for fila, (remitente, cantidad) in enumerate(conteo_remitentes, start=2):
#         sheet[f"A{fila}"] = remitente
#         sheet[f"B{fila}"] = cantidad
#
#     # Ajustar el ancho de la columna A automáticamente para que se lea bien
#     sheet.column_dimensions['A'].width = 50
#     sheet.column_dimensions['B'].width = 20
#
#     # Guardamos el archivo en la misma carpeta del script
#     nombre_excel = "ranking_remitentes.xlsx"
#     wb.save(nombre_excel)
#     wb.close()
#
#     print(f"¡Proceso terminado con éxito! Archivo guardado como: '{nombre_excel}'")
#
# except Exception as e:
#     print(f"\nOcurrió un error durante el proceso: {e}")
