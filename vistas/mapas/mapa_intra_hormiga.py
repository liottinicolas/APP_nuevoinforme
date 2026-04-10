import folium
import geopandas as gpd
from folium.plugins import AntPath
from folium.features import DivIcon

# 1. CARGAR DATOS
# Capa de Municipios/Intra (Polígonos)
gdf_intra = gpd.read_file("vistas/mapas/capa_intra_montevideo.geojson")
# Capa de Recorrido Sisconve (Puntos)
gdf_recorrido = gpd.read_file("vistas/mapas/SIM.json")

# --- LIMPIEZA Y PROYECCIÓN ---
# Corregir fechas en ambas capas para evitar error de Serialización
for df in [gdf_intra, gdf_recorrido]:
    for col in df.columns:
        if 'date' in str(df[col].dtype) or col in ['tiempo', 'FECHA.DESDE']:
            df[col] = df[col].astype(str)
    # Asegurar WGS84
    if df.crs != "EPSG:4326":
        df.to_crs(epsg=4326, inplace=True)

# 2. CREAR MAPA BASE
mapa_mvd = folium.Map(location=[-34.85, -56.16], zoom_start=12, tiles="OpenStreetMap")

# 3. CAPA WMS (Cartografía oficial de la IM como fondo)
folium.WmsTileLayer(
    url="https://montevideo.gub.uy/app/geowebcache/service/wms",
    layers="mapstore-base:capas_base",
    fmt="image/png",
    transparent=True,
    version="1.1.1",
    attr="Intendencia de Montevideo",
    name="Mapa Base (WMS)",
    overlay=False  # Se usa como base
).add_to(mapa_mvd)

# 4. CAPA DE POLÍGONOS (Municipios / Intra)
folium.GeoJson(
    gdf_intra,
    name="División Territorial (Intra)",
    style_function=lambda x: {
        'fillColor': 'royalblue',
        'color': 'blue',
        'weight': 1,
        'fillOpacity': 0.2
    },
    tooltip=folium.GeoJsonTooltip(
        fields=['nombre', 'municipio'],
        aliases=['Zona:', 'Municipio:']
    )
).add_to(mapa_mvd)

# 5. RECORRIDO "HORMIGA" (AntPath)
puntos_recorrido = [[p.y, p.x] for p in gdf_recorrido.geometry]

AntPath(
    locations=puntos_recorrido,
    delay=5000,
    dash_array=[10, 20],
    color="darkred",
    pulse_color="white",
    weight=4,
    opacity=0.9,
    name="Trayectoria (Hormigas)"
).add_to(mapa_mvd)

# 6. CAPA DE FLECHAS (Orientación Sisconve)
capa_flechas = folium.FeatureGroup(name="Puntos y Orientación")

for idx, fila in gdf_recorrido.iterrows():
    angulo = fila['orientacion']
    
    icon_html = f"""
        <div style="transform: rotate({angulo}deg);">
            <svg viewBox="0 0 24 24" width="18" height="18">
                <path d="M12 2L4.5 20.29L5.21 21L12 18L18.79 21L19.5 20.29L12 2Z" fill="red"/>
            </svg>
        </div>"""

    folium.Marker(
        location=[fila.geometry.y, fila.geometry.x],
        icon=DivIcon(html=icon_html, icon_size=(18,18), icon_anchor=(9,9)),
        popup=(f"<b>Unidad:</b> {fila['matricula']}<br>"
               f"<b>Velocidad:</b> {fila['velocidad']} km/h<br>"
               f"<b>Hora:</b> {fila['tiempo']}")
    ).add_to(capa_flechas)

capa_flechas.add_to(mapa_mvd)

# 7. CONTROL DE CAPAS Y GUARDADO
folium.LayerControl(collapsed=False).add_to(mapa_mvd)

mapa_mvd.save("vistas/mapas/mapa_completo_final.html")

print("Mapa completo generado con éxito.")
