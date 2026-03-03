import os
from datetime import datetime
import pandas as pd
import pyreadr
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Table, TableStyle, 
    Paragraph, Spacer, Image
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT

# --- 1. DATOS DE PRUEBA (DUMMY DATA) PARA DISPONIBILIDAD Y TONELADAS ---
def get_dummy_data_extra():
    # Tabla 2: DISPONIBILIDAD RECOLECCIÓN LATERAL
    data_disponibilidad = {
        'TURNO': ['M', 'V', 'N', 'Total'],
        'CAM_INICIO': [30, 26, 31, 87],
        'CAM_USADOS': [13, 2, 24, 39],
        'CHOFERES': [16, 2, 29, 47],
        'AUXILIARES': [13, 4, 25, 42]
    }
    df_disponibilidad = pd.DataFrame(data_disponibilidad)

    # Tabla 3: CONTENEDORES INSTALADOS
    data_instalados = {
        'MUNICIPIO': ['A', 'B', 'C', 'CH', 'D', 'E', 'F', 'G', 'Total'],
        'CONT_INSTALADOS': [1366, 1342, 1575, 1156, 1369, 1548, 1359, 1370, 11085]
    }
    df_instalados = pd.DataFrame(data_instalados)

    # Datos Sueltos: Toneladas
    toneladas_sdfr = "269"
    toneladas_pta = "3,5"
    return df_disponibilidad, df_instalados, toneladas_sdfr, toneladas_pta

def load_real_data(base_dir):
    data_dir = os.path.join(base_dir, "data")
    path_im = os.path.join(data_dir, "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds")
    path_fid = os.path.join(data_dir, "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds")

    try:
        df_im_full = pyreadr.read_r(path_im)[None]
        df_fid_full = pyreadr.read_r(path_fid)[None]
    except Exception as e:
        print(f"Error cargando RDS: {e}")
        return pd.DataFrame(), pd.DataFrame(), pd.Timestamp.now().date()

    df_im_full['Fecha_dt'] = pd.to_datetime(df_im_full['Fecha'], dayfirst=False)
    df_fid_full['Fecha_dt'] = pd.to_datetime(df_fid_full['Fecha'], dayfirst=False)

    ultima_fecha = max(df_im_full['Fecha_dt'].max(), df_fid_full['Fecha_dt'].max())

    fecha_env = os.environ.get("FECHA_REPORTE")
    if fecha_env:
        try:
            fecha_ingresada = pd.to_datetime(fecha_env).normalize()
            if fecha_ingresada > ultima_fecha.normalize():
                raise ValueError(f"Error: La fecha ingresada ({fecha_ingresada.strftime('%Y-%m-%d')}) es mayor al último dato disponible.")
            fecha_reporte = fecha_ingresada
        except ValueError as e:
            print(f"Advertencia al parsear FECHA_REPORTE: {e}. Se usará la fecha por defecto.")
            fecha_reporte = ultima_fecha.normalize()
    else:
        fecha_reporte = ultima_fecha.normalize()

    df_im = df_im_full[df_im_full['Fecha_dt'].dt.normalize() == fecha_reporte].copy()
    df_fid = df_fid_full[df_fid_full['Fecha_dt'].dt.normalize() == fecha_reporte].copy()

    def procesar_tabla(df_in):
        if df_in.empty:
            return pd.DataFrame(columns=['MUNICIPIO', 'TURNO', 'PLANIF.', 'PROGRAMADOS', 'VISITADOS', 'NO VISITADOS', 'VACIADOS', 'NO VACIADOS'])

        for col in ['Planificados', 'Programado', 'Visitados', 'No_visitados', 'Vaciados', 'No_Vaciados']:
            if col not in df_in.columns:
                df_in[col] = 0

        df = df_in[['Municipio', 'Turno', 'Planificados', 'Programado', 'Visitados', 'No_visitados', 'Vaciados', 'No_Vaciados']].copy()

        for col in ['Planificados', 'Programado', 'Visitados', 'No_visitados', 'Vaciados', 'No_Vaciados']:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)

        df.columns = ['MUNICIPIO', 'TURNO', 'PLANIF.', 'PROGRAMADOS', 'VISITADOS', 'NO VISITADOS', 'VACIADOS', 'NO VACIADOS']

        total_row = df[['PLANIF.', 'PROGRAMADOS', 'VISITADOS', 'NO VISITADOS', 'VACIADOS', 'NO VACIADOS']].sum()
        total_dict = {
            'MUNICIPIO': 'Total',
            'TURNO': '',
            **total_row.to_dict()
        }

        df = pd.concat([df, pd.DataFrame([total_dict])], ignore_index=True)
        return df

    return procesar_tabla(df_im), procesar_tabla(df_fid), fecha_reporte


# --- 2. FUNCIONES DE DISEÑO Y TABLAS ---
azul_header = colors.HexColor("#0044CC")
celeste_texto = colors.HexColor("#0070C0")
celeste_linea = colors.HexColor("#3399FF")
gris_claro = colors.HexColor("#EAEAEA")

def draw_header_footer(canvas, doc):
    canvas.saveState()
    # Barra Azul Superior (Reducida)
    canvas.setFillColor(azul_header)
    canvas.rect(0, doc.pagesize[1] - 2*cm, doc.pagesize[0], 2*cm, stroke=0, fill=1)
    
    # Barra Azul Inferior (Reducida)
    canvas.rect(0, 0, doc.pagesize[0], 1*cm, stroke=0, fill=1)

    # Logo Texto (Placeholder ya que no tenemos la imagen exacta)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 18)
    canvas.drawString(1.5*cm, doc.pagesize[1] - 1.2*cm, "Intendencia")
    canvas.drawString(1.5*cm, doc.pagesize[1] - 1.7*cm, "Montevideo")

    canvas.restoreState()

def crear_tabla_contenedores(df):
    headers = ["MUNICIPIO", "TURNO", "PLANIF.", "PROGRAMADOS", "VISITADOS", "NO VISITADOS", "VACIADOS", "NO VACIADOS"]
    data = [headers] + df.astype(str).values.tolist()
    
    col_widths = [1.8*cm, 2.5*cm, 1.8*cm, 2.8*cm, 2.1*cm, 2.6*cm, 2.1*cm, 2.0*cm]
    t = Table(data, colWidths=col_widths)
    
    estilo = TableStyle([
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-BoldOblique'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.black),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
        ('TOPPADDING', (0, 0), (-1, -1), 1),
        # Linea general superior en negro
        ('LINEABOVE', (0, 0), (-1, 0), 1, colors.black),
        ('LINEBELOW', (0, 0), (-1, 0), 1, colors.black),
        # Fila Total
        ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
        ('LINEABOVE', (0, -1), (-1, -1), 1, colors.black),
        ('LINEBELOW', (0, -1), (-1, -1), 1, colors.black),
    ])
    
    # Fondo intercalado segun imagen (pares blanco, impares gris, ignorando headers)
    for i in range(1, len(data) - 1):
        if i % 2 == 0:
            estilo.add('BACKGROUND', (0, i), (-1, i), gris_claro)
            
    t.setStyle(estilo)
    return t

def crear_tabla_disponibilidad(df):
    headers_1 = ["", "DISPONIBILIDAD RECOLECCIÓN LATERAL/TURNO", "", "", ""]
    headers_2 = ["TURNO", "CAM.\nINICIO", "CAM.\nUSADOS", "CHOFERES", "AUXILIARES"]
    
    data = [headers_1, headers_2] + df.astype(str).values.tolist()
    col_widths = [1.4*cm, 1.9*cm, 1.9*cm, 1.9*cm, 1.9*cm]
    t = Table(data, colWidths=col_widths)
    
    estilo = TableStyle([
        ('SPAN', (1, 0), (-1, 0)),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('FONTNAME', (0, 1), (-1, 1), 'Helvetica-Oblique'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
        ('TOPPADDING', (0, 0), (-1, -1), 1),
        ('TEXTCOLOR', (1, 0), (1, 0), celeste_texto),
        ('FONTNAME', (1, 0), (1, 0), 'Helvetica-BoldOblique'),
        ('LINEBELOW', (1, 0), (-1, 0), 1, colors.black),
        ('LINEABOVE', (0, 1), (-1, 1), 1, colors.black),
        ('LINEBELOW', (0, 1), (-1, 1), 1, colors.black),
        ('TEXTCOLOR', (1, 1), (-1, 1), colors.black),
        
        # Color cyan a 'TURNO' column y 'CAM INICIO'
        ('TEXTCOLOR', (1, 2), (1, 4), celeste_texto),
        ('TEXTCOLOR', (0, 2), (0, 4), celeste_texto),

        # Total fila
        ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
        ('TEXTCOLOR', (0, -1), (-1, -1), colors.black),
        ('TEXTCOLOR', (1, -1), (1, -1), celeste_texto),
        ('LINEABOVE', (0, -1), (-1, -1), 1, colors.black),
        ('LINEBELOW', (0, -1), (-1, -1), 1, colors.black),
    ])
    
    # Fondos intercalados dinámicos (empezando en la fila 2 de datos)
    for i in range(2, len(data) - 1):
        if i % 2 == 1: # Equivalente visual a las grises
            estilo.add('BACKGROUND', (0, i), (-1, i), gris_claro)
    t.setStyle(estilo)
    return t

def crear_tabla_instalados(df):
    headers_1 = ["", "CONTENEDORES INSTALADOS/MUNCIPIO"]
    headers_2 = ["MUNICIPIO", "CONT. INSTALADOS EN VÍA PÚBLICA"]
    data = [headers_1, headers_2] + df.astype(str).values.tolist()
    
    col_widths = [2.5*cm, 6.5*cm]
    t = Table(data, colWidths=col_widths)
    
    estilo = TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('FONTNAME', (1, 0), (1, 0), 'Helvetica-BoldOblique'),
        ('TEXTCOLOR', (1, 0), (1, 0), celeste_texto),
        ('FONTNAME', (0, 1), (-1, 1), 'Helvetica-Oblique'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
        ('TOPPADDING', (0, 0), (-1, -1), 1),
        
        # Lineas Negras
        ('LINEBELOW', (1, 0), (1, 0), 1, colors.black),
        ('LINEABOVE', (0, 1), (-1, 1), 1, colors.black),
        ('LINEBELOW', (0, 1), (-1, 1), 1, colors.black),
        
        # Total Fila
        ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
        ('LINEABOVE', (0, -1), (-1, -1), 1, colors.black),
        ('LINEBELOW', (0, -1), (-1, -1), 1, colors.black),
    ])
    
    # Intercalado dinámico
    for i in range(2, len(data) - 1):
        if i % 2 == 1:
            estilo.add('BACKGROUND', (0, i), (-1, i), gris_claro)
    t.setStyle(estilo)
    return t

def crear_toneladas_bloque(sdfr, pta):
    estilos = getSampleStyleSheet()
    estilo_titulo = ParagraphStyle(
        'TitTon', parent=estilos['Normal'], fontName='Helvetica-BoldOblique', 
        fontSize=10, textColor=celeste_texto, alignment=TA_CENTER
    )
    estilo_sub = ParagraphStyle('SubTon', parent=estilos['Normal'], fontName='Helvetica-Oblique', fontSize=9, alignment=TA_CENTER)
    estilo_num = ParagraphStyle('NumTon', parent=estilos['Normal'], fontName='Helvetica-Bold', fontSize=18, alignment=TA_CENTER)
    
    # Armar la tabla de 3 filas
    data = [
        [Paragraph("<u>TONELADAS (RESIDUOS MEZCLADOS* Y MATERIAL RECICLABLE**)</u>", estilo_titulo), ""],
        [Paragraph("INGRESO SDFR*", estilo_sub), Paragraph("INGRESO PTA CLASIF.**", estilo_sub)],
        [Paragraph(sdfr, estilo_num), Paragraph(pta, estilo_num)]
    ]
    t = Table(data, colWidths=[4.5*cm, 4.5*cm])
    t.setStyle(TableStyle([
        ('SPAN', (0, 0), (1, 0)),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('LINEABOVE', (0, 1), (-1, 1), 1, colors.black),
        ('LINEBELOW', (0, 1), (-1, 1), 1, colors.black),
        ('LINEBELOW', (0, 2), (-1, 2), 1, colors.black),
        ('BACKGROUND', (0, 2), (-1, 2), gris_claro)
    ]))
    return t

# --- 3. GENERADOR PRINCIPAL ---
def generar_informe_diario_pdf(output_path):
    base_dir = os.path.dirname(os.path.abspath(output_path))
    if "informe_test_visual.pdf" in output_path:
        base_dir = os.path.dirname(os.path.abspath(__file__))

    df_cont, df_fid, fecha_objetivo = load_real_data(base_dir)
    df_disp, df_inst, t_sdfr, t_pta = get_dummy_data_extra()
    
    # Doc config (Usar Landscape de A4)
    doc = BaseDocTemplate(output_path, pagesize=landscape(A4),
                          leftMargin=1.0*cm, rightMargin=1.0*cm,
                          topMargin=2.6*cm, bottomMargin=1.2*cm)
    
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='normal')
    template = PageTemplate(id='Principal', frames=frame, onPage=draw_header_footer)
    doc.addPageTemplates([template])
    
    elementos = []
    
    # --- Estructura Master Tabla (1 fila, 2 columnas grandes) ---
    t_im = crear_tabla_contenedores(df_cont)
    t_fid = crear_tabla_contenedores(df_fid)

    estilos = getSampleStyleSheet()
    titulo_im = Paragraph("<u>CONTENEDORES/MUNICIPIO (MUNICIPALES)</u>", ParagraphStyle('tit1', parent=estilos['Normal'], fontName='Helvetica-BoldOblique', fontSize=10, textColor=celeste_texto, spaceAfter=5))
    titulo_fid = Paragraph("<u>CONTENEDORES/MUNICIPIO (FIDEICOMISO)</u>", ParagraphStyle('tit2', parent=estilos['Normal'], fontName='Helvetica-BoldOblique', fontSize=10, textColor=celeste_texto, spaceAfter=5, spaceBefore=10))

    # Alinear título izquierdo con Fila 2 derecha (empujando 14 puntos)
    datos_izq = [[Spacer(1, 14)], [titulo_im], [t_im], [titulo_fid], [t_fid]]
    t_izq = Table(datos_izq)
    t_izq.setStyle(TableStyle([
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0)
    ]))
    
    # Bloque Derecho (apilado)
    b_ton = crear_toneladas_bloque(t_sdfr, t_pta)
    b_disp = crear_tabla_disponibilidad(df_disp)
    b_inst = crear_tabla_instalados(df_inst)
    
    # Calculo y Alineación Dinámica de los Pies (Bottoms)
    w_izq, h_izq = t_izq.wrap(17.7*cm, 800)
    w_ton, h_ton = b_ton.wrap(9.0*cm, 800)
    w_disp, h_disp = b_disp.wrap(9.0*cm, 800)
    w_inst, h_inst = b_inst.wrap(9.0*cm, 800)
    
    h_derecha_fija = h_ton + h_disp + h_inst
    espacio_restante = h_izq - h_derecha_fija
    
    if espacio_restante > 0:
        espacio_medio = espacio_restante / 2.0
        datos_der = [[b_ton], [Spacer(1, espacio_medio)], [b_disp], [Spacer(1, espacio_medio)], [b_inst]]
    else:
        datos_der = [[b_ton], [Spacer(1, 0.4*cm)], [b_disp], [Spacer(1, 0.4*cm)], [b_inst]]
        
    t_der = Table(datos_der)
    t_der.setStyle(TableStyle([
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0)
    ]))
    
    # 3 Columnas: Izq, Vacia(Spacer horizontal), Der
    master_data = [[t_izq, '', t_der]]
    master_table = Table(master_data, colWidths=[17.7*cm, 1.0*cm, 9.0*cm])
    master_table.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('ALIGN', (0, 0), (0, 0), 'LEFT'),
        ('ALIGN', (2, 0), (2, 0), 'RIGHT'),
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0)
    ]))
    
    elementos.append(master_table)
    
    doc.build(elementos)
    fecha_fmt = fecha_objetivo.strftime('%d/%m/%Y')
    print(f"Informe Diario generado: {output_path} (Fecha de datos: {fecha_fmt})")

if __name__ == "__main__":
    base_dir = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(base_dir, "informe_test_visual.pdf")
    generar_informe_diario_pdf(file_path)
