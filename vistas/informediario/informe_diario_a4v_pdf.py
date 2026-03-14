import os
from datetime import datetime
import pandas as pd
import pyreadr
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Table, TableStyle,
    Paragraph, Spacer, PageBreak
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT

# ─── Paleta de colores ────────────────────────────────────────────────────────
azul_header  = colors.HexColor("#0046E3")
celeste_texto = colors.HexColor("#0070C0")
gris_claro   = colors.HexColor("#EAEAEA")

# ─── 1. CARGA DE DATOS ────────────────────────────────────────────────────────
def load_real_data(base_dir):
    data_dir = os.path.join(base_dir, "data")
    path_im  = os.path.join(data_dir, "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds")
    path_fid = os.path.join(data_dir, "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds")

    try:
        df_im_full  = pyreadr.read_r(path_im)[None]
        df_fid_full = pyreadr.read_r(path_fid)[None]
    except Exception as e:
        print(f"Error cargando RDS: {e}")
        return (
            pd.DataFrame(),
            pd.DataFrame(),
            pd.DataFrame(columns=['MUNICIPIO', 'CONT_INSTALADOS']),
            pd.Timestamp.now().date()
        )

    df_im_full['Fecha_dt']  = pd.to_datetime(df_im_full['Fecha'],  dayfirst=False)
    df_fid_full['Fecha_dt'] = pd.to_datetime(df_fid_full['Fecha'], dayfirst=False)

    ultima_fecha = max(df_im_full['Fecha_dt'].max(), df_fid_full['Fecha_dt'].max())

    fecha_env = os.environ.get("FECHA_REPORTE")
    if fecha_env:
        try:
            fecha_ingresada = pd.to_datetime(fecha_env).normalize()
            if fecha_ingresada > ultima_fecha.normalize():
                raise ValueError(
                    f"La fecha ingresada ({fecha_ingresada.strftime('%Y-%m-%d')}) "
                    f"es mayor al último dato disponible."
                )
            fecha_reporte = fecha_ingresada
        except ValueError as e:
            print(f"Advertencia FECHA_REPORTE: {e}. Se usa fecha por defecto.")
            fecha_reporte = ultima_fecha.normalize()
    else:
        fecha_reporte = ultima_fecha.normalize()

    df_im  = df_im_full[df_im_full['Fecha_dt'].dt.normalize()  == fecha_reporte].copy()
    df_fid = df_fid_full[df_fid_full['Fecha_dt'].dt.normalize() == fecha_reporte].copy()

    def procesar_tabla(df_in):
        if df_in.empty:
            return pd.DataFrame(columns=[
                'MUNICIPIO', 'TURNO', 'PLANIF.', 'PROGRAMADOS',
                'VISITADOS', 'NO VISITADOS', 'VACIADOS', 'NO VACIADOS'
            ])
        for col in ['Planificados', 'Programado', 'Visitados', 'No_visitados', 'Vaciados', 'No_Vaciados']:
            if col not in df_in.columns:
                df_in[col] = 0
        df = df_in[['Municipio', 'Turno', 'Planificados', 'Programado',
                     'Visitados', 'No_visitados', 'Vaciados', 'No_Vaciados']].copy()
        for col in ['Planificados', 'Programado', 'Visitados', 'No_visitados', 'Vaciados', 'No_Vaciados']:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)
        df.columns = ['MUNICIPIO', 'TURNO', 'PLANIF.', 'PROGRAMADOS',
                      'VISITADOS', 'NO VISITADOS', 'VACIADOS', 'NO VACIADOS']
        total_row  = df[['PLANIF.', 'PROGRAMADOS', 'VISITADOS', 'NO VISITADOS', 'VACIADOS', 'NO VACIADOS']].sum()
        total_dict = {'MUNICIPIO': 'Total', 'TURNO': '', **total_row.to_dict()}
        df = pd.concat([df, pd.DataFrame([total_dict])], ignore_index=True)
        return df

    # Contenedores instalados
    path_ubicaciones = os.path.join(base_dir, "../../db/10393_ubicaciones/historico_ubicaciones.rds")
    df_inst_final = pd.DataFrame(columns=['MUNICIPIO', 'CONT_INSTALADOS'])
    try:
        df_ubic = pyreadr.read_r(path_ubicaciones)[None]
        df_ubic['Fecha_dt'] = pd.to_datetime(df_ubic['Fecha'], dayfirst=False)
        df_ubic_filtrado    = df_ubic[df_ubic['Fecha_dt'].dt.normalize() == fecha_reporte].copy()
        df_ubic_instalados  = df_ubic_filtrado[df_ubic_filtrado['Estado'].isna()].copy()
        if not df_ubic_instalados.empty:
            counts = df_ubic_instalados.groupby('Municipio').size().reset_index(name='CONT_INSTALADOS')
            counts.rename(columns={'Municipio': 'MUNICIPIO'}, inplace=True)
            counts = counts.sort_values(by='MUNICIPIO')
            total_inst = counts['CONT_INSTALADOS'].sum()
            df_inst_final = pd.concat(
                [counts, pd.DataFrame([{'MUNICIPIO': 'Total', 'CONT_INSTALADOS': total_inst}])],
                ignore_index=True
            )
    except Exception as e:
        print(f"Error procesando ubicaciones: {e}")

    return procesar_tabla(df_im), procesar_tabla(df_fid), df_inst_final, fecha_reporte


def get_dummy_disponibilidad():
    """Datos de disponibilidad de recolección lateral (dummy por ahora)."""
    data = {
        'TURNO':      ['M', 'V', 'N', 'Total'],
        'CAM_INICIO': [30, 26, 31, 87],
        'CAM_USADOS': [13,  2, 24, 39],
        'CHOFERES':   [16,  2, 29, 47],
        'AUXILIARES': [13,  4, 25, 42],
    }
    return pd.DataFrame(data)


# ─── 2. ENCABEZADO Y PIE DE PÁGINA ───────────────────────────────────────────
def draw_header_footer(canvas, doc):
    canvas.saveState()
    w, h = doc.pagesize  # A4 vertical

    # ── Barra azul superior ──
    canvas.setFillColor(azul_header)
    canvas.rect(0, h - 2*cm, w, 2*cm, stroke=0, fill=1)

    # ── Logo ──
    ruta_logo = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        "logoazul.png"
    )
    if os.path.exists(ruta_logo):
        canvas.drawImage(
            ruta_logo,
            1.0*cm, h - 1.85*cm,
            width=4*cm, height=1.5*cm,
            preserveAspectRatio=True, mask='auto'
        )

    # ── Título y fecha centrados en la barra ──
    titulo = doc.report_title if hasattr(doc, 'report_title') else "INFORME DIARIO"
    canvas.setFont("Helvetica-Bold", 13)
    canvas.setFillColor(colors.white)
    canvas.drawCentredString(w / 2, h - 1.1*cm, titulo)

    canvas.setFont("Helvetica", 9)
    fecha_str = doc.report_date if hasattr(doc, 'report_date') else ""
    canvas.drawCentredString(w / 2, h - 1.65*cm, fecha_str)

    # ── Barra azul inferior ──
    canvas.setFillColor(azul_header)
    canvas.rect(0, 0, w, 1*cm, stroke=0, fill=1)

    # ── Número de página ──
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.white)
    canvas.drawCentredString(w / 2, 0.3*cm, f"Página {doc.page}")

    canvas.restoreState()


# ─── 3. TABLAS ────────────────────────────────────────────────────────────────
def _estilo_base_tabla(data, gris_en_impares=True):
    """Estilo base compartido por todas las tablas del informe."""
    estilo = TableStyle([
        ('FONTNAME',      (0, 0), (-1,  0), 'Helvetica-BoldOblique'),
        ('FONTSIZE',      (0, 0), (-1, -1), 8),
        ('ALIGN',         (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN',        (0, 0), (-1, -1), 'MIDDLE'),
        ('TEXTCOLOR',     (0, 0), (-1,  0), colors.black),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
        ('TOPPADDING',    (0, 0), (-1, -1), 2),
        ('LINEABOVE',     (0, 0), (-1,  0), 1, colors.black),
        ('LINEBELOW',     (0, 0), (-1,  0), 1, colors.black),
        # Fila total
        ('FONTNAME',  (0, -1), (-1, -1), 'Helvetica-Bold'),
        ('LINEABOVE', (0, -1), (-1, -1), 1, colors.black),
        ('LINEBELOW', (0, -1), (-1, -1), 1, colors.black),
    ])
    n = len(data)
    for i in range(1, n - 1):
        if gris_en_impares:
            if i % 2 == 0:
                estilo.add('BACKGROUND', (0, i), (-1, i), gris_claro)
        else:
            if i % 2 == 1:
                estilo.add('BACKGROUND', (0, i), (-1, i), gris_claro)
    return estilo


# Ancho útil de una página A4 vertical con márgenes de 1.5 cm a cada lado
ANCHO_UTIL = A4[0] - 3*cm   # ≈ 14.77 cm


def crear_tabla_contenedores(df, es_fideicomiso=False):
    if es_fideicomiso:
        headers    = ["MUNICIPIO", "TURNO", "PROGRAMADOS", "VISITADOS",
                      "NO VISITADOS", "VACIADOS", "NO VACIADOS"]
        col_widths = [2.5*cm, 1.8*cm, 2.8*cm, 2.1*cm, 2.8*cm, 2.2*cm, 2.0*cm]
        df_copy    = df.drop(columns=['PLANIF.']) if 'PLANIF.' in df.columns else df.copy()
    else:
        headers    = ["MUNICIPIO", "TURNO", "PLANIF.", "PROGRAMADOS",
                      "VISITADOS", "NO VISITADOS", "VACIADOS", "NO VACIADOS"]
        col_widths = [2.2*cm, 1.8*cm, 1.6*cm, 2.6*cm, 2.0*cm, 2.4*cm, 2.0*cm, 1.7*cm]
        df_copy    = df.copy()

    data   = [headers] + df_copy.astype(str).values.tolist()
    t      = Table(data, colWidths=col_widths)
    estilo = _estilo_base_tabla(data, gris_en_impares=True)
    t.setStyle(estilo)
    return t


def crear_tabla_instalados(df, col_widths=None):
    if col_widths is None:
        col_widths = [3.0*cm, 8.0*cm]
    headers = ["MUNICIPIO", "CONT. INSTALADOS EN VÍA PÚBLICA"]
    data    = [headers] + df.astype(str).values.tolist()
    t       = Table(data, colWidths=col_widths)
    estilo  = _estilo_base_tabla(data, gris_en_impares=False)
    t.setStyle(estilo)
    return t


def crear_tabla_disponibilidad(df, col_widths=None):
    if col_widths is None:
        col_widths = [2.0*cm, 2.5*cm, 2.5*cm, 2.5*cm, 2.5*cm]
    headers = ["TURNO", "CAM.\nINICIO", "CAM.\nUSADOS", "CHOFERES", "AUXILIARES"]
    data    = [headers] + df.astype(str).values.tolist()
    t       = Table(data, colWidths=col_widths)

    estilo = _estilo_base_tabla(data, gris_en_impares=False)
    # Color celeste en columnas TURNO y CAM INICIO (filas de datos, no total)
    for i in range(1, len(data) - 1):
        estilo.add('TEXTCOLOR', (0, i), (1, i), celeste_texto)
    estilo.add('TEXTCOLOR', (1, len(data)-1), (1, len(data)-1), celeste_texto)
    t.setStyle(estilo)
    return t


# ─── 4. PÁRRAFOS TÍTULO ───────────────────────────────────────────────────────
def _titulo(texto, space_before=8):
    estilos = getSampleStyleSheet()
    return Paragraph(
        f"<u>{texto}</u>",
        ParagraphStyle(
            'titSec',
            parent=estilos['Normal'],
            fontName='Helvetica-BoldOblique',
            fontSize=10,
            textColor=celeste_texto,
            alignment=TA_LEFT,
            spaceAfter=5,
            spaceBefore=space_before,
        )
    )


def _bloque(titulo_txt, tabla, col_widths, space_before=8):
    """Envuelve un título y su tabla en un contenedor del mismo ancho,
    garantizando que ambos queden alineados al mismo borde izquierdo."""
    ancho = sum(col_widths)
    contenedor = Table(
        [[_titulo(titulo_txt, space_before=space_before)], [Spacer(1, 5)], [tabla]],
        colWidths=[ancho],
    )
    contenedor.setStyle(TableStyle([
        ('LEFTPADDING',   (0, 0), (-1, -1), 0),
        ('RIGHTPADDING',  (0, 0), (-1, -1), 0),
        ('TOPPADDING',    (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('ALIGN',         (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN',        (0, 0), (-1, -1), 'TOP'),
    ]))
    contenedor.hAlign = 'LEFT'
    return contenedor


# ─── 5. GENERADOR PRINCIPAL ───────────────────────────────────────────────────
def generar_informe_diario_a4v_pdf(output_path):
    # Determinar base_dir para búsqueda de datos
    base_dir = os.path.dirname(os.path.abspath(__file__))

    df_cont, df_fid, df_inst, fecha_objetivo = load_real_data(base_dir)
    df_disp = get_dummy_disponibilidad()

    fecha_fmt   = fecha_objetivo.strftime('%d/%m/%Y') if hasattr(fecha_objetivo, 'strftime') else str(fecha_objetivo)
    titulo_doc  = "INFORME DIARIO – CONTENEDORES"
    fecha_label = f"Fecha de datos: {fecha_fmt}"

    # ── Documento ──
    doc = BaseDocTemplate(
        output_path,
        pagesize=A4,                  # Vertical
        leftMargin=1.5*cm,
        rightMargin=1.5*cm,
        topMargin=2.8*cm,             # Deja espacio para la barra azul
        bottomMargin=1.5*cm,
    )
    doc.report_title = titulo_doc
    doc.report_date  = fecha_label

    frame    = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='normal')
    template = PageTemplate(id='Principal', frames=frame, onPage=draw_header_footer)
    doc.addPageTemplates([template])

    elementos = []
    estilos   = getSampleStyleSheet()

    # Anchos de columnas
    cw_municipales = [2.2*cm, 1.8*cm, 1.6*cm, 2.6*cm, 2.0*cm, 2.4*cm, 2.0*cm, 1.7*cm]
    cw_fideicomiso = [2.5*cm, 1.8*cm, 2.8*cm, 2.1*cm, 2.8*cm, 2.2*cm, 2.0*cm]

    # Instalados y Disponibilidad lado a lado
    # Ancho útil ~18 cm → izq 7.5 + gap 0.5 + der 10.0 = 18 cm
    cw_instalados  = [2.5*cm, 5.0*cm]                            # 7.5 cm
    cw_disponibil  = [2.0*cm, 2.0*cm, 2.0*cm, 2.0*cm, 2.0*cm]  # 10.0 cm
    gap_lado       = 0.5*cm

    # ════════════════════════════════════════════════════════════════════════
    # PÁGINA 1: Municipales + Fideicomiso + (Instalados | Disponibilidad)
    # ════════════════════════════════════════════════════════════════════════
    elementos.append(_bloque(
        "CONTENEDORES/MUNICIPIO (MUNICIPALES)",
        crear_tabla_contenedores(df_cont, es_fideicomiso=False),
        cw_municipales, space_before=0
    ))
    elementos.append(Spacer(1, 14))
    elementos.append(_bloque(
        "CONTENEDORES/MUNICIPIO (FIDEICOMISO)",
        crear_tabla_contenedores(df_fid, es_fideicomiso=True),
        cw_fideicomiso
    ))
    elementos.append(Spacer(1, 14))

    # Bloques lado a lado
    bloque_inst  = _bloque(
        "CONTENEDORES INSTALADOS/MUNICIPIO",
        crear_tabla_instalados(df_inst, col_widths=cw_instalados),
        cw_instalados, space_before=0
    )
    bloque_disp = _bloque(
        "DISPONIBILIDAD RECOLECCIÓN LATERAL/TURNO",
        crear_tabla_disponibilidad(df_disp, col_widths=cw_disponibil),
        cw_disponibil, space_before=0
    )

    master_lado = Table(
        [[bloque_inst, '', bloque_disp]],
        colWidths=[sum(cw_instalados), gap_lado, sum(cw_disponibil)]
    )
    master_lado.setStyle(TableStyle([
        ('VALIGN',        (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING',   (0, 0), (-1, -1), 0),
        ('RIGHTPADDING',  (0, 0), (-1, -1), 0),
        ('TOPPADDING',    (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
    ]))
    master_lado.hAlign = 'LEFT'
    elementos.append(master_lado)

    # ── Construir ──
    doc.build(elementos)
    print(f"Informe A4 vertical generado: {output_path}  (Fecha: {fecha_fmt})")


# ─── Ejecución directa ────────────────────────────────────────────────────────
if __name__ == "__main__":
    base_dir  = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(base_dir, "informe_diario_a4v_test.pdf")
    generar_informe_diario_a4v_pdf(file_path)
