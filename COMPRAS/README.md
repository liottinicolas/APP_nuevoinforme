# COMPRAS — Envío de correos por el webmail de la IM

Envía correos desde el webmail de Zimbra (`webmail.montevideo.gub.uy`) usando su API SOAP por HTTPS. Desde la red de la IM los puertos SMTP están cerrados, por eso no se usa SMTP. Se puede enviar desde cualquier identidad configurada en la cuenta, por ejemplo **Contable Limpieza**.

## Archivos

| Archivo | Qué es | ¿Se versiona en git? |
|---|---|---|
| `mail.py` | Funciones de envío y ejemplos listos para descomentar | Sí |
| `correos.txt` | Lista de destinatarios, una dirección por línea | **No** (`.gitignore`): son datos de contacto de terceros |
| `README.md` | Esta guía | Sí |

## Uso rápido

1. Edita `correos.txt`. Pon una dirección por línea. Las líneas vacías y los duplicados se ignoran.
2. En `mail.py`, al final del archivo, descomenta el **Ejemplo 1** y ajusta el asunto y el cuerpo.
3. Ejecuta desde la carpeta `COMPRAS/`:
   ```bash
   cd COMPRAS
   python mail.py
   ```
4. Ingresa el código 2FA de la app de autenticación. Se pide una sola vez por ejecución.
5. Por cada correo que salga bien, la consola muestra `Correo enviado desde ... a ...`.

> Prueba siempre primero con `destinatarios=["tu-correo@..."]` antes de mandarlo a la lista real.

## Identidades (desde qué cuenta sale el correo)

Pasa siempre los tres valores de **la misma fila**. Zimbra usa la dirección de la identidad: si el `identidad_id` no coincide con el `remitente`, el correo sale igual desde la cuenta del id.

| Identidad | `identidad_id` | `remitente` | `nombre_remitente` |
|---|---|---|---|
| Contable Limpieza | `143fc742-ea5e-49ab-b5dd-a475a4d17ac4` | `contable.limpieza@imm.gub.uy` | Contable Limpieza |
| No domiciliarios | `9835e787-818b-4ab5-9d38-50fe40b662a5` | `recoleccion.nodomiciliarios@imm.gub.uy` | recoleccion no domiciliarios |
| Nicolás (default) | `f8c2e9a7-3d51-4b5a-a283-d1abed4b118b` | `nicolas.liotti@imm.gub.uy` | Nicolas Liotti |

Si no pasas `identidad_id`, el correo sale desde `nicolas.liotti@imm.gub.uy`.
Para ver o actualizar la lista:

```bash
python -c "import mail; mail.listar_identidades()"
```

## Funciones

| Función | Qué hace |
|---|---|
| `enviar_correo_individual(destinatarios, asunto, cuerpo, ...)` | Manda **un correo separado a cada dirección**. Nadie ve a quién más se le envió. **Es la recomendada para listas.** |
| `enviar_correo(destinatario, asunto, cuerpo, cc=None, cco=None, ...)` | Manda **un solo correo**. Los destinatarios en `destinatario` y en `cc` ven las direcciones de los demás; los que van en `cco`, no. |
| `leer_correos(archivo="correos.txt")` | Devuelve la lista de direcciones del `.txt`, sin espacios ni duplicados. |
| `listar_identidades()` | Muestra las identidades de la cuenta con su id. |

Parámetros comunes:
- `asunto`: el texto del asunto.
- `cuerpo`: texto plano, o HTML si pones `es_html=True`.
- `identidad_id`, `remitente`, `nombre_remitente`: ver la tabla de identidades.

### Ejemplo

```python
from mail import enviar_correo_individual, leer_correos

enviar_correo_individual(
    destinatarios=leer_correos(),
    asunto="Solicitud de recibos de sueldo – Setiembre 2026",
    cuerpo="<p>A quien corresponda,</p><p>...</p><p>Desde ya, gracias.</p>",
    es_html=True,
    identidad_id="143fc742-ea5e-49ab-b5dd-a475a4d17ac4",  # Contable Limpieza
    remitente="contable.limpieza@imm.gub.uy",
    nombre_remitente="Contable Limpieza",
)
```

## Formato del cuerpo HTML

Usa estilos **inline** (`style="..."` dentro de cada etiqueta). Gmail y Outlook suelen ignorar los bloques `<style>`. El `style` del `<body>` se aplica a todo el correo; en un `<p>` o `<strong>` cambia solo ese texto.

```html
<html>
  <body style="font-family: Arial, sans-serif; font-size: 16px; color: #222; line-height: 1.5;">
    <p>A quien corresponda,</p>
    <p>Solicitamos ... del mes de <strong style="color: #0b5394;">Setiembre del 2026</strong>.</p>
    <p style="font-size: 18px; font-weight: bold;">Plazo: 15 de octubre</p>
    <p>Desde ya, gracias.</p>
    <p style="font-size: 14px; color: #666;">Contable Limpieza<br>Intendencia de Montevideo</p>
  </body>
</html>
```

| Quieres… | Escribe en `style="..."` |
|---|---|
| Letra más grande | `font-size: 16px;` (normal ≈ 13–14px; 18–20px para destacar) |
| Cambiar la fuente | `font-family: Arial, sans-serif;` |
| Color de texto | `color: #0b5394;` (o `color: red;`) |
| Negrita | `font-weight: bold;` o la etiqueta `<strong>...</strong>` |
| Cursiva | la etiqueta `<em>...</em>` |
| Subrayado | `text-decoration: underline;` |
| Más espacio entre líneas | `line-height: 1.5;` |
| Resaltado de fondo | `background-color: #fff2cc;` |
| Centrar | `text-align: center;` |

Otras etiquetas útiles: `<br>` hace un salto de línea, `<h2>` es un título y `<ul><li>…</li></ul>` arma una lista con viñetas. Recuerda poner `es_html=True` y probar primero con `correosPrueba.txt`.

## Ten en cuenta

- **Si un envío falla, el script se detiene en esa dirección** y las siguientes no se envían. Revisa en la consola cuáles salieron antes de volver a correrlo, para no duplicar envíos.
- **Copia en Enviados:** cuando envías como otra identidad, la copia se guarda según *Webmail → Preferencias → Cuentas → "Guardar una copia de los mensajes enviados en…"*. Por defecto suele ir a la carpeta Enviados de la cuenta delegante, por ejemplo contable.limpieza, y no a la tuya.
- **Credenciales:** `mail.py` tiene el usuario y la contraseña en texto plano (`EMAIL`, `PASSWORD`). Lo pendiente es moverlos a variables de entorno.
