import folium
import geopandas as gpd
import pandas as pd
import sys
import os
import osmnx as ox
import networkx as nx
import urllib3
from shapely.ops import transform
from branca.element import Template, MacroElement

# --- 1. CONFIGURACIÓN DE SEGURIDAD Y RED (IMM) ---
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
ox.settings.requests_kwargs = {'verify': False}
ox.settings.use_cache = True
ox.settings.log_console = False

def limpiar_para_json(gdf):
    """Evita errores de fechas (Timestamp) al convertir a mapa interactivo."""
    if gdf is None or gdf.empty:
        return gdf
    for col in gdf.columns:
        if col != 'geometry':
            gdf[col] = gdf[col].astype(str).replace('NaT', '').replace('None', '')
    return gdf

def generar_mapa():
    # Argumentos desde R
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None
    ruta_salida_final = sys.argv[3] if len(sys.argv) > 3 else "vistas/mapas/mapa_solapamiento_final.html"

    # Centro inicial en Montevideo
    mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="CartoDB positron")
    resumen_datos = {"zona": "N/A", "fraccion": "N/A", "matricula": "N/A", "hora_inicio": "N/A", "hora_fin": "N/A"}

    # --- 2. CARGAR CAPA DEL SECTOR (INTRA) ---
    gdf_intra = None
    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra).to_crs(epsg=4326)
        
        # FIX COORDENADAS INVERTIDAS EN SECTOR (ValueError corregido con .mean())
        if not gdf_intra.empty and gdf_intra.geometry.centroid.y.mean() < -45:
            print("🔄 Detectadas coordenadas invertidas en el SECTOR. Corrigiendo...")
            # Función para dar vuelta X e Y en polígonos
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
            # CORRECCIÓN DE COORDENADAS INVERTIDAS EN PUNTOS
            if gdf_puntos.geometry.y.mean() < -45:
                print("🔄 Detectadas coordenadas invertidas en PUNTOS. Corrigiendo...")
                gdf_puntos.geometry = gpd.points_from_xy(gdf_puntos.geometry.y, gdf_puntos.geometry.x)

            # FILTROS DE SEGURIDAD (Eliminar basura y puntos fuera de MVD)
            gdf_puntos = gdf_puntos[(gdf_puntos.geometry.x != 0) & (gdf_puntos.geometry.y != 0)]
            gdf_puntos = gdf_puntos.cx[-56.5:-55.8, -35.1:-34.5]

            # Procesar fechas y ordenar
            gdf_puntos['t_dt'] = pd.to_datetime(gdf_puntos['tiempo'], dayfirst=True, errors='coerce')
            gdf_puntos = gdf_puntos.sort_values(by='t_dt')
            
            if not gdf_puntos.empty:
                resumen_datos.update({
                    "hora_inicio": gdf_puntos['t_dt'].min().strftime('%H:%M:%S'),
                    "hora_fin": gdf_puntos['t_dt'].max().strftime('%H:%M:%S'),
                    "zona": str(gdf_puntos['nombre'].iloc[0]) if 'nombre' in gdf_puntos.columns else "N/A",
                    "fraccion": str(gdf_puntos['FRACCION'].iloc[0]) if 'FRACCION' in gdf_puntos.columns else "N/A",
                    "matricula": str(gdf_puntos['matricula'].iloc[0]) if 'matricula' in gdf_puntos.columns else "N/A"
                })

                # --- 4. MAP MATCHING (CALLES REALES) ---
                try:
                    print(f"Calculando ruta por calles para {resumen_datos['zona']}...")
                    poligono_sector = gdf_intra.geometry.iloc[0]
                    # Buffer pequeño para asegurar que bajamos todas las calles necesarias
                    G = ox.graph_from_polygon(poligono_sector.buffer(0.005), network_type='drive')
                    
                    ruta_final = []
                    for i in range(len(gdf_puntos) - 1):
                        p1, p2 = gdf_puntos.iloc[i].geometry, gdf_puntos.iloc[i+1].geometry
                        u = ox.distance.nearest_nodes(G, p1.x, p1.y)
                        v = ox.distance.nearest_nodes(G, p2.x, p2.y)
                        
                        try:
                            camino = nx.shortest_path(G, u, v, weight='length')
                            puntos_calle = ox.util_graph.get_route_edge_attributes(G, camino, 'geometry')
                            for edge in puntos_calle:
                                if edge:
                                    y, x = edge.xy
                                    ruta_final.extend(list(zip(y, x)))
                        except:
                            ruta_final.append([p1.y, p1.x]); ruta_final.append([p2.y, p2.x])

                    if ruta_final:
                        folium.PolyLine(ruta_final, color='#0046E3', weight=4, opacity=0.75).add_to(mapa)
                    print("✅ Ruta por calles generada con éxito.")

                except Exception as e:
                    print(f"⚠️ Usando líneas directas ({e})")
                    coords_linea = [[p.y, p.x] for p in gdf_puntos.geometry]
                    folium.PolyLine(coords_linea, color='#0046E3', weight=3, opacity=0.6).add_to(mapa)

                # --- 5. DIBUJAR MARCADORES (Puntos) ---
                gdf_puntos_json = limpiar_para_json(gdf_puntos.copy())
                for _, fila in gdf_puntos_json.iterrows():
                    vel = pd.to_numeric(fila.get('velocidad', 0), errors='coerce')
                    # Naranja para paradas, Verde para movimiento
                    color_m = '#FF6600' if vel <= 5 else '#33CC33'
                    
                    folium.CircleMarker(
                        location=[fila.geometry.y, fila.geometry.x],
                        radius=4, color='white', weight=1, fill=True,
                        fill_color=color_m, fill_opacity=1,
                        popup=f"Hora: {fila['tiempo']}<br>Vel: {fila['velocidad']} km/h"
                    ).add_to(mapa)

    # --- 6. TARJETA INFORMATIVA AZUL ---
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
    print(f"✅ Proceso terminado. Mapa guardado en: {ruta_salida_final}")

if __name__ == "__main__":
    generar_mapa()
