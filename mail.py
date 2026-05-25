import imaplib
import email
from email.header import decode_header

# --- CONFIGURACIÓN CON EL SERVIDOR DEL CERTIFICADO ---
EMAIL = "nicolas.liotti@imm.gub.uy"  # Tu usuario completo según el archivo [cite: 4]
PASSWORD = "NMNDUVKZUCXMPGTT"

# Este es el servidor IMAP externo real que figura en el certificado de la IM 
IMAP_SERVER = "imap.imm.gub.uy" 
IMAP_PORT = 993
# ----------------------  --------

try:
    print("Conectando al servidor de la IM...")
    mail = imaplib.IMAP4_SSL(IMAP_SERVER, IMAP_PORT)
    mail.login(EMAIL, PASSWORD)
    mail.select("inbox")
    
    # Buscamos TODOS los correos de la bandeja de entrada
    print("Buscando correos... (Esto puede demorar unos segundos si tenés muchos)")
    status, messages = mail.search(None, 'ALL')
    mail_ids = messages[0].split()
    
    print(f"Se encontraron {len(mail_ids)} correos en total. Procesando remitentes...")
    
    lista_remitentes = []
    
    # Recorremos cada correo para extraer el 'From' (Remitente)
    for num in mail_ids:
        # Solo descargamos el encabezado (HEADER) para que sea muchísimo más rápido
        status, data = mail.fetch(num, '(BODY[HEADER.FIELDS (FROM)])')
        
        for response_part in data:
            if isinstance(response_part, tuple):
                # Parseamos el encabezado
                msg = email.message_from_bytes(response_part[1])
                from_header = msg['From']
                
                if from_header:
                    # Decodificar por si el nombre tiene tildes o caracteres raros
                    decoded_parts = decode_header(from_header)
                    remitente_limpio = ""
                    for part, encoding in decoded_parts:
                        if isinstance(part, bytes):
                            remitente_limpio += part.decode(encoding or "utf-8", errors="ignore")
                        else:
                            remitente_limpio += part
                    
                    # Limpiamos espacios y saltos de línea molestos
                    remitente_limpio = remitente_limpio.strip().replace("\r", "").replace("\n", "")
                    lista_remitentes.append(remitente_limpio)

    # Cerrar conexión con Zimbra de forma limpia
    mail.logout()
    print("Conexión con el servidor cerrada.")

    # --- MAGIA DEL CONTEO Y ORDENADO ---
    # Counter cuenta cuántas veces aparece cada remitente y .most_common() los ordena de mayor a menor
    conteo_remitentes = Counter(lista_remitentes).most_common()

    # --- CREACIÓN DEL EXCEL ---
    print("Generando el archivo Excel con el ranking...")
    wb = openpyxl.Workbook()
    sheet = wb.active
    sheet.title = "Ranking de Correos"
    
    # Ponemos los títulos de las columnas
    sheet["A1"] = "Remitente / Dirección"
    sheet["B1"] = "Cantidad de Mails"
    
    # Aplicamos un formato negrita simple a los encabezados
    sheet["A1"].font = openpyxl.styles.Font(bold=True)
    sheet["B1"].font = openpyxl.styles.Font(bold=True)
    
    # Volcamos los datos fila por fila
    # El bucle empieza en la fila 2 para no pisar los títulos
    for fila, (remitente, cantidad) in enumerate(conteo_remitentes, start=2):
        sheet[f"A{fila}"] = remitente
        sheet[f"B{fila}"] = cantidad

    # Ajustar el ancho de la columna A automáticamente para que se lea bien
    sheet.column_dimensions['A'].width = 50
    sheet.column_dimensions['B'].width = 20

    # Guardamos el archivo en la misma carpeta del script
    nombre_excel = "ranking_remitentes.xlsx"
    wb.save(nombre_excel)
    wb.close()
    
    print(f"¡Proceso terminado con éxito! Archivo guardado como: '{nombre_excel}'")

except Exception as e:
    print(f"\nOcurrió un error durante el proceso: {e}")
