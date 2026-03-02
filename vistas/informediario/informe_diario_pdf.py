import os
from datetime import datetime
import pandas as pd
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Table, TableStyle, 
    Paragraph, Spacer, Image
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT

# --- 1. DATOS DE PRUEBA (DUMMY DATA) ---
def get_dummy_data():
    # Tabla 1: CONTENEDORES/MUNICIPIO
    data_contenedores = {
        'MUNICIPIO': ['A', 'A', 'A', 'B', 'B', 'B', 'C', 'C', 'C', 'CH', 'CH', 'CH', 'D', 'D', 'D', 'E', 'E', 'E', 'F', 'F', 'F', 'G', 'G', 'G', 'Total'],
        'TURNO': ['Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', 'Matutino', 'Vespertino', 'Nocturno', ''],
        'PLANIF.': [303, 0, 0, 0, 0, 45, 0, 0, 952, 0, 0, 1158, 235, 0, 0, 0, 40, 177, 174, 93, 0, 100, 0, 187, 3464],
        'PROGRAMADOS': [370, 101, 0, 0, 0, 95, 0, 0, 954, 0, 0, 1161, 155, 0, 0, 308, 0, 195, 188, 0, 0, 425, 0, 0, 3952],
        'VISITADOS': [225, 79, 0, 0, 0, 67, 0, 0, 680, 0, 0, 1100, 108, 0, 0, 112, 0, 189, 150, 0, 0, 346, 0, 0, 3056],
        'NO VISITADOS': [145, 22, 0, 0, 0, 28, 0, 0, 274, 0, 0, 61, 47, 0, 0, 196, 0, 6, 38, 0, 0, 79, 0, 0, 896],
        'VACIADOS': [201, 69, 0, 0, 0, 65, 0, 0, 659, 0, 0, 1088, 94, 0, 0, 102, 0, 188, 126, 0, 0, 309, 0, 0, 2901],
        'NO VACIADOS': [24, 10, 0, 0, 0, 2, 0, 0, 21, 0, 0, 12, 14, 0, 0, 10, 0, 1, 24, 0, 0, 37, 0, 0, 155]
    }
    df_contenedores = pd.DataFrame(data_contenedores)
    # Tabla 1b: FIDEICOMISO
    data_fideicomiso = {
        'MUNICIPIO': ['B', 'B', 'Total'],
        'TURNO': ['Matutino', 'Nocturno', ''],
        'PLANIF.': [100, 150, 250],
        'PROGRAMADOS': [110, 140, 250],
        'VISITADOS': [90, 130, 220],
        'NO VISITADOS': [20, 10, 30],
        'VACIADOS': [85, 125, 210],
        'NO VACIADOS': [5, 5, 10]
    }
    df_fideicomiso = pd.DataFrame(data_fideicomiso)

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
    return df_contenedores, df_fideicomiso, df_disponibilidad, df_instalados, toneladas_sdfr, toneladas_pta

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
def generar_informe_diario_pdf(output_path, fecha="01/03/2026"):
    df_cont, df_fid, df_disp, df_inst, t_sdfr, t_pta = get_dummy_data()
    
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
    print(f"Informe Diario generado: {output_path}")

if __name__ == "__main__":
    base_dir = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(base_dir, "informe_test_visual.pdf")
    generar_informe_diario_pdf(file_path)
