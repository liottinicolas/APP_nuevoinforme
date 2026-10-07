# ejecutar_evaluacion_cli.py - Script de ejecución Standalone/Headless (sin abrir QGIS)
import argparse
import sys
import os
import webbrowser

# Configurar ruta del paquete interno
sys.path.insert(0, os.path.dirname(__file__))

from qgis.core import QgsApplication, QgsProcessingContext, QgsProcessingFeedback, QgsVectorLayer

QGIS_INSTALL_DIR = r"C:\Program Files\QGIS 3.30.0"
sys.path.append(os.path.join(QGIS_INSTALL_DIR, "apps", "qgis", "python", "plugins"))
QgsApplication.setPrefixPath(os.path.join(QGIS_INSTALL_DIR, "apps", "qgis"), True)
qgs = QgsApplication([], False)
qgs.initQgis()

from evaluar_cumplimiento.algorithm import EvaluarCumplimientoIntraZonasConsultasMapasLeaflet


def run_evaluation():
    parser = argparse.ArgumentParser(description="Ejecutor Standalone del Preinforme de Cumplimiento Intradomiciliario (sin GUI de QGIS).")
    parser.add_argument("--zonas", help="Ruta al archivo vectorial de Zonas (.gpkg, .shp)")
    parser.add_argument("--gps", help="Ruta al archivo vectorial de Puntos GPS (.gpkg, .shp)")
    parser.add_argument("--ods", help="Ruta al archivo ODS de matrículas (si se descarga del Visor Intranet)")
    parser.add_argument("--descargar-gps", action="store_true", help="Marcar para descargar posiciones directamente del Visor Intranet")
    parser.add_argument("--gps-descargado-gpkg", help="Ruta del GeoPackage NUEVO para guardar la descarga GPS")
    parser.add_argument("--fecha-desde", default="auto", help="Fecha inicial AAAA-MM-DD")
    parser.add_argument("--fecha-hasta", default="auto", help="Fecha final AAAA-MM-DD")
    parser.add_argument("--servicio", default="Mezclado", help="Servicio a evaluar (ej: Mezclado, Reciclable)")
    parser.add_argument("--html-salida", help="Ruta del informe HTML generado de salida")

    args = parser.parse_args()

    print("=" * 70)
    print(" EJECUCIÓN STANDALONE - EVALUACIÓN DE CUMPLIMIENTO INTRADOMICILIARIO")
    print("=" * 70)

    # Modo interactivo si faltan argumentos principales
    if not args.zonas:
        args.zonas = input("📍 1. Ingrese la ruta del archivo de Zonas (.gpkg / .shp): ").strip('"')
    
    if not args.descargar_gps and not args.gps:
        opcion_descarga = input("🌐 2. ¿Desea descargar posiciones directamente del Visor Intranet? (s/N): ").strip().lower()
        if opcion_descarga.startswith("s"):
            args.descargar_gps = True
            args.ods = input("   - Ruta del listado ODS de matrículas: ").strip('"')
            args.gps_descargado_gpkg = input("   - Ruta para guardar GeoPackage GPS nuevo: ").strip('"')
        else:
            args.gps = input("   - Ruta de la capa GPS existente (.gpkg / .shp): ").strip('"')

    if not args.html_salida:
        default_out = os.path.join(os.path.dirname(__file__), "informes", "Informe_Cumplimiento_Intradomiciliario.html")
        usr_out = input(f"📄 3. Ruta para el HTML de salida [ENTER para {default_out}]: ").strip('"')
        args.html_salida = usr_out if usr_out else default_out

    print("-" * 70)
    print(f" Zonas: {args.zonas}")
    print(f" Servicio: {args.servicio}")
    print(f" Período: {args.fecha_desde} a {args.fecha_hasta}")
    print(f" Salida HTML: {args.html_salida}")
    print("=" * 70)

    alg = EvaluarCumplimientoIntraZonasConsultasMapasLeaflet()
    
    # Cargar capas de entrada
    layer_zonas = QgsVectorLayer(args.zonas, "Zonas", "ogr")
    if not layer_zonas.isValid():
        print(f"❌ Error: No se pudo abrir la capa de zonas en: {args.zonas}")
        qgs.exitQgis()
        sys.exit(1)

    layer_gps = None
    if not args.descargar_gps and args.gps:
        layer_gps = QgsVectorLayer(args.gps, "GPS", "ogr")
        if not layer_gps.isValid():
            print(f"❌ Error: No se pudo abrir la capa GPS en: {args.gps}")
            qgs.exitQgis()
            sys.exit(1)

    params = {
        alg.ZONAS: layer_zonas,
        alg.SERVICIO: args.servicio,
        alg.FECHA_DESDE: args.fecha_desde,
        alg.FECHA_HASTA: args.fecha_hasta,
        alg.DESCARGAR_GPS: args.descargar_gps,
        alg.USAR_MINIMOS_ZONA: True,
        alg.OUTPUT_HTML: args.html_salida,
    }

    if args.descargar_gps:
        if not args.ods or not args.gps_descargado_gpkg:
            print("❌ Error: Para descargar GPS del visor debe especificar ODS y ruta GPKG de salida.")
            qgs.exitQgis()
            sys.exit(1)
        params[alg.LISTADO_MATRICULAS] = args.ods
        params[alg.GPS_DESCARGADO] = args.gps_descargado_gpkg
    else:
        params[alg.GPS] = layer_gps

    context = QgsProcessingContext()
    feedback = QgsProcessingFeedback()

    print("🚀 Procesando zonas e índice espacial R-Tree...")
    try:
        results = alg.processAlgorithm(params, context, feedback)
        out_path = os.path.abspath(args.html_salida)
        print("✅ Evaluación finalizada con éxito.")
        print(f"📄 Informe HTML generado en: {out_path}")
        print("🌐 Abriendo el reporte interactivo en su navegador predeterminado...")
        webbrowser.open(out_path)
    except Exception as exc:
        print(f"❌ Error en la evaluación: {exc}")
    finally:
        qgs.exitQgis()


if __name__ == "__main__":
    run_evaluation()
