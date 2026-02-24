import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import pyreadr
from datetime import datetime, timedelta
import os
import numpy as np

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

def plot_stacked_bar(ax, df, metric_col, title, colores):
    turnos = ["Matutino", "Vespertino", "Nocturno"]
    
    # Asegurar que todas las columnas de turno existan
    for t in turnos:
        if t not in df.columns:
            df[t] = 0
            
    df = df[turnos]
    bottom = np.zeros(len(df))
    
    x_labels = df.index.astype(str).tolist()
    
    for turno in turnos:
        values = df[turno].values
        # Dibujar las barras apiladas
        bars = ax.bar(x_labels, values, bottom=bottom, label=turno, color=colores.get(turno, "gray"), edgecolor='black')
        
        # Etiquetar cada barra
        for bar, val in zip(bars, values):
            if val > 0:  # Mostrar sólo donde haya datos
                # Etiqueta en el medio del segmento de barra
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_y() + bar.get_height() / 2,
                    f'{int(val)}',
                    ha='center', va='center', color='black', fontsize=9
                )
                
        bottom += values

    # Etiquetas de totales encima de cada columna
    for idx, total in enumerate(bottom):
        ax.text(idx, total + (total * 0.02), f'{int(total)}', ha='center', va='bottom', fontsize=11, fontweight='bold')
        
    ax.set_title(title, fontsize=14, pad=20)
    ax.set_xlabel("Fecha", fontsize=12, labelpad=15)
    ax.set_ylabel(metric_col, fontsize=12)
    
    # Leyenda abajo del gráfico para no tapar el título ni el ancho
    ax.legend(title="Turno", bbox_to_anchor=(0.5, -0.25), loc='upper center', ncol=3)
    
    # Rotar las etiquetas del eje x para mejor visibilidad
    ax.set_xticks(range(len(x_labels)))
    ax.set_xticklabels(x_labels, rotation=45, ha='right')
    ax.grid(axis='y', linestyle='--', alpha=0.7)

def plot_table(ax, df_table, title):
    ax.axis('tight')
    ax.axis('off')
    
    df_plot = df_table.copy()
    
    # Las fuentes de la tabla
    table = ax.table(
        cellText=df_plot.values, 
        colLabels=df_plot.columns, 
        loc='center', 
        cellLoc='center'
    )
    
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1, 1.4)
    
    # Estilizar cabeceras
    for (row, col), cell in table.get_celld().items():
        if row == 0:
            cell.set_text_props(weight='bold')
            cell.set_facecolor('#d9d9d9')
            
    ax.set_title(title, fontsize=16, pad=20, weight='bold')

def create_pdf_report(opcion, output_filename):
    print(f"Generando reporte para {opcion}...")
    base_dir = os.path.dirname(os.path.abspath(__file__))
    df_vaciados, df_camiones = load_and_prepare_data(base_dir, opcion)
    
    if df_vaciados.empty or df_camiones.empty:
        print(f"No hay datos para {opcion} en los últimos 30 días.")
        return
        
    colores_turno = {
        "Matutino": "#FFFF00",
        "Vespertino": "#FFCC00",
        "Nocturno": "#4D4D4D"
    }
    
    with PdfPages(os.path.join(base_dir, output_filename)) as pdf:
        
        # --- SECCIÓN VACIADOS ---
        col_vaciados = next((col for col in ['Vaciados', 'Total_Vaciados'] if col in df_vaciados.columns), None)
        if not col_vaciados:
            num_cols = df_vaciados.select_dtypes(include='number').columns
            col_vaciados = num_cols[0] if len(num_cols) > 0 else 'Vaciados_Suma'
            
        vaciados_agrupados = df_vaciados.groupby(['Fecha', 'Turno_levantado'])[col_vaciados].sum().reset_index()
        pivot_bar = vaciados_agrupados.pivot(index='Fecha', columns='Turno_levantado', values=col_vaciados).fillna(0)
        
        # 1. Tabla (Se muestra primero la tabla)
        turnos = ["Matutino", "Vespertino", "Nocturno"]
        for t in turnos:
            if t not in pivot_bar.columns:
                pivot_bar[t] = 0
                
        pivot_bar = pivot_bar[turnos]
        pivot_bar['Total general'] = pivot_bar.sum(axis=1)
        
        tabla_print = pivot_bar.reset_index()
        tabla_print['Fecha'] = tabla_print['Fecha'].astype(str)
        # Convertir todo a int si es necesario o strings formateados para no ver flotantes (.0)
        for col in turnos + ['Total general']:
            tabla_print[col] = tabla_print[col].astype(int).astype(str)
            
        tabla_print = tabla_print.sort_values(by='Fecha', ascending=False)
        
        fig, ax = plt.subplots(figsize=(8.27, 11.69)) # A4 Portrait for list
        plot_table(ax, tabla_print, f"Detalle de Contenedores Vaciados - {opcion}")
        plt.tight_layout()
        pdf.savefig(fig)
        plt.close()

        # 2. Gráfico (Se muestra después)
        fig, ax = plt.subplots(figsize=(11.69, 8.27)) # A4 Landscape
        plot_stacked_bar(
            ax, pivot_bar.drop(columns=['Total general']), "Suma de contenedores", 
            f"Suma de Contenedores Vaciados por Turno\n{opcion} (Últimos 30 días)", 
            colores_turno
        )
        plt.tight_layout()
        pdf.savefig(fig)
        plt.close()
        
        
        # --- SECCIÓN CAMIONES ---
        camiones_agrupados = df_camiones.groupby(['Fecha', 'Turno_levantado'])['Camiones'].sum().reset_index()
        pivot_cam = camiones_agrupados.pivot(index='Fecha', columns='Turno_levantado', values='Camiones').fillna(0)
        
        # 1. Tabla de Camiones (Primero)
        for t in turnos:
            if t not in pivot_cam.columns:
                pivot_cam[t] = 0
                
        pivot_cam = pivot_cam[turnos]
        pivot_cam['Total'] = pivot_cam.sum(axis=1)
        
        tabla_cam_print = pivot_cam.reset_index()
        tabla_cam_print['Fecha'] = tabla_cam_print['Fecha'].astype(str)
        
        for col in turnos + ['Total']:
            tabla_cam_print[col] = tabla_cam_print[col].astype(int).astype(str)
            
        tabla_cam_print = tabla_cam_print.sort_values(by='Fecha', ascending=False)
        
        fig, ax = plt.subplots(figsize=(8.27, 11.69)) # A4 Portrait
        plot_table(ax, tabla_cam_print, f"Detalle de Camiones Utilizados - {opcion}")
        plt.tight_layout()
        pdf.savefig(fig)
        plt.close()

        # 2. Gráfico de Camiones (Después)
        fig, ax = plt.subplots(figsize=(11.69, 8.27)) # A4 Landscape
        plot_stacked_bar(
            ax, pivot_cam.drop(columns=['Total']), "Cantidad de Camiones", 
            f"Cantidad de Camiones por Turno\n{opcion} (Últimos 30 días)", 
            colores_turno
        )
        plt.tight_layout()
        pdf.savefig(fig)
        plt.close()
        
    print(f"Reporte generado exitosamente: {output_filename}")

if __name__ == "__main__":
    create_pdf_report("Solo IM", "Reporte_IM_Ultimos_30_Dias.pdf")
    create_pdf_report("IM y Fideicomiso", "Reporte_IM_Fideicomiso_Ultimos_30_Dias.pdf")
