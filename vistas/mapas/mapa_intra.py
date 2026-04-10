import folium
import geopandas as gpd
import sys
import os
from folium.features import DivIcon

def generar_mapa():
    # --- 1. CAPTURAR AMBOS ARGUMENTOS ---
    # sys.argv[1] -> Ruta Capa Intra (Polígono de zona)
    # sys.argv[2] -> Ruta Puntos Solapados (Puntos de eventos/velocidad)
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None

    # Inicializamos el mapa con un fondo neutro (CartoDB Positron)
    # Ya no es crítico el location/zoom inicial porque fit_bounds lo ajustará
    mapa = folium.Map(location=[-34.85, -56.16], zoom_start=14, tiles="CartoDB positron")

    # --- 2. CARGAR Y MOSTRAR CAPA INTRA ---
    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra)
        
        # Convertimos a coordenadas geográficas (WGS84) para Folium
        gdf_intra_4326 = gdf_intra.to_crs(epsg=4326)

        # Limpieza rápida de fechas para evitar errores de serialización en el JSON
        for col in gdf_intra_4326.columns:
            if 'date' in str(gdf_intra_4326[col].dtype) or col == 'FECHA.DESDE':
                gdf_intra_4326[col] = gdf_intra_4326[col].astype(str)
        
        folium.GeoJson(
            gdf_intra_4326,
            name="Zona Filtrada",
            style_function=lambda x: {'fillColor': 'orange', 'color': 'darkorange', 'fillOpacity': 0.2}
        ).add_to(mapa)

        # --- AJUSTE AUTOMÁTICO DEL ZOOM ---
        # Calculamos los límites del polígono y ajustamos el mapa a ellos
        if not gdf_intra_4326.empty:
            limites = gdf_intra_4326.total_bounds # [minx, miny, maxx, maxy]
            # Folium espera [[miny, minx], [maxy, maxx]]
            mapa.fit_bounds([[limites[1], limites[0]], [limites[3], limites[2]]])

    # --- 3. CARGAR Y DESTACAR PUNTOS SOLAPADOS ---
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados)
        gdf_puntos_4326 = gdf_puntos.to_crs(epsg=4326)

        # Limpieza de fechas
        for col in gdf_puntos_4326.columns:
            if 'date' in str(gdf_puntos_4326[col].dtype) or col == 'tiempo':
                gdf_puntos_4326[col] = gdf_puntos_4326[col].astype(str)

        # Agregamos estos puntos con un color fuerte para ver el "solapamiento"
        capa_solape = folium.FeatureGroup(name="Puntos en la Zona")
        
        for idx, fila in gdf_puntos_4326.iterrows():
            if fila.geometry:
                folium.CircleMarker(
                    location=[fila.geometry.y, fila.geometry.x],
                    radius=6,
                    color='red',
                    fill=True,
                    fill_color='red',
                    fill_opacity=0.8,
                    popup=f"<b>Solapado en Zona</b><br>Velocidad: {fila.get('velocidad', 'N/A')} km/h"
                ).add_to(capa_solape)
        
        capa_solape.add_to(mapa)

    # --- 4. FINALIZAR ---
    folium.LayerControl(collapsed=False).add_to(mapa)
    
    # Asegurar que el directorio de salida existe
    os.makedirs("vistas/mapas", exist_ok=True)
    
    ruta_salida = "vistas/mapas/mapa_solapamiento_final.html"
    mapa.save(ruta_salida)
    print(f"Mapa de solapamiento generado en: {ruta_salida}")

if __name__ == "__main__":
    generar_mapa()
