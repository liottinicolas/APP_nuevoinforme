import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import pyreadr
from datetime import datetime, timedelta
import os

st.set_page_config(
    page_title="Reporte contenedores vaciados por turno",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ----------------- NAVEGACIÓN (PÁGINAS) -----------------
st.sidebar.header("Navegación")
opcion_datos = st.sidebar.radio(
    "Seleccione el origen de datos:",
    ("Solo IM", "IM y Fideicomiso")
)

@st.cache_data(ttl=300) # Expira y recarga datos cada 5 minutos
def load_data(opcion):
    try:
        # Cargar los datos desde los archivos .rds alojados en la carpeta "data"
        base_dir = os.path.dirname(os.path.abspath(__file__))
        data_dir = os.path.join(base_dir, "data")
        
        if opcion == "Solo IM":
            path_prueba = os.path.join(data_dir, "informediarionuevo_total_soloim_criterioadrian.rds")
            path_viajes = os.path.join(data_dir, "total_viajesporcamionsoloim_criterioadrian.rds")
        else:
            path_prueba = os.path.join(data_dir, "informediarionuevo_total_imyfideicomiso_criterioadrian.rds")
            path_viajes = os.path.join(data_dir, "total_viajesporcamionIM_fid_criterioadrian.rds")
        
        # Leer .rds usando pyreadr
        res_prueba = pyreadr.read_r(path_prueba)
        res_viajes = pyreadr.read_r(path_viajes)
        
        prueba_adrian = res_prueba[None]
        total_viajes = res_viajes[None]
        
        # Asegurar tipos correctos y estandarizar nombres de columnas
        if 'Fecha' in prueba_adrian.columns:
            prueba_adrian['Fecha'] = pd.to_datetime(prueba_adrian['Fecha']).dt.date
        if 'Fecha' in total_viajes.columns:
            total_viajes['Fecha'] = pd.to_datetime(total_viajes['Fecha']).dt.date
            
        if 'Turno' in prueba_adrian.columns:
            prueba_adrian.rename(columns={'Turno': 'Turno_levantado'}, inplace=True)
        if 'Turno' in total_viajes.columns:
            total_viajes.rename(columns={'Turno': 'Turno_levantado'}, inplace=True)

        return prueba_adrian, total_viajes
        
    except Exception as e:
        st.error(f"Error al cargar los datos para {opcion}: {e}")
        st.info("Asegúrese de que los archivos .rds existan en la carpeta 'data'.")
        return pd.DataFrame(), pd.DataFrame()

# Cargar datos según selección
prueba_adrian, total_viajes = load_data(opcion_datos)

st.title(f"Reporte contenedores vaciados por turno ({opcion_datos})")

if prueba_adrian.empty or total_viajes.empty:
    st.warning(f"No hay datos disponibles para la opción: {opcion_datos}.")
    st.stop()

# Filtro general: Hasta ayer
ayer = datetime.now().date() - timedelta(days=1)
prueba_adrian = prueba_adrian[prueba_adrian['Fecha'] <= ayer]
total_viajes = total_viajes[total_viajes['Fecha'] <= ayer]

# Colores para los turnos
colores_turno = {
    "Matutino": "#FFFF00",
    "Vespertino": "#FFCC00",
    "Nocturno": "#4D4D4D"
}

# ----------------- BARRA LATERAL (FILTROS) -----------------
st.sidebar.markdown("---")
st.sidebar.header("Filtros")

# Rango de fechas
min_date = min(prueba_adrian['Fecha'].min(), total_viajes['Fecha'].min())
max_date = max(prueba_adrian['Fecha'].max(), total_viajes['Fecha'].max())
default_start_date = max(min_date, max_date - timedelta(days=30))

rango_fechas = st.sidebar.date_input(
    "Seleccione el período:",
    value=(default_start_date, max_date),
    min_value=min_date,
    max_value=max_date
)

# Turnos
todos_los_turnos = ["Matutino", "Vespertino", "Nocturno"]
turnos_seleccionados = st.sidebar.multiselect(
    "Turno de Levantado",
    options=todos_los_turnos,
    default=todos_los_turnos
)

# ----------------- PROCESAMIENTO CON FILTROS -----------------

# Aplicar filtros
if len(rango_fechas) == 2:
    start_date, end_date = rango_fechas
elif len(rango_fechas) == 1:
    # Si el usuario solo ha seleccionado la primera fecha en el calendario
    start_date = end_date = rango_fechas[0]
else:
    st.warning("Por favor, seleccione un rango de fechas.")
    st.stop()
    
# Filtrar prueba_adrian (Vaciados)
df_vaciados = prueba_adrian[
    (prueba_adrian['Fecha'] >= start_date) & 
    (prueba_adrian['Fecha'] <= end_date) &
    (prueba_adrian['Turno_levantado'].isin(turnos_seleccionados))
]

# Filtrar total_viajes (Camiones)
df_camiones = total_viajes[
    (total_viajes['Fecha'] >= start_date) & 
    (total_viajes['Fecha'] <= end_date) &
    (total_viajes['Turno_levantado'].isin(turnos_seleccionados))
]

# ----------------- TABS (PESTAÑAS) -----------------
tab1, tab2 = st.tabs(["Resultados principales (Vaciados)", "Datos camiones"])

with tab1:
    st.header("Resultados principales")
    
    # Datos agrupados para el gráfico de vaciados
    if 'Vaciados' in df_vaciados.columns:
        col_vaciados = 'Vaciados'
    elif 'Total_Vaciados' in df_vaciados.columns:
        col_vaciados = 'Total_Vaciados'
    else:
        # Por si el dataframe consolidado tiene otro nombre de suma
        # Tomaremos la primera columna numérica que no sea Fecha
        num_cols = df_vaciados.select_dtypes(include='number').columns
        col_vaciados = num_cols[0] if len(num_cols) > 0 else None

    if col_vaciados:
        vaciados_agrupados = df_vaciados.groupby(['Fecha', 'Turno_levantado'])[col_vaciados].sum().reset_index()
        vaciados_agrupados.rename(columns={col_vaciados: 'Vaciados_Suma'}, inplace=True)
        
        # Totales diarios para etiquetas
        totales_dia_vaciados = vaciados_agrupados.groupby('Fecha')['Vaciados_Suma'].sum().reset_index()
        
        # Gráfico Vaciados
        fig_vaciados = px.bar(
            vaciados_agrupados[vaciados_agrupados['Vaciados_Suma'] > 0], 
            x='Fecha', 
            y='Vaciados_Suma', 
            color='Turno_levantado',
            color_discrete_map=colores_turno,
            text='Vaciados_Suma',
            title='Suma de contenedores vaciados',
            category_orders={"Turno_levantado": ["Matutino", "Vespertino", "Nocturno"]}
        )
        
        # Añadir totales encima
        for index, row in totales_dia_vaciados.iterrows():
            if row['Vaciados_Suma'] > 0:
                fig_vaciados.add_annotation(
                    x=row['Fecha'],
                    y=row['Vaciados_Suma'],
                    text=str(int(row['Vaciados_Suma'])),
                    showarrow=False,
                    yshift=10,
                    font=dict(color="black", size=12)
                )
            
        fig_vaciados.update_layout(
            barmode='stack',
            xaxis_title="Fecha",
            yaxis_title="Suma de contenedores",
            xaxis=dict(tickangle=-45, tickformat="%d/%m/%y"),
            hovermode="x unified"
        )
        
        st.plotly_chart(fig_vaciados, use_container_width=True)
    
        # Tabla Vaciados
        st.subheader("Tabla de Datos")
        
        # Pivot table
        tabla_vaciados_pivot = vaciados_agrupados.pivot(
            index='Fecha', 
            columns='Turno_levantado', 
            values='Vaciados_Suma'
        ).fillna(0).reset_index()
        
        # Asegurar que todas las columnas de turno existan
        for t in todos_los_turnos:
            if t not in tabla_vaciados_pivot.columns:
                tabla_vaciados_pivot[t] = 0
                
        # Reordenar y sumar total general
        cols_turnos = [t for t in todos_los_turnos if t in tabla_vaciados_pivot.columns]
        tabla_vaciados_pivot['Total general'] = tabla_vaciados_pivot[cols_turnos].sum(axis=1)
        
        # Ordenar columnas final
        final_cols = ['Fecha'] + cols_turnos + ['Total general']
        tabla_vaciados_pivot = tabla_vaciados_pivot[final_cols]
        
        st.dataframe(
            tabla_vaciados_pivot.sort_values('Fecha', ascending=False),
            use_container_width=True,
            hide_index=True
        )

with tab2:
    st.header("Datos camiones")
    
    st.subheader("Gráfico de Camiones")
    
    # Totales diarios para etiquetas
    totales_dia_camiones = df_camiones.groupby('Fecha')['Camiones'].sum().reset_index()
    
    fig_camiones = px.bar(
        df_camiones[df_camiones['Camiones'] > 0], 
        x='Fecha', 
        y='Camiones', 
        color='Turno_levantado',
        color_discrete_map=colores_turno,
        title='Cantidad de Camiones por Turno',
        category_orders={"Turno_levantado": ["Matutino", "Vespertino", "Nocturno"]}
    )
    
    # Añadir totales encima
    for index, row in totales_dia_camiones.iterrows():
        if row['Camiones'] > 0:
            fig_camiones.add_annotation(
                x=row['Fecha'],
                y=row['Camiones'],
                text=str(int(row['Camiones'])),
                showarrow=False,
                yshift=10,
                font=dict(color="black", size=12)
            )
        
    fig_camiones.update_layout(
        barmode='stack',
        xaxis_title="Día",
        yaxis_title="Cantidad de Camiones",
        xaxis=dict(tickangle=-45, tickformat="%d/%m/%y"),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
    )
    
    st.plotly_chart(fig_camiones, use_container_width=True)
    
    st.subheader("Detalle de Camiones")
    
    # Pivot table
    tabla_camiones_pivot = df_camiones.pivot_table(
        index='Fecha', 
        columns='Turno_levantado', 
        values='Camiones',
        aggfunc='sum',
        fill_value=0
    ).reset_index()
    
    # Asegurar que todas las columnas de turno existan
    for t in todos_los_turnos:
        if t not in tabla_camiones_pivot.columns:
            tabla_camiones_pivot[t] = 0
            
    # Reordenar y sumar total general
    cols_turnos = [t for t in todos_los_turnos if t in tabla_camiones_pivot.columns]
    tabla_camiones_pivot['Total'] = tabla_camiones_pivot[cols_turnos].sum(axis=1)
    
    # Ordenar columnas final
    final_cols_camiones = ['Fecha'] + cols_turnos + ['Total']
    tabla_camiones_pivot = tabla_camiones_pivot[final_cols_camiones]
    
    st.dataframe(
        tabla_camiones_pivot.sort_values('Fecha', ascending=False),
        use_container_width=True,
        hide_index=True
    )
