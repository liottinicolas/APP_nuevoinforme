import pandas as pd
import matplotlib
matplotlib.use('Agg') # backend sin GUI
import matplotlib.pyplot as plt
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

# 1. GENERACIÓN DEL GRÁFICO (Matplotlib)
def crear_grafico_apilado(df):
    # Colores institucionales: Amarillo (M), Naranja (V), Gris (N)
    colores = ['#ffff00', '#ffcc00', '#555555'] 
    
    fig, ax = plt.subplots(figsize=(10, 5))
    # Graficamos solo las columnas de turnos
    df_plot = df.set_index('Fecha')[['Matutino', 'Vespertino', 'Nocturno']]
    df_plot.plot(kind='bar', stacked=True, color=colores, ax=ax, width=0.8)
    
    ax.set_title("Contenedores vaciados por turno - Últimos 30 días", fontsize=12, pad=15)
    ax.set_ylabel("Cantidad de contenedores")
    ax.legend(["Matutino", "Vespertino", "Nocturno"], loc='upper right')
    plt.xticks(rotation=45, ha='right', fontsize=8)
    
    # Guardar en buffer para ReportLab
    img_buffer = io.BytesIO()
    plt.savefig(img_buffer, format='png', bbox_inches='tight', dpi=150)
    img_buffer.seek(0)
    plt.close()
    return img_buffer

# 2. FUNCIÓN PARA EL PIE DE PÁGINA (Canvas)
def pie_de_pagina(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    # Información de contacto según el documento original
    linea1 = "Edificio Sede. Av. 18 de Julio 1360. Piso 6 y 2. CP 11200. Montevideo, Uruguay."
    linea2 = "Tel: (598 2) 1950 3740. Spaa.planificacion@imm.gub.uy"
    
    canvas.drawCentredString(A4[0]/2, 1.5*cm, linea1)
    canvas.drawCentredString(A4[0]/2, 1.1*cm, linea2)
    canvas.restoreState()

# 3. CONSTRUCCIÓN DEL PDF
def generar_reporte_completo(df, nombre_salida):
    # Calcular fecha para el título y filtrar el dataframe
    # "que la ultima fecha del informe, sea el dia anterior a esa ultima fecha"
    df['Fecha_dt'] = pd.to_datetime(df['Fecha'], dayfirst=True)
    ultima_fecha_dataset = df['Fecha_dt'].max()
    fecha_reporte = ultima_fecha_dataset - pd.Timedelta(days=1)
    
    # Filtrar datos (descartar la última fecha real)
    df = df[df['Fecha_dt'] <= fecha_reporte].copy()
    df = df.drop(columns=['Fecha_dt'])
    
    fecha_str = fecha_reporte.strftime("%d/%m/%Y")

    doc = SimpleDocTemplate(nombre_salida, pagesize=A4, 
                            rightMargin=1.5*cm, leftMargin=1.5*cm, 
                            topMargin=1.5*cm, bottomMargin=2.5*cm)
    elementos = []
    estilos = getSampleStyleSheet()

    # --- ENCABEZADO ---
    estilo_titulo = ParagraphStyle('Titulo', parent=estilos['Heading1'], fontSize=12, spaceAfter=10)
    
    import os
    ruta_logo = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo.png")
    if os.path.exists(ruta_logo):
        # Logo achicado a 4 cm de ancho x 1.5 cm de alto
        img_logo = Image(ruta_logo, width=4*cm, height=1.5*cm, hAlign='LEFT')
        elementos.append(img_logo)
        elementos.append(Spacer(1, 5))

    elementos.append(Paragraph("<b>Intendencia de Montevideo</b>", estilo_titulo))
    elementos.append(Paragraph("DEPARTAMENTO DESARROLLO AMBIENTAL", estilos['Normal']))
    elementos.append(Paragraph("DIVISIÓN LIMPIEZA Y GESTIÓN DE RESIDUOS", estilos['Normal']))
    elementos.append(Spacer(1, 10))
    
    # Título del reporte dinámico
    elementos.append(Paragraph(f"<b>ANÁLISIS DE CONTENEDORES MUNICIPALES Y FIDEICOMISO VACIADOS POR TURNO - {fecha_str}</b>", estilo_titulo))
    elementos.append(Paragraph("<i>Se toma como inicial el turno Nocturno del día anterior. Los datos son extraídos del sistema GOL.</i>", estilos['Italic']))
    elementos.append(Spacer(1, 15))

    # --- TABLA DE DATOS ---
    # Preparar datos (Source 9: Fecha, Matutino, Vespertino, Nocturno, Total general)
    datos_tabla = [df.columns.tolist()] + df.values.tolist()
    
    # Ajustar anchos de columna proporcionalmente
    t = Table(datos_tabla, colWidths=[3*cm, 2.5*cm, 2.5*cm, 2.5*cm, 3*cm])
    
    estilo_t = TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.white),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.black),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('LINEBELOW', (0, 0), (-1, 0), 1.5, colors.dodgerblue),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.whitesmoke, colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
    ])
    t.setStyle(estilo_t)
    elementos.append(t)
    elementos.append(Spacer(1, 25))

    # --- GRÁFICO ---
    grafico = crear_grafico_apilado(df)
    elementos.append(Image(grafico, width=16*cm, height=8*cm))

    # Generar el documento final vinculando el pie de página
    doc.build(elementos, onFirstPage=pie_de_pagina, onLaterPages=pie_de_pagina)
    print(f"Reporte '{nombre_salida}' generado exitosamente.")

# --- EJECUCIÓN ---
# Ejemplo de cómo debería ser tu DataFrame (basado en Source 9)
data = {
    'Fecha': ['25/1/2026', '26/1/2026', '27/1/2026', '28/1/2026', '29/1/2026'],
    'Matutino': [1816, 1831, 1941, 1462, 1933],
    'Vespertino': [166, 484, 428, 0, 658],
    'Nocturno': [463, 2327, 2599, 2584, 2440],
    'Total general': [2445, 4642, 4968, 4046, 5031]
}
df_user = pd.DataFrame(data)

generar_reporte_completo(df_user, "Reporte_IM_Final.pdf")
