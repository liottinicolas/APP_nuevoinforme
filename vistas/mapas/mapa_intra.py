import folium
import geopandas as gpd
import pandas as pd
import sys
import os
from folium.features import DivIcon
from branca.element import Template, MacroElement

def limpiar_para_json(gdf):
    if gdf is None or gdf.empty:
        return gdf
    for col in gdf.columns:
        if col != 'geometry':
            gdf[col] = gdf[col].astype(str).replace('NaT', '').replace('None', '')
    return gdf

def generar_mapa():
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None
    ruta_salida_final = sys.argv[3] if len(sys.argv) > 3 else "vistas/mapas/mapa_solapamiento_final.html"

    mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="CartoDB positron")
    
    resumen_datos = {
        "zona": "No definida", 
        "fraccion": "N/A",
        "matricula": "N/A",
        "hora_inicio": "N/A",
        "hora_fin": "N/A"
    }

    # --- 1. CARGAR CAPA INTRA ---
    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra)
        gdf_intra_4326 = gdf_intra.to_crs(epsg=4326)
        gdf_intra_4326 = limpiar_para_json(gdf_intra_4326)
        folium.GeoJson(
            gdf_intra_4326,
            name="Zona Filtrada",
            style_function=lambda x: {'fillColor': 'orange', 'color': 'darkorange', 'fillOpacity': 0.15}
        ).add_to(mapa)
        if not gdf_intra_4326.empty:
            limites = gdf_intra_4326.total_bounds
            mapa.fit_bounds([[limites[1], limites[0]], [limites[3], limites[2]]])

    # --- 2. CARGAR PUNTOS ---
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados)
        
        if not gdf_puntos.empty:
            if 'tiempo' in gdf_puntos.columns:
                gdf_puntos['tiempo_dt'] = pd.to_datetime(gdf_puntos['tiempo'], errors='coerce')
                gdf_puntos = gdf_puntos.sort_values(by='tiempo_dt')
                resumen_datos["hora_inicio"] = gdf_puntos['tiempo_dt'].min().strftime('%H:%M:%S')
                resumen_datos["hora_fin"] = gdf_puntos['tiempo_dt'].max().strftime('%H:%M:%S')

            resumen_datos["zona"] = str(gdf_puntos['nombre'].iloc[0]) if 'nombre' in gdf_puntos.columns else "N/A"
            resumen_datos["fraccion"] = str(gdf_puntos['FRACCION'].iloc[0]) if 'FRACCION' in gdf_puntos.columns else "N/A"
            resumen_datos["matricula"] = str(gdf_puntos['matricula'].iloc[0]) if 'matricula' in gdf_puntos.columns else "N/A"

            gdf_puntos_4326 = gdf_puntos.to_crs(epsg=4326)
            coords = [[f.geometry.y, f.geometry.x] for idx, f in gdf_puntos_4326.iterrows() if f.geometry]
            
            if coords:
                folium.PolyLine(
                    coords, color='#0046E3', weight=3, opacity=0.7, name="Trayectoria Real"
                ).add_to(mapa)

            gdf_puntos_limpio = limpiar_para_json(gdf_puntos_4326.copy())
            for _, fila in gdf_puntos_limpio.iterrows():
                if fila.geometry:
                    folium.CircleMarker(
                        location=[fila.geometry.y, fila.geometry.x], radius=3, color='#0046E3', fill=True,
                        popup=f"Hora: {fila.get('tiempo', 'N/A')}<br>Vel: {fila.get('velocidad', '0')} km/h"
                    ).add_to(mapa)

    # --- 3. TARJETA INFORMATIVA ---
    template = """
    {% macro html(this, kwargs) %}
    <div id='info-card' style='
        position: fixed; bottom: 50px; left: 50px; width: 260px; height: auto; 
        background-color: #0046E3; border: 1px solid white; z-index:9999; 
        font-size: 13px; color: white; padding: 15px; border-radius: 12px; 
        box-shadow: 0px 4px 10px rgba(0,0,0,0.3); font-family: sans-serif;'>
        <div style='text-align: center; font-weight: bold; margin-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.3); padding-bottom: 8px;'>
            RESUMEN DE ANÁLISIS
        </div>
        <div style='line-height: 1.7;'>
            <b>Matrícula:</b> <span style='font-size: 14px;'>{{ this.matricula }}</span><br>
            <b>Zona:</b> {{ this.zona }} <br>
            <b>Fracción:</b> {{ this.fraccion }} <br>
            <hr style='margin: 10px 0; border: 0; border-top: 1px solid rgba(255,255,255,0.3);'>
            <b>Inicio:</b> {{ this.hora_inicio }} <br>
            <b>Fin:</b> {{ this.hora_fin }} <br>
            <div style='text-align: center; margin-top: 15px;'>
                <img src="https://montevideo.gub.uy/modules/custom/im_logo/images/logo_im.png" 
                     style="width: 130px; filter: brightness(0) invert(1);">
            </div>
        </div>
    </div>
    {% endmacro %}
    """

    class InfoCard(MacroElement):
        def __init__(self, d):
            super(InfoCard, self).__init__()
            self._template = Template(template)
            self.zona, self.fraccion, self.matricula = d["zona"], d["fraccion"], d["matricula"]
            self.hora_inicio, self.hora_fin = d["hora_inicio"], d["hora_fin"]

    mapa.get_root().add_child(InfoCard(resumen_datos))
    folium.LayerControl(collapsed=False).add_to(mapa)
    os.makedirs(os.path.dirname(ruta_salida_final), exist_ok=True)
    mapa.save(ruta_salida_final)

if __name__ == "__main__":
    generar_mapa()
