import folium
import geopandas as gpd
import pandas as pd
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
            gdf[col] = gdf[col].astype(str).replace('NaT', '').replace('None', '')
    return gdf

def generar_mapa():
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None

    mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="CartoDB positron")
    
    resumen_datos = {
        "zona": "No definida", 
        "fraccion": "N/A",
        "matricula": "N/A",
        "hora_inicio": "N/A",
        "hora_fin": "N/A"
    }

    # --- 2. CARGAR CAPA INTRA ---
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

    # --- 3. CARGAR PUNTOS Y FILTRAR ---
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados)
        
        if not gdf_puntos.empty:
            # Ordenar cronológicamente
            if 'tiempo' in gdf_puntos.columns:
                gdf_puntos['tiempo_dt'] = pd.to_datetime(gdf_puntos['tiempo'], errors='coerce')
                gdf_puntos = gdf_puntos.sort_values(by='tiempo_dt')
                resumen_datos["hora_inicio"] = gdf_puntos['tiempo_dt'].min().strftime('%H:%M:%S')
                resumen_datos["hora_fin"] = gdf_puntos['tiempo_dt'].max().strftime('%H:%M:%S')

            # Datos para tarjeta
            if 'nombre' in gdf_puntos.columns: resumen_datos["zona"] = str(gdf_puntos['nombre'].iloc[0])
            if 'FRACCION' in gdf_puntos.columns: resumen_datos["fraccion"] = str(gdf_puntos['FRACCION'].iloc[0])
            if 'matricula' in gdf_puntos.columns: resumen_datos["matricula"] = str(gdf_puntos['matricula'].iloc[0])

            gdf_puntos_4326 = gdf_puntos.to_crs(epsg=4326)

            # --- A. TRAYECTORIA AZUL (TODOS los puntos) ---
            coordenadas_todas = [[f.geometry.y, f.geometry.x] for idx, f in gdf_puntos_4326.iterrows() if f.geometry]
            if coordenadas_todas:
                folium.PolyLine(
                    locations=coordenadas_todas,
                    color='#0046E3',
                    weight=3,
                    opacity=0.7,
                    name="Trayectoria Completa"
                ).add_to(mapa)

            # --- B. PUNTOS NEGROS (Solo velocidad <= 5) ---
            # Aseguramos que velocidad sea numérica para poder comparar
            gdf_puntos_4326['velocidad_num'] = pd.to_numeric(gdf_puntos_4326['velocidad'], errors='coerce')
            
            # Filtramos: solo puntos con velocidad menor o igual a 5
            gdf_lentos = gdf_puntos_4326[gdf_puntos_4326['velocidad_num'] <= 5].copy()
            
            # Limpiamos solo el dataframe filtrado para los popups
            gdf_lentos_limpio = limpiar_para_json(gdf_lentos)

            capa_puntos = folium.FeatureGroup(name="Puntos Velocidad ≤ 5")
            for idx, fila in gdf_lentos_limpio.iterrows():
                if fila.geometry:
                    folium.CircleMarker(
                        location=[fila.geometry.y, fila.geometry.x],
                        radius=3,
                        color='#0046E3',
                        weight=1,
                        fill=True,
                        fill_color='#0046E3',
                        fill_opacity=1,
                        popup=f"Hora: {fila.get('tiempo', 'N/A')}<br>Velocidad: {fila.get('velocidad', '0')} km/h"
                    ).add_to(capa_puntos)
            capa_puntos.add_to(mapa)

    # --- 4. TARJETA INFORMATIVA AZUL ---
    template = """
    {% macro html(this, kwargs) %}
    <div id='info-card' style='
        position: fixed; 
        bottom: 50px; left: 50px; width: 260px; height: auto; 
        background-color: #0046E3; border: 1px solid white; z-index:9999; 
        font-size: 13px; color: white; padding: 15px; border-radius: 12px; 
        box-shadow: 0px 4px 10px rgba(0,0,0,0.3);
        font-family: sans-serif;
        '>
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
        def __init__(self, datos):
            super(InfoCard, self).__init__()
            self._template = Template(template)
            self.zona = datos["zona"]
            self.fraccion = datos["fraccion"]
            self.matricula = datos["matricula"]
            self.hora_inicio = datos["hora_inicio"]
            self.hora_fin = datos["hora_fin"]

    mapa.get_root().add_child(InfoCard(resumen_datos))

    # --- 5. FINALIZAR ---
    folium.LayerControl(collapsed=False).add_to(mapa)
    os.makedirs("vistas/mapas", exist_ok=True)
    ruta_html = "vistas/mapas/mapa_solapamiento_final.html"
    mapa.save(ruta_html)

    with open(ruta_html, "r", encoding="utf-8") as f:
        contenido = f.read()
    meta_referrer = '<meta name="referrer" content="no-referrer-when-downgrade">'
    if meta_referrer not in contenido:
        contenido = contenido.replace("<head>", f"<head>\n    {meta_referrer}", 1)
        with open(ruta_html, "w", encoding="utf-8") as f:
            f.write(contenido)

    print("Mapa generado: Trayectoria completa dibujada, marcadores solo en velocidad <= 5.")

if __name__ == "__main__":
    generar_mapa()
