import folium
import geopandas as gpd
import sys
import os
from folium.features import DivIcon
from branca.element import Template, MacroElement

def limpiar_para_json(gdf):
    """Convierte todas las columnas (excepto geometría) a string para evitar errores de Timestamp"""
    if gdf is None or gdf.empty:
        return gdf
    for col in gdf.columns:
        if col != 'geometry':
            # Forzamos todo a string, manejando valores nulos
            gdf[col] = gdf[col].astype(str).replace('NaT', '').replace('None', '')
    return gdf

def generar_mapa():
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None

    # Usamos CartoDB para evitar bloqueos y tener un mapa limpio
    mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="CartoDB positron")
    
    #mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="OpenStreetMap")
    
    # mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", attr='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors')
    
    
 
    resumen_datos = {"zona": "No definida", "puntos": 0}

    # --- 2. CARGAR Y LIMPIAR CAPA INTRA ---
    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra)
        gdf_intra_4326 = gdf_intra.to_crs(epsg=4326)
        
        # Limpieza agresiva de Timestamps
        gdf_intra_4326 = limpiar_para_json(gdf_intra_4326)
        
        if 'NOMBRE' in gdf_intra_4326.columns:
            resumen_datos["zona"] = str(gdf_intra_4326['NOMBRE'].iloc[0])

        folium.GeoJson(
            gdf_intra_4326,
            name="Zona Filtrada",
            style_function=lambda x: {'fillColor': 'orange', 'color': 'darkorange', 'fillOpacity': 0.2}
        ).add_to(mapa)

        if not gdf_intra_4326.empty:
            limites = gdf_intra_4326.total_bounds
            mapa.fit_bounds([[limites[1], limites[0]], [limites[3], limites[2]]])

    # --- 3. CARGAR Y LIMPIAR PUNTOS SOLAPADOS ---
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados)
        gdf_puntos_4326 = gdf_puntos.to_crs(epsg=4326)
        
        # Limpieza agresiva de Timestamps en puntos también
        gdf_puntos_4326 = limpiar_para_json(gdf_puntos_4326)
        resumen_datos["puntos"] = len(gdf_puntos_4326)

        capa_solape = folium.FeatureGroup(name="Puntos en la Zona")
        for idx, fila in gdf_puntos_4326.iterrows():
            if fila.geometry:
                folium.CircleMarker(
                    location=[fila.geometry.y, fila.geometry.x],
                    radius=6, color='red', fill=True, fill_color='red', fill_opacity=0.8,
                    popup=f"<b>Solapado</b><br>Velocidad: {fila.get('velocidad', 'N/A')} km/h"
                ).add_to(capa_solape)
        capa_solape.add_to(mapa)

    # --- 4. TARJETA INFORMATIVA (HTML/CSS) ---
    template = """
    {% macro html(this, kwargs) %}
    <div id='info-card' style='
        position: fixed; 
        bottom: 50px; left: 50px; width: 220px; height: auto; 
        background-color: white; border:2px solid #ccc; z-index:9999; font-size:14px;
        padding: 10px; border-radius: 10px; box-shadow: 2px 2px 5px rgba(0,0,0,0.2);
        font-family: sans-serif;
        '>
        <div style='text-align: center; font-weight: bold; margin-bottom: 5px; border-bottom: 1px solid #eee;'>
            Resumen de Análisis
        </div>
        <div style='margin-top: 5px;'>
            <b>Zona:</b> {{ this.zona }} <br>
            <b>Puntos:</b> {{ this.puntos }} <br>
            <hr style='margin: 5px 0; border: 0; border-top: 1px solid #eee;'>
            <small style='color: #666;'>Intendencia de Montevideo</small>
        </div>
    </div>
    {% endmacro %}
    """

    class InfoCard(MacroElement):
        def __init__(self, zona, puntos):
            super(InfoCard, self).__init__()
            self._template = Template(template)
            self.zona = zona
            self.puntos = puntos

    mapa.get_root().add_child(InfoCard(resumen_datos["zona"], resumen_datos["puntos"]))

    # --- 5. FINALIZAR ---
    folium.LayerControl(collapsed=False).add_to(mapa)
    os.makedirs("vistas/mapas", exist_ok=True)
    mapa.save("vistas/mapas/mapa_solapamiento_final.html")
    print("Mapa generado correctamente.")

if __name__ == "__main__":
    generar_mapa()
