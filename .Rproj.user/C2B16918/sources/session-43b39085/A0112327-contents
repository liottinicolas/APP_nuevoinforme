import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import os
from datetime import datetime, timedelta

# Intentar importar pyreadr de forma segura
try:
    import pyreadr
    PYREADR_AVAILABLE = True
except ImportError:
    PYREADR_AVAILABLE = False

# 1. CONFIGURACIÓN DE LA PÁGINA (Debe ser lo primero de Streamlit)
st.set_page_config(
    page_title="Informe de Gestión - Datos",
    page_icon="📋",
    layout="wide"
)

# 2. DEFINICIÓN DE LA FUNCIÓN CON CACHÉ
# He unido tus dos funciones en una sola que es más robusta
@st.cache_data(ttl=300)  # Se borra solo cada 1 hora
def cargar_datos_rds(ruta):
    if not os.path.exists(ruta):
        return None, f"Archivo no encontrado en: {ruta}"
    
    try:
        result = pyreadr.read_r(ruta)
        df = result[None] 
        if 'Fecha' in df.columns:
            df['Fecha'] = pd.to_datetime(df['Fecha'])
        return df, None
    except Exception as e:
        return None, f"Error al procesar el archivo: {e}"

# 3. LÓGICA DE RUTAS (Detectar si es local o Cloud)
script_dir = os.path.dirname(os.path.abspath(__file__))

# Lógica para encontrar la carpeta 'informediario'
if os.path.exists(os.path.join(script_dir, "informediario")):
    BASE_DIR = script_dir
else:
    BASE_DIR = os.path.dirname(script_dir) 

RUTA_ARCHIVO_LOCAL = os.path.join(BASE_DIR, "informediario", "data", "tabla_soloIM_resumen_pordia_municipio_turno_completo.rds")
RUTA_ARCHIVO_FID = os.path.join(BASE_DIR, "informediario", "data", "tabla_soloFID_resumen_pordia_municipio_turno_completo.rds")

# 4. PROCESO DE CARGA (Aquí es donde se llama a la función)
df_im, error_carga_im = cargar_datos_rds(RUTA_ARCHIVO_LOCAL)
df_fid, error_carga_fid = cargar_datos_rds(RUTA_ARCHIVO_FID)

# 5. VALIDACIÓN Y UI
if df_im is not None:
    st.sidebar.success(f"✅ Datos IM cargados")
else:
    st.sidebar.error(f"⚠️ IM: {error_carga_im}")
    st.stop() 

if df_fid is not None:
    st.sidebar.success(f"✅ Datos FID cargados")
else:
    st.sidebar.error(f"⚠️ FID: {error_carga_fid}")
    st.stop() 

# Crear alias para compatibilidad
df = df_im.copy()

# --- BARRA LATERAL: FILTROS ---
st.sidebar.header("Filtros de Tabla")

# 1. Filtro de Fecha (Selección ÚNICA)
if 'Fecha' in df.columns:
    df_fechas_limpias = df.dropna(subset=['Fecha'])
    min_fecha_data = df_fechas_limpias['Fecha'].min().date()
    max_fecha_data = df_fechas_limpias['Fecha'].max().date()
    
    # Al pasar un solo objeto date (no una tupla), Streamlit activa el selector de un solo día
    fecha_seleccionada = st.sidebar.date_input(
        "Seleccionar Fecha",
        value=max_fecha_data, 
        min_value=min_fecha_data,
        max_value=max_fecha_data
    )

# 2. Filtro de Municipio
if 'Municipio' in df.columns:
    lista_muni = sorted([str(x) for x in df['Municipio'].dropna().unique()])
    sel_muni = st.sidebar.multiselect("Filtrar Municipio", options=lista_muni, default=lista_muni)

# 3. Filtro de Turno
if 'Turno' in df.columns:
    lista_turno = sorted([str(x) for x in df['Turno'].dropna().unique()])
    sel_turno = st.sidebar.multiselect("Filtrar Turno", options=lista_turno, default=lista_turno)

# --- APLICAR FILTROS ---
df_filtrado = df.copy()

# Aplicar Filtro de Fecha Única
df_filtrado = df_filtrado[df_filtrado['Fecha'].dt.date == fecha_seleccionada]

# Aplicar Municipio y Turno
if 'Municipio' in df.columns and sel_muni:
    df_filtrado = df_filtrado[df_filtrado['Municipio'].astype(str).isin(sel_muni)]
if 'Turno' in df.columns and sel_turno:
    df_filtrado = df_filtrado[df_filtrado['Turno'].astype(str).isin(sel_turno)]

# --- APLICAR FILTROS FID (SOLO FECHA) ---
df_filtrado_fid = df_fid.copy()
if 'Fecha' in df_filtrado_fid.columns:
    df_filtrado_fid = df_filtrado_fid[df_filtrado_fid['Fecha'].dt.date == fecha_seleccionada]

# --- INTERFAZ PRINCIPAL ---
st.title("📋 Informe de Gestión diario")

tab_datos, tab_fid, tab_historico = st.tabs(["📋 Detalle Diario", "� Datos FID", "📈 Evolución Histórica"])

with tab_datos:
    # =====================================================================
    # SECCIÓN: DATOS DIARIOS
    # =====================================================================
    st.header("📋 Detalle del Día Seleccionado")
    st.markdown(f"**Visualizando registros del día: {fecha_seleccionada}**")

    # Espacio para KPIs rápidos del día seleccionado
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Visitados", f"{df_filtrado['Visitados'].sum():,}")
    with col2:
        st.metric("Vaciados", f"{df_filtrado['Vaciados'].sum():,}")
    with col3:
        prog_total = df_filtrado['Programado'].sum()
        eficiencia = (df_filtrado['Visitados'].sum() / prog_total * 100) if prog_total > 0 else 0
        st.metric("Eficiencia", f"{eficiencia:.1f}%")
    with col4:
        st.metric("Registros", len(df_filtrado))

    # Gráficos del Día
    req_cols = ['Planificados', 'Programado', 'Visitados', 'Vaciados']
    if not df_filtrado.empty and all(c in df_filtrado.columns for c in req_cols):
        col_g1, col_g2 = st.columns(2)
        
        with col_g1:
            st.markdown("**Totales del Día**")
            df_totales = pd.DataFrame({
                'Estado': req_cols,
                'Total': [df_filtrado[c].sum() for c in req_cols]
            })
            
            fig_totales = px.bar(
                df_totales,
                x='Estado',
                y='Total',
                color='Estado',
                text_auto=True,
                color_discrete_map={
                    'Planificados': '#1f77b4',
                    'Programado': '#ff7f0e',
                    'Visitados': '#2ca02c',
                    'Vaciados': '#d62728'
                }
            )
            fig_totales.update_layout(showlegend=False, xaxis_title="", yaxis_title="Cantidad")
            st.plotly_chart(fig_totales, use_container_width=True)
            
        with col_g2:
            if 'Municipio' in df_filtrado.columns:
                st.markdown("**Desglose por Municipio**")
                df_agrupado = df_filtrado.groupby('Municipio')[req_cols].sum().reset_index()
                df_melt = df_agrupado.melt(
                    id_vars=['Municipio'], 
                    value_vars=req_cols,
                    var_name='Estado', 
                    value_name='Cantidad'
                )
                
                fig_muni = px.bar(
                    df_melt, 
                    x='Municipio', 
                    y='Cantidad', 
                    color='Estado',
                    barmode='group',
                    text_auto=True,
                    color_discrete_map={
                        'Planificados': '#1f77b4',
                        'Programado': '#ff7f0e',
                        'Visitados': '#2ca02c',
                        'Vaciados': '#d62728'
                    }
                )
                fig_muni.update_layout(xaxis_title="Municipio", yaxis_title="Cantidad", hovermode="x unified")
                st.plotly_chart(fig_muni, use_container_width=True)

    st.markdown("---")

    # Visualización de la Tabla
    st.dataframe(
        df_filtrado, 
        use_container_width=True, 
        height=500, # Altura ajustada
        column_config={
            "Fecha": st.column_config.DateColumn(
                "Fecha",
                format="YYYY-MM-DD",
            )
        }
    )

    # Botón de descarga
    csv = df_filtrado.to_csv(index=False).encode('utf-8')
    st.download_button(
        label="📥 Descargar esta vista (CSV)",
        data=csv,
        file_name=f"informe_{fecha_seleccionada}.csv",
        mime='text/csv',
    )


with tab_fid:
    # =====================================================================
    # SECCIÓN: DATOS FID DIARIOS
    # =====================================================================
    st.header("📋 Detalle del Día Seleccionado (FID)")
    st.markdown(f"**Visualizando registros FID del día: {fecha_seleccionada}**")
    st.markdown("*(Esta vista ignora los filtros de Municipio y Turno de la barra lateral)*")

    # Espacio para KPIs rápidos del día seleccionado
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Visitados", f"{df_filtrado_fid['Visitados'].sum():,}")
    with col2:
        st.metric("Vaciados", f"{df_filtrado_fid['Vaciados'].sum():,}")
    with col3:
        prog_total = df_filtrado_fid['Programado'].sum()
        eficiencia = (df_filtrado_fid['Visitados'].sum() / prog_total * 100) if prog_total > 0 else 0
        st.metric("Eficiencia", f"{eficiencia:.1f}%")
    with col4:
        st.metric("Registros", len(df_filtrado_fid))

    # Gráficos del Día FID
    req_cols = ['Planificados', 'Programado', 'Visitados', 'Vaciados']
    if not df_filtrado_fid.empty and all(c in df_filtrado_fid.columns for c in req_cols):
        col_g1, col_g2 = st.columns(2)
        
        with col_g1:
            st.markdown("**Totales del Día (FID)**")
            df_totales = pd.DataFrame({
                'Estado': req_cols,
                'Total': [df_filtrado_fid[c].sum() for c in req_cols]
            })
            
            fig_totales = px.bar(
                df_totales,
                x='Estado',
                y='Total',
                color='Estado',
                text_auto=True,
                color_discrete_map={
                    'Planificados': '#1f77b4',
                    'Programado': '#ff7f0e',
                    'Visitados': '#2ca02c',
                    'Vaciados': '#d62728'
                }
            )
            fig_totales.update_layout(showlegend=False, xaxis_title="", yaxis_title="Cantidad")
            st.plotly_chart(fig_totales, use_container_width=True)
            
        with col_g2:
            if 'Municipio' in df_filtrado_fid.columns:
                st.markdown("**Desglose FID por Municipio**")
                df_agrupado = df_filtrado_fid.groupby('Municipio')[req_cols].sum().reset_index()
                df_melt = df_agrupado.melt(
                    id_vars=['Municipio'], 
                    value_vars=req_cols,
                    var_name='Estado', 
                    value_name='Cantidad'
                )
                
                fig_muni = px.bar(
                    df_melt, 
                    x='Municipio', 
                    y='Cantidad', 
                    color='Estado',
                    barmode='group',
                    text_auto=True,
                    color_discrete_map={
                        'Planificados': '#1f77b4',
                        'Programado': '#ff7f0e',
                        'Visitados': '#2ca02c',
                        'Vaciados': '#d62728'
                    }
                )
                fig_muni.update_layout(xaxis_title="Municipio", yaxis_title="Cantidad", hovermode="x unified")
                st.plotly_chart(fig_muni, use_container_width=True)

    st.markdown("---")

    # Visualización de la Tabla
    st.dataframe(
        df_filtrado_fid, 
        use_container_width=True, 
        column_config={
            "Fecha": st.column_config.DateColumn(
                "Fecha",
                format="YYYY-MM-DD",
            )
        }
    )

    # Botón de descarga
    csv_fid = df_filtrado_fid.to_csv(index=False).encode('utf-8')
    st.download_button(
        label="📥 Descargar esta vista FID (CSV)",
        data=csv_fid,
        file_name=f"informe_FID_{fecha_seleccionada}.csv",
        mime='text/csv',
    )


with tab_historico:
    # =====================================================================
    # SECCIÓN: HISTÓRICO
    # =====================================================================
    st.header("📈 Evolución Histórica General")
    st.markdown("Esta vista **no se ve afectada** por los filtros de Municipio o Turno de la barra lateral.")

    if 'Fecha' in df.columns:
        df_fechas_limpias = df.dropna(subset=['Fecha'])
        min_f = df_fechas_limpias['Fecha'].min().date()
        max_f = df_fechas_limpias['Fecha'].max().date()
        
        col_f1, col_f2 = st.columns(2)
        with col_f1:
            fecha_inicio = st.date_input("Fecha Inicio (Histórico)", value=min_f, min_value=min_f, max_value=max_f)
        with col_f2:
            fecha_fin = st.date_input("Fecha Fin (Histórico)", value=max_f, min_value=min_f, max_value=max_f)
            
        df_historico = df.copy()
            
        if fecha_inicio <= fecha_fin:
            mask = (df_historico['Fecha'].dt.date >= fecha_inicio) & (df_historico['Fecha'].dt.date <= fecha_fin)
            df_historico = df_historico[mask]
        else:
            st.warning("La fecha de inicio debe ser anterior a la fecha de fin.")
            df_historico = pd.DataFrame()

        req_cols = ['Planificados', 'Programado', 'Visitados', 'Vaciados']
        if not df_historico.empty and all(c in df_historico.columns for c in req_cols):
            df_tiempo = df_historico.groupby(df_historico['Fecha'].dt.date)[req_cols].sum().reset_index()
            # Asegurarse de que la fecha sea tipo datetime para plotly
            df_tiempo['Fecha'] = pd.to_datetime(df_tiempo['Fecha'])
            
            df_tiempo_melt = df_tiempo.melt(
                id_vars=['Fecha'],
                value_vars=req_cols,
                var_name='Estado',
                value_name='Cantidad'
            )
            fig_tiempo = px.line(
                df_tiempo_melt,
                x='Fecha',
                y='Cantidad',
                color='Estado',
                markers=False, # Sin puntos tal como se solicitó
                color_discrete_map={
                    'Planificados': '#1f77b4',
                    'Programado': '#ff7f0e',
                    'Visitados': '#2ca02c',
                    'Vaciados': '#d62728'
                }
            )
            # Formatear el eje X para mostrar correctamente las fechas sin horas
            fig_tiempo.update_layout(
                xaxis_title="Fecha", 
                yaxis_title="Cantidad", 
                hovermode="x unified",
                xaxis=dict(tickformat="%Y-%m-%d")
            )
            st.plotly_chart(fig_tiempo, use_container_width=True)
        else:
            st.info("No hay datos históricos en el rango seleccionado o faltan columnas requeridas.")
