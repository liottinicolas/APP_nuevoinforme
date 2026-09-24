import requests

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
):
    """Manda el MISMO correo a cada destinatario por separado (uno no ve la dirección del otro).

    Se autentica una sola vez y hace un SendMsgRequest por cada dirección en `destinatarios`.
    """
    session = requests.Session()
    auth_token = _autenticar(session)
    remitente_final = remitente or EMAIL
    nombre_final = nombre_remitente or "Nicolás Liotti"

    resultados = []
    for destinatario in _a_lista(destinatarios):
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
    enviar_correo(
        destinatario=["nicolas.liotti@imm.gub.uy", "nicolasliotti92@gmail.com"],
        asunto="Prueba de envío",
        cuerpo="""
            <html>
                <body>
                    <h2>Prueba de envío</h2>
                    <p>Este es un correo de <strong>prueba</strong> en formato HTML.</p>
                </body>
            </html>
        """,
        es_html=True,
        identidad_id="9835e787-818b-4ab5-9d38-50fe40b662a5",
        remitente="recoleccion.nodomiciliarios@imm.gub.uy",
        nombre_remitente="recoleccion no domiciliarios",
    )
    
    enviar_correo_individual(
    destinatarios=["nicolas.liotti@imm.gub.uy", "nicolas.liotti@imm.gub.uy"],
    asunto="eaaaa",
    cuerpo="vpi",
    es_html=True,
    identidad_id="9835e787-818b-4ab5-9d38-50fe40b662a5",
    remitente="recoleccion.nodomiciliarios@imm.gub.uy",
    nombre_remitente="recoleccion no domiciliarios",
)


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
