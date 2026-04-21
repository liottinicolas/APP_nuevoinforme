import sys, os, pandas as pd, geopandas as gpd, matplotlib.pyplot as plt, contextily as cx
from matplotlib.offsetbox import OffsetImage, AnnotationBbox
import urllib.request, io

def generar_mapa_estatico():
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None
    ruta_salida_final = sys.argv[3] if len(sys.argv) > 3 else "vistas/mapas/mapa_estatico_final.png"

    fig, ax = plt.subplots(figsize=(10, 12))
    resumen_datos = {"zona": "N/A", "fraccion": "N/A", "matricula": "N/A", "hora_inicio": "N/A", "hora_fin": "N/A", "fecha": "N/A"}

    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados).to_crs(epsg=3857)
        
        if not gdf_puntos.empty:
            gdf_puntos['t_dt'] = pd.to_datetime(gdf_puntos['tiempo'], dayfirst=True, errors='coerce')
            gdf_puntos = gdf_puntos.sort_values(by='t_dt')
            
            resumen_datos.update({
                "fecha": gdf_puntos['t_dt'].min().strftime('%d-%m-%Y'),
                "hora_inicio": gdf_puntos['t_dt'].min().strftime('%H:%M:%S'),
                "hora_fin": gdf_puntos['t_dt'].max().strftime('%H:%M:%S'),
                "zona": str(gdf_puntos['nombre'].iloc[0]) if 'nombre' in gdf_puntos.columns else "N/A",
                "fraccion": str(gdf_puntos['FRACCION'].iloc[0]) if 'FRACCION' in gdf_puntos.columns else "N/A",
                "matricula": str(gdf_puntos['matricula'].iloc[0]) if 'matricula' in gdf_puntos.columns else "N/A"
            })

            ax.plot([p.x for p in gdf_puntos.geometry], [p.y for p in gdf_puntos.geometry], 
                    color='#0046E3', lw=2.5, alpha=0.7, zorder=2)
            
            ax.scatter(gdf_puntos.geometry.x, gdf_puntos.geometry.y, 
                       c='#0046E3', s=20, edgecolors='white', linewidth=0.5, zorder=3)

    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra).to_crs(epsg=3857)
        gdf_intra.plot(ax=ax, facecolor='orange', edgecolor='darkorange', alpha=0.15, zorder=1)
        
        xmin, ymin, xmax, ymax = gdf_intra.total_bounds
        ancho, alto = xmax - xmin, ymax - ymin
        ax.set_xlim(xmin - ancho * 0.45, xmax + ancho * 0.05)
        ax.set_ylim(ymin - alto * 0.05, ymax + alto * 0.40)

    cx.add_basemap(ax, source=cx.providers.CartoDB.Positron)
    ax.set_axis_off()

    info_texto = f"\n\n\n\n\n{'—'*22}\n FECHA:     {resumen_datos['fecha']}\n MATRÍCULA: {resumen_datos['matricula']}\n ZONA:      {resumen_datos['zona']}\n FRACCIÓN:  {resumen_datos['fraccion']}\n INICIO:    {resumen_datos['hora_inicio']}\n FIN:       {resumen_datos['hora_fin']}\n{'—'*22}"
    ax.text(0.02, 0.98, info_texto, transform=ax.transAxes, bbox=dict(facecolor='#0046E3', alpha=0.9, edgecolor='white', boxstyle='round,pad=0.8'),
            fontsize=11, color='white', fontweight='bold', family='monospace', va='top', ha='left', zorder=5)

    try:
        url_logo = "https://montevideo.gub.uy/modules/custom/im_logo/images/logo_im.png"
        with urllib.request.urlopen(url_logo) as url:
            logo_img = plt.imread(io.BytesIO(url.read()))
            if logo_img.shape[2] == 4: logo_img[:, :, :3] = 1.0 
            ab = AnnotationBbox(OffsetImage(logo_img, zoom=0.45), (0.11, 0.940), frameon=False, xycoords='axes fraction', zorder=6)
            ax.add_artist(ab)
    except: pass

    os.makedirs(os.path.dirname(ruta_salida_final), exist_ok=True)
    plt.savefig(ruta_salida_final, dpi=300, bbox_inches='tight')
    plt.close()

if __name__ == "__main__":
    generar_mapa_estatico()
