import folium
import geopandas as gpd
import pandas as pd
import sys
import os
import urllib3
from shapely.ops import transform
from branca.element import Template, MacroElement

# --- 1. CONFIGURACIÓN DE SEGURIDAD ---
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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
    ruta_salida_final = sys.argv[3] if len(sys.argv) > 3 else "vistas/mapas/mapa_paradas_unicamente.html"

    mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="CartoDB positron")
    
    # AGREGADO: "dia" en el diccionario resumen
    resumen_datos = {
        "zona": "N/A", 
        "fraccion": "N/A", 
        "matricula": "N/A", 
        "dia": "N/A", 
        "hora_inicio": "N/A", 
        "hora_fin": "N/A"
    }

    # --- 2. CAPA DEL SECTOR ---
    gdf_intra = None
    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra).to_crs(epsg=4326)
        if not gdf_intra.empty and gdf_intra.geometry.centroid.y.mean() < -45:
            gdf_intra.geometry = gdf_intra.geometry.map(lambda geom: transform(lambda x, y: (y, x), geom))

        folium.GeoJson(
            limpiar_para_json(gdf_intra.copy()),
            name="Sector de Trabajo",
            style_function=lambda x: {'fillColor': 'orange', 'color': 'darkorange', 'fillOpacity': 0.1}
        ).add_to(mapa)
        
        if not gdf_intra.empty:
            limites = gdf_intra.total_bounds
            mapa.fit_bounds([[limites[1], limites[0]], [limites[3], limites[2]]])

    # --- 3. CARGAR PUNTOS Y FILTRAR ---
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados).to_crs(epsg=4326)
        
        if not gdf_puntos.empty:
            if gdf_puntos.geometry.y.mean() < -45:
                gdf_puntos.geometry = gpd.points_from_xy(gdf_puntos.geometry.y, gdf_puntos.geometry.x)

            gdf_puntos = gdf_puntos[(gdf_puntos.geometry.x != 0) & (gdf_puntos.geometry.y != 0)]
            gdf_puntos = gdf_puntos.cx[-56.5:-55.8, -35.1:-34.5]

            gdf_puntos['t_dt'] = pd.to_datetime(gdf_puntos['tiempo'], dayfirst=True, errors='coerce')
            gdf_puntos = gdf_puntos.sort_values(by='t_dt')
            
            if not gdf_puntos.empty:
                # MODIFICACIÓN: Extraer el día y las horas
                resumen_datos.update({
                    "dia": gdf_puntos['t_dt'].min().strftime('%d/%m/%Y'),
                    "hora_inicio": gdf_puntos['t_dt'].min().strftime('%H:%M:%S'),
                    "hora_fin": gdf_puntos['t_dt'].max().strftime('%H:%M:%S'),
                    "zona": str(gdf_puntos['nombre'].iloc[0]) if 'nombre' in gdf_puntos.columns else "N/A",
                    "fraccion": str(gdf_puntos['FRACCION'].iloc[0]) if 'FRACCION' in gdf_puntos.columns else "N/A",
                    "matricula": str(gdf_puntos['matricula'].iloc[0]) if 'matricula' in gdf_puntos.columns else "N/A"
                })

                # --- 4. DIBUJAR SOLO PUNTOS DE PARADA ---
                gdf_puntos_json = limpiar_para_json(gdf_puntos.copy())
                for _, fila in gdf_puntos_json.iterrows():
                    try:
                        vel_val = float(fila['velocidad']) if fila['velocidad'] else 0
                    except (ValueError, TypeError):
                        vel_val = 0

                    if vel_val <= 5:
                        folium.CircleMarker(
                            location=[fila.geometry.y, fila.geometry.x],
                            radius=5,
                            color='white',
                            weight=1,
                            fill=True,
                            fill_color='#FF6600',
                            fill_opacity=0.9,
                            popup=f"<b>Parada Detectada</b><br>Hora: {fila['tiempo']}<br>Vel: {vel_val} km/h"
                        ).add_to(mapa)

    # --- 5. TARJETA INFORMATIVA AZUL (MODIFICADA PARA MOSTRAR EL DÍA) ---
    template = """
    {% macro html(this, kwargs) %}
    <div id='info-card' style='
        position: fixed; bottom: 50px; left: 50px; width: 260px; height: auto; 
        background-color: #0046E3; border: 1px solid white; z-index:9999; 
        font-size: 13px; color: white; padding: 15px; border-radius: 12px; 
        box-shadow: 0px 4px 10px rgba(0,0,0,0.3); font-family: sans-serif;'>
        <div style='text-align: center; font-weight: bold; margin-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.3); padding-bottom: 8px;'>
            MAPA DE PARADAS (<= 5 km/h)
        </div>
        <div style='line-height: 1.7;'>
            <b>Matrícula:</b> <span style='font-size: 14px;'>{{ this.matricula }}</span><br>
            <b>Día:</b> {{ this.dia }} <br>
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
            self.zona = d["zona"]
            self.fraccion = d["fraccion"]
            self.matricula = d["matricula"]
            self.dia = d["dia"] # AGREGADO
            self.hora_inicio = d["hora_inicio"]
            self.hora_fin = d["hora_fin"]

    mapa.get_root().add_child(InfoCard(resumen_datos))
    folium.LayerControl(collapsed=False).add_to(mapa)
    
    os.makedirs(os.path.dirname(ruta_salida_final), exist_ok=True)
    mapa.save(ruta_salida_final)
    print(f"✅ Proceso terminado. Mapa guardado en: {ruta_salida_final}")

if __name__ == "__main__":
    generar_mapa()
