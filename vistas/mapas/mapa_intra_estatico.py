import sys
import os
import pandas as pd
import geopandas as gpd
import matplotlib.pyplot as plt
import contextily as cx
from matplotlib.offsetbox import OffsetImage, AnnotationBbox
import urllib.request
import io

def generar_mapa_estatico():
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None

    fig, ax = plt.subplots(figsize=(10, 12))
    
    resumen_datos = {
        "zona": "No definida", "fraccion": "N/A", "matricula": "N/A",
        "hora_inicio": "N/A", "hora_fin": "N/A", "fecha": "N/A"
    }

    # --- 1. CARGAR DATOS ---
    gdf_puntos = gpd.GeoDataFrame()
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados).to_crs(epsg=3857)
        # ... (procesamiento de tiempos y metadatos igual que antes)
        if not gdf_puntos.empty:
            if 'tiempo' in gdf_puntos.columns:
                gdf_puntos['tiempo_dt'] = pd.to_datetime(gdf_puntos['tiempo'], dayfirst=True, errors='coerce')
                gdf_puntos = gdf_puntos.sort_values(by='tiempo_dt')
                min_time = gdf_puntos['tiempo_dt'].min()
                resumen_datos["fecha"] = min_time.strftime('%d-%m-%Y')
                resumen_datos["hora_inicio"] = min_time.strftime('%H:%M:%S')
                resumen_datos["hora_fin"] = gdf_puntos['tiempo_dt'].max().strftime('%H:%M:%S')
            if 'nombre' in gdf_puntos.columns: resumen_datos["zona"] = str(gdf_puntos['nombre'].iloc[0])
            if 'FRACCION' in gdf_puntos.columns: resumen_datos["fraccion"] = str(gdf_puntos['FRACCION'].iloc[0])
            if 'matricula' in gdf_puntos.columns: resumen_datos["matricula"] = str(gdf_puntos['matricula'].iloc[0])

    # --- 2. GRAFICAR ---
    if not gdf_puntos.empty:
        # Trayectoria
        coords = [(p.x, p.y) for p in gdf_puntos.geometry]
        linea_x, linea_y = zip(*coords)
        ax.plot(linea_x, linea_y, color='#0046E3', linewidth=2.5, alpha=0.7, zorder=2)
        
        # Puntos lentos
        gdf_puntos['velocidad_num'] = pd.to_numeric(gdf_puntos['velocidad'], errors='coerce')
        gdf_lentos = gdf_puntos[gdf_puntos['velocidad_num'] <= 5]
        ax.scatter(gdf_lentos.geometry.x, gdf_lentos.geometry.y, c='#0046E3', s=20, edgecolors='white', zorder=3)

    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra).to_crs(epsg=3857)
        gdf_intra.plot(ax=ax, facecolor='orange', edgecolor='darkorange', alpha=0.15, zorder=1)

    # --- 3. LÓGICA DE AUTO-ZOOM PARA LA TARJETA ---
    if not gdf_puntos.empty:
        # 1. Obtener límites actuales que encierran los datos
        xmin, ymin, xmax, ymax = gdf_puntos.total_bounds
        if ruta_intra and os.path.exists(ruta_intra):
            ixmin, iymin, ixmax, iymax = gdf_intra.total_bounds
            xmin, ymin = min(xmin, ixmin), min(ymin, iymin)
            xmax, ymax = max(xmax, ixmax), max(ymax, iymax)

        ancho_datos = xmax - xmin
        alto_datos = ymax - ymin

        # 2. Definir cuánto espacio estimamos que ocupa la tarjeta (aprox 35% del ancho y 30% del alto)
        # La tarjeta está en la esquina superior izquierda (North-West)
        margen_necesario_x = ancho_datos * 0.45 
        margen_necesario_y = alto_datos * 0.40

        # Ajustamos los límites del eje para "alejar" el vertice superior izquierdo
        ax.set_xlim(xmin - margen_necesario_x, xmax + (ancho_datos * 0.05))
        ax.set_ylim(ymin - (alto_datos * 0.05), ymax + margen_necesario_y)

    # --- 4. FINALIZAR MAPA ---
    cx.add_basemap(ax, source=cx.providers.CartoDB.Positron)
    ax.set_axis_off()

    # --- 5. TARJETA E IMAGENES ---
    info_texto = (
        f"\n\n\n\n\n"
        f"{'—'*22}\n"
        f" FECHA:     {resumen_datos['fecha']}\n"
        f" MATRÍCULA: {resumen_datos['matricula']}\n"
        f" ZONA:      {resumen_datos['zona']}\n"
        f" FRACCIÓN:  {resumen_datos['fraccion']}\n"
        f" INICIO:    {resumen_datos['hora_inicio']}\n"
        f" FIN:       {resumen_datos['hora_fin']}\n"
        f"{'—'*22}"
    )

    ax.text(0.02, 0.98, info_texto, transform=ax.transAxes,
            bbox=dict(facecolor='#0046E3', alpha=0.9, edgecolor='white', boxstyle='round,pad=0.8'),
            fontsize=11, color='white', fontweight='bold', family='monospace',
            verticalalignment='top', horizontalalignment='left', zorder=5)

    # Logo
    try:
        url_logo = "https://montevideo.gub.uy/modules/custom/im_logo/images/logo_im.png"
        with urllib.request.urlopen(url_logo) as url:
            f = io.BytesIO(url.read()); logo_img = plt.imread(f)
            if logo_img.shape[2] == 4: logo_img[:, :, :3] = 1.0 
            imagebox = OffsetImage(logo_img, zoom=0.45) 
            ab = AnnotationBbox(imagebox, (0.11, 0.940), frameon=False, xycoords='axes fraction', zorder=6)
            ax.add_artist(ab)
    except: pass
        
    # Marca de agua
    ax.text(0.5, 0.5, resumen_datos["zona"].upper(), transform=ax.transAxes,
            fontsize=60, color='gray', alpha=0.12, ha='center', va='center', rotation=30, zorder=1)

    # Guardar
    os.makedirs("vistas/mapas", exist_ok=True)
    ruta_salida = "vistas/mapas/mapa_estatico_final.png"
    plt.savefig(ruta_salida, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Mapa generado en: {ruta_salida}")

if __name__ == "__main__":
    generar_mapa_estatico()
