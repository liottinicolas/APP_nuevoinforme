import pandas as pd
import matplotlib.pyplot as plt
import io
import os
import numpy as np
import pyreadr
from datetime import datetime, timedelta
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import cm
from reportlab.platypus import BaseDocTemplate, PageTemplate, Frame, NextPageTemplate, Table, TableStyle, Paragraph, Spacer, Image, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

def load_and_prepare_data(base_dir, opcion):
    data_dir = os.path.join(base_dir, "data")
    if opcion == "Solo IM":
        path_prueba = os.path.join(data_dir, "informediarionuevo_total_soloim_criterioadrian.rds")
        path_viajes = os.path.join(data_dir, "total_viajesporcamionsoloim_criterioadrian.rds")
    else:
        path_prueba = os.path.join(data_dir, "informediarionuevo_total_imyfideicomiso_criterioadrian.rds")
        path_viajes = os.path.join(data_dir, "total_viajesporcamionIM_fid_criterioadrian.rds")
        
    res_prueba = pyreadr.read_r(path_prueba)
    res_viajes = pyreadr.read_r(path_viajes)
    
    prueba_adrian = res_prueba[None]
    total_viajes = res_viajes[None]
    
    if 'Fecha' in prueba_adrian.columns:
        prueba_adrian['Fecha'] = pd.to_datetime(prueba_adrian['Fecha']).dt.date
    if 'Fecha' in total_viajes.columns:
        total_viajes['Fecha'] = pd.to_datetime(total_viajes['Fecha']).dt.date
        
    if 'Turno' in prueba_adrian.columns:
        prueba_adrian.rename(columns={'Turno': 'Turno_levantado'}, inplace=True)
    if 'Turno' in total_viajes.columns:
        total_viajes.rename(columns={'Turno': 'Turno_levantado'}, inplace=True)
        
    # Filtrar últimos 30 días respecto al día de ayer
    ayer = datetime.now().date() - timedelta(days=1)
    hace_30_dias = ayer - timedelta(days=29)
    
    prueba_adrian = prueba_adrian[(prueba_adrian['Fecha'] >= hace_30_dias) & (prueba_adrian['Fecha'] <= ayer)]
    total_viajes = total_viajes[(total_viajes['Fecha'] >= hace_30_dias) & (total_viajes['Fecha'] <= ayer)]
    
    return prueba_adrian, total_viajes

def procesar_datos_pivot(df, col_valores, turnos):
    if df.empty:
        return pd.DataFrame()
        
    agrupado = df.groupby(['Fecha', 'Turno_levantado'])[col_valores].sum().reset_index()
    pivot = agrupado.pivot(index='Fecha', columns='Turno_levantado', values=col_valores).fillna(0)
    
    for t in turnos:
        if t not in pivot.columns:
            pivot[t] = 0
            
    pivot = pivot[turnos]
    pivot['Total general'] = pivot.sum(axis=1)
    
    return pivot.reset_index()

def crear_grafico_apilado(df, titulo, ylabel, colores_turno):
    # Usar un tamaño más apto para hoja horizontal (landscape)
    fig, ax = plt.subplots(figsize=(14, 8))
    
    turnos = ["Matutino", "Vespertino", "Nocturno"]
    df_plot = df.set_index('Fecha')[turnos]
    
    # Colores institucionales
    colores_lista = [colores_turno[t] for t in turnos]
    
    bottom = np.zeros(len(df_plot))
    x_labels = df_plot.index.astype(str).tolist()
    
    for i, turno in enumerate(turnos):
        values = df_plot[turno].values
        bars = ax.bar(x_labels, values, bottom=bottom, label=turno, color=colores_lista[i], edgecolor='black')
        
        # Etiquetar cada barra
        for bar, val in zip(bars, values):
            if val > 0:
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_y() + bar.get_height() / 2,
                    f'{int(val)}',
                    ha='center', va='center', color='black', fontsize=9
                )
        bottom += values

    # Etiquetas de totales
    for idx, total in enumerate(bottom):
        if total > 0:
            ax.text(idx, total + (total * 0.02), f'{int(total)}', ha='center', va='bottom', fontsize=10, fontweight='bold')

    ax.set_title(titulo, fontsize=14, pad=15)
    ax.set_ylabel(ylabel)
    # Movemos la leyenda abajo, al centro, en columnas horizontales
    ax.legend(title="Turno", loc='upper center', bbox_to_anchor=(0.5, -0.15), ncol=3)
    ax.set_xticks(range(len(x_labels)))
    ax.set_xticklabels(x_labels, rotation=45, ha='right', fontsize=8)
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    
    plt.tight_layout()
    img_buffer = io.BytesIO()
    plt.savefig(img_buffer, format='png', bbox_inches='tight', dpi=150)
    img_buffer.seek(0)
    plt.close(fig)
    return img_buffer

def generar_tabla(df_pivot, turnos):
    df_str = df_pivot.copy()
    
    df_str['Fecha'] = df_str['Fecha'].astype(str)
    for col in turnos + ['Total general']:
        df_str[col] = df_str[col].astype(int).astype(str)
        
    df_str = df_str.sort_values(by='Fecha', ascending=False)
    
    columnas = ['Fecha'] + turnos + ['Total general']
    datos_tabla = [columnas] + df_str[columnas].values.tolist()
    
    t = Table(datos_tabla, colWidths=[3*cm, 2.5*cm, 2.5*cm, 2.5*cm, 3*cm])
    
    estilo_t = TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.Color(0.85, 0.85, 0.85)),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.black),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('LINEBELOW', (0, 0), (-1, 0), 1.5, colors.dodgerblue),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.whitesmoke, colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
    ])
    t.setStyle(estilo_t)
    return t

def pie_de_pagina(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    linea1 = "Edificio Sede. Av. 18 de Julio 1360. Piso 6 y 2. CP 11200. Montevideo, Uruguay."
    linea2 = "Tel: (598 2) 1950 3740. Spaa.planificacion@imm.gub.uy"
    
    # Tomar el ancho actual de la página (portrait o landscape)
    ancho_pagina = canvas._pagesize[0]
    canvas.drawCentredString(ancho_pagina/2, 1.5*cm, linea1)
    canvas.drawCentredString(ancho_pagina/2, 1.1*cm, linea2)
    canvas.restoreState()

def create_pdf_report_reportlab(opcion, output_filename):
    print(f"Generando reporte PDF ({opcion}) con ReportLab...")
    base_dir = os.path.dirname(os.path.abspath(__file__))
    df_vaciados, df_camiones = load_and_prepare_data(base_dir, opcion)
    
    if df_vaciados.empty or df_camiones.empty:
        print(f"No hay datos para {opcion} en los últimos 30 días.")
        return
        
    col_vaciados = next((col for col in ['Vaciados', 'Total_Vaciados'] if col in df_vaciados.columns), None)
    if not col_vaciados:
        num_cols = df_vaciados.select_dtypes(include='number').columns
        col_vaciados = num_cols[0] if len(num_cols) > 0 else 'Vaciados_Suma'
        
    turnos = ["Matutino", "Vespertino", "Nocturno"]
    
    pivot_vaciados = procesar_datos_pivot(df_vaciados, col_vaciados, turnos)
    pivot_camiones = procesar_datos_pivot(df_camiones, 'Camiones', turnos)
    
    output_path = os.path.join(base_dir, output_filename)
    
    # Usar BaseDocTemplate en vez de SimpleDocTemplate para permitir múltiples tamaños de página
    doc = BaseDocTemplate(output_path, pagesize=A4, 
                          rightMargin=1.5*cm, leftMargin=1.5*cm, 
                          topMargin=1.5*cm, bottomMargin=2.5*cm)
                          
    # Definir marcos para Portrait
    frame_portrait = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='portrait_frame')
    
    # Definir marcos para Landscape
    ancho_landscape = A4[1]
    alto_landscape = A4[0]
    frame_landscape = Frame(doc.leftMargin, doc.bottomMargin, ancho_landscape - 3*cm, alto_landscape - 4*cm, id='landscape_frame')

    # Crear los PageTemplates y asociar el pie de página
    template_portrait = PageTemplate(id='Portrait', frames=frame_portrait, onPage=pie_de_pagina, pagesize=A4)
    template_landscape = PageTemplate(id='Landscape', frames=frame_landscape, onPage=pie_de_pagina, pagesize=landscape(A4))
    
    doc.addPageTemplates([template_portrait, template_landscape])

    elementos = []
    estilos = getSampleStyleSheet()
    
    estilo_titulo = ParagraphStyle('Titulo', parent=estilos['Heading1'], fontSize=12, spaceAfter=10)
    estilo_sub = ParagraphStyle('Subtitulo', parent=estilos['Heading2'], fontSize=11, spaceAfter=5, textColor=colors.dodgerblue)
    
    fecha_ayer = (datetime.now().date() - timedelta(days=1)).strftime("%d/%m/%Y")
    
    # La cabecera se agrega UNA sola vez al principio
    # Posibilidad de agregar el logo "adelante" del título
    ruta_logo = os.path.join(base_dir, "logo.png")
    if os.path.exists(ruta_logo):
        # Se alinea a la izquierda o al centro, según la estética (usamos CENTER por defecto, o LEFT si prefieres al lado del texto)
        img_logo = Image(ruta_logo, width=3*cm, height=3*cm, hAlign='CENTER')
        elementos.append(img_logo)
        elementos.append(Spacer(1, 10))

    elementos.append(Paragraph("<b>Intendencia de Montevideo</b>", estilo_titulo))
    elementos.append(Paragraph("DEPARTAMENTO DESARROLLO AMBIENTAL", estilos['Normal']))
    elementos.append(Paragraph("DIVISIÓN LIMPIEZA Y GESTIÓN DE RESIDUOS", estilos['Normal']))
    elementos.append(Spacer(1, 10))
    elementos.append(Paragraph(f"<b>ANÁLISIS DE CONTENEDORES Y CAMIONES POR TURNO - {fecha_ayer}</b>", estilo_titulo))
    if opcion == "Solo IM":
        subt = "<i>Ámbito: Sólo IM. Se toma como inicial el turno Nocturno del día anterior. Datos extraídos del sistema GOL.</i>"
    else:
        subt = "<i>Ámbito: IM y Fideicomiso. Se toma como inicial el turno Nocturno del día anterior. Datos extraídos del sistema GOL.</i>"
    elementos.append(Paragraph(subt, estilos['Italic']))
    elementos.append(Spacer(1, 15))

    colores_turno = {
        "Matutino": "#FFFF00", 
        "Vespertino": "#FFCC00", 
        "Nocturno": "#555555"
    }
    
    # === SECCIÓN VACIADOS ===
    elementos.append(Paragraph("<b>1. Contenedores Vaciados</b>", estilo_sub))
    elementos.append(Spacer(1, 10))
    elementos.append(generar_tabla(pivot_vaciados, turnos))
    
    elementos.append(NextPageTemplate('Landscape'))
    elementos.append(PageBreak())
    
    grafico_v = crear_grafico_apilado(pivot_vaciados, f"Suma de Contenedores Vaciados por Turno\n{opcion} (Últimos 30 días)", "Suma de contenedores", colores_turno)
    # Tamaño para ocupar gran parte de la hoja horizontal
    elementos.append(Image(grafico_v, width=26*cm, height=14*cm))
    
    elementos.append(NextPageTemplate('Portrait'))
    elementos.append(PageBreak())
    
    # === SECCIÓN CAMIONES ===
    elementos.append(Paragraph("<b>2. Camiones Utilizados</b>", estilo_sub))
    elementos.append(Spacer(1, 10))
    elementos.append(generar_tabla(pivot_camiones, turnos))
    
    elementos.append(NextPageTemplate('Landscape'))
    elementos.append(PageBreak())
    
    grafico_c = crear_grafico_apilado(pivot_camiones, f"Cantidad de Camiones por Turno\n{opcion} (Últimos 30 días)", "Cantidad de Camiones", colores_turno)
    elementos.append(Image(grafico_c, width=26*cm, height=14*cm))
    
    doc.build(elementos)
    print(f"Reporte '{output_filename}' generado exitosamente.")

if __name__ == "__main__":
    create_pdf_report_reportlab("Solo IM", "Reporte_IM_Ultimos_30_Dias_ReportLab.pdf")
    create_pdf_report_reportlab("IM y Fideicomiso", "Reporte_IM_Fideicomiso_Ultimos_30_Dias_ReportLab.pdf")
