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
    # 1. Leer argumentos de la terminal (desde R)
    ruta_intra = sys.argv[1] if len(sys.argv) > 1 else None
    ruta_solapados = sys.argv[2] if len(sys.argv) > 2 else None

    # Configurar la figura
    fig, ax = plt.subplots(figsize=(10, 12))
    
    resumen_datos = {
        "zona": "No definida", "fraccion": "N/A", "matricula": "N/A",
        "hora_inicio": "N/A", "hora_fin": "N/A", "fecha": "N/A"
    }

    # --- 2. CARGAR CAPA ZONA (Polígono naranja) ---
    if ruta_intra and os.path.exists(ruta_intra):
        gdf_intra = gpd.read_file(ruta_intra).to_crs(epsg=3857)
        gdf_intra.plot(ax=ax, facecolor='orange', edgecolor='darkorange', alpha=0.15, zorder=1)

    # --- 3. CARGAR PUNTOS Y LÓGICA DE DATOS ---
    if ruta_solapados and os.path.exists(ruta_solapados):
        gdf_puntos = gpd.read_file(ruta_solapados).to_crs(epsg=3857)
        
        if not gdf_puntos.empty:
            if 'tiempo' in gdf_puntos.columns:
                # Forzamos formato día-mes-año
                gdf_puntos['tiempo_dt'] = pd.to_datetime(gdf_puntos['tiempo'], dayfirst=True, errors='coerce')
                gdf_puntos = gdf_puntos.sort_values(by='tiempo_dt')
                
                min_time = gdf_puntos['tiempo_dt'].min()
                resumen_datos["fecha"] = min_time.strftime('%d-%m-%Y')
                resumen_datos["hora_inicio"] = min_time.strftime('%H:%M:%S')
                resumen_datos["hora_fin"] = gdf_puntos['tiempo_dt'].max().strftime('%H:%M:%S')

            # Extraer metadatos para la tarjeta
            if 'nombre' in gdf_puntos.columns: resumen_datos["zona"] = str(gdf_puntos['nombre'].iloc[0])
            if 'FRACCION' in gdf_puntos.columns: resumen_datos["fraccion"] = str(gdf_puntos['FRACCION'].iloc[0])
            if 'matricula' in gdf_puntos.columns: resumen_datos["matricula"] = str(gdf_puntos['matricula'].iloc[0])

            # Dibujar Trayectoria (Línea Azul)
            coords = [(p.x, p.y) for p in gdf_puntos.geometry]
            linea_x, linea_y = zip(*coords)
            ax.plot(linea_x, linea_y, color='#0046E3', linewidth=2.5, alpha=0.7, zorder=2)

            # Dibujar Puntos lentos (Velocidad <= 5)
            gdf_puntos['velocidad_num'] = pd.to_numeric(gdf_puntos['velocidad'], errors='coerce')
            gdf_lentos = gdf_puntos[gdf_puntos['velocidad_num'] <= 5]
            ax.scatter(gdf_lentos.geometry.x, gdf_lentos.geometry.y, 
                       c='#0046E3', s=20, edgecolors='white', linewidths=0.5, zorder=3)

    # --- 4. MAPA BASE (CartoDB Positron) ---
    cx.add_basemap(ax, source=cx.providers.CartoDB.Positron)
    ax.set_axis_off()

    # --- 5. TARJETA INFORMATIVA ---
    # Usamos saltos de línea al inicio para dejar el "hueco" del logo arriba
    info_texto = (
        f"\n\n\n\n" 
        f"{'-'*18}\n"
        f"Fecha: {resumen_datos['fecha']}\n"
        f"Matrícula: {resumen_datos['matricula']}\n"
        f"Zona: {resumen_datos['zona']}\n"
        f"Fracción: {resumen_datos['fraccion']}\n"
        f"Inicio: {resumen_datos['hora_inicio']}\n"
        f"Fin: {resumen_datos['hora_fin']}"
    )

    # Dibujar el cuadro azul
    ax.text(0.02, 0.98, info_texto, transform=ax.transAxes,
            bbox=dict(facecolor='#0046E3', alpha=0.9, edgecolor='white', boxstyle='round,pad=0.5'),
            fontsize=8, color='white', fontweight='bold', 
            verticalalignment='top', horizontalalignment='left', zorder=5)

    # --- 6. AGREGAR LOGO (Arriba a la izquierda, sin sangría) ---
    try:
        url_logo = "https://montevideo.gub.uy/modules/custom/im_logo/images/logo_im.png"
        with urllib.request.urlopen(url_logo) as url:
            f = io.BytesIO(url.read())
            logo_img = plt.imread(f)
            
            # Convertir logo a blanco puro
            if logo_img.shape[2] == 4:
                logo_img[:, :, :3] = 1.0 

            # Zoom aumentado a 0.30 para que sea grande
            imagebox = OffsetImage(logo_img, zoom=0.45) 
            
            # Coordenadas: 
            # X = 0.025 (alineado casi al borde izquierdo de la caja)
            # Y = 0.955 (posicionado en el espacio en blanco superior)
            ab = AnnotationBbox(imagebox, (0.1, 0.945), frameon=False, 
                                xycoords='axes fraction', zorder=6,
                                box_alignment=(0.5, 0.5))
            ax.add_artist(ab)
    except Exception as e:
        print(f"No se pudo cargar el logo: {e}")
        
        # --- 6.5 AGREGAR MARCA DE AGUA (Nombre de la Zona) ---
    texto_watermark = resumen_datos["zona"].upper()
    
    # Añadimos el texto en el centro del eje (0.5, 0.5)
    ax.text(0.5, 0.5, texto_watermark,
            transform=ax.transAxes,
            fontsize=60,          # Tamaño grande
            color='gray',         # Color neutro
            alpha=0.15,           # Muy transparente para que sea marca de agua
            ha='center', va='center', 
            rotation=0,          # Sin rotación
            fontweight='bold',
            zorder=1)             # Zorder bajo para que quede detrás de la tarjeta y el logo

    # --- 7. GUARDAR RESULTADO ---
    os.makedirs("vistas/mapas", exist_ok=True)
    ruta_salida = "vistas/mapas/mapa_estatico_final.png"
    plt.savefig(ruta_salida, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Mapa estático generado exitosamente en: {ruta_salida}")

if __name__ == "__main__":
    generar_mapa_estatico()
  
