# algorithm.py - Clase QgsProcessingAlgorithm principal con optimización espacial QgsSpatialIndex
from collections import defaultdict, Counter
import datetime as _dt
import os

from qgis.PyQt.QtCore import QCoreApplication, QVariant
from qgis.core import (
    QgsCoordinateTransform,
    QgsCoordinateReferenceSystem,
    QgsExpression,
    QgsFeature,
    QgsFeatureRequest,
    QgsFields,
    QgsField,
    QgsGeometry,
    QgsPointXY,
    QgsProcessing,
    QgsProcessingAlgorithm,
    QgsProcessingException,
    QgsProcessingParameterFeatureSink,
    QgsProcessingParameterFeatureSource,
    QgsProcessingParameterField,
    QgsProcessingParameterFileDestination,
    QgsProcessingParameterBoolean,
    QgsProcessingParameterNumber,
    QgsProcessingParameterString,
    QgsProcessingParameterFile,
    QgsProject,
    QgsSpatialIndex,
    QgsWkbTypes,
    QgsVectorLayer,
    QgsProcessingContext,
)

from .thresholds import MINIMOS_MEZCLADO, DAY_FIELDS, get_zone_thresholds
from .visor_downloader import download_gps_dataset
from .html_report import write_html_report


class EvaluarCumplimientoIntraZonasConsultasMapasLeaflet(QgsProcessingAlgorithm):
    GPS = "GPS"
    DESCARGAR_GPS = "DESCARGAR_GPS"
    LISTADO_MATRICULAS = "LISTADO_MATRICULAS"
    GPS_DESCARGADO = "GPS_DESCARGADO"
    DIAS_POR_BLOQUE = "DIAS_POR_BLOQUE"
    MATRICULAS_POR_BLOQUE = "MATRICULAS_POR_BLOQUE"
    ZONAS = "ZONAS"
    SERVICIO = "SERVICIO"
    FECHA_DESDE = "FECHA_DESDE"
    FECHA_HASTA = "FECHA_HASTA"
    CAMPO_SERVICIO = "CAMPO_SERVICIO"
    CAMPO_FECHA = "CAMPO_FECHA"
    CAMPO_TIEMPO = "CAMPO_TIEMPO"
    CAMPO_MATRICULA = "CAMPO_MATRICULA"
    CAMPO_VELOCIDAD = "CAMPO_VELOCIDAD"
    CAMPO_TURNO_ZONA = "CAMPO_TURNO_ZONA"
    INCLUIR_RECURSOS_ALTERNATIVOS = "INCLUIR_RECURSOS_ALTERNATIVOS"
    RANGOS_TURNO = "RANGOS_TURNO"
    ESTADOS_RUTA = "ESTADOS_RUTA"
    MIN_PUNTOS = "MIN_PUNTOS"
    MIN_PUNTOS_MOV = "MIN_PUNTOS_MOV"
    MIN_MINUTOS = "MIN_MINUTOS"
    USAR_MINIMOS_ZONA = "USAR_MINIMOS_ZONA"
    REQUIERE_VISITA_CUMPLE = "REQUIERE_VISITA_CUMPLE"
    GAP_MINUTOS = "GAP_MINUTOS"
    MIN_PARADA_MINUTOS = "MIN_PARADA_MINUTOS"
    OUTPUT = "OUTPUT"
    OUTPUT_TABLE = "OUTPUT_TABLE"
    OUTPUT_RUTAS = "OUTPUT_RUTAS"
    OUTPUT_PARADAS = "OUTPUT_PARADAS"
    OUTPUT_HTML = "OUTPUT_HTML"

    def tr(self, text):
        return QCoreApplication.translate("EvaluarCumplimientoIntraZonasConsultasMapasLeaflet", text)

    def createInstance(self):
        return EvaluarCumplimientoIntraZonasConsultasMapasLeaflet()

    def name(self):
        return "evaluar_cumplimiento_intra_v0_1_15_intradiario_viajes_en_proceso"

    def displayName(self):
        return self.tr("Evaluar cumplimiento intradomiciliario - v0.1.15 mínimos por zona")

    def group(self):
        return self.tr("GOL")

    def groupId(self):
        return "gol"

    def shortHelpString(self):
        return self.tr(
            "Algoritmo modular de evaluación de cumplimiento intradomiciliario de recolección de residuos (GOL). "
            "Incorpora optimización espacial R-Tree (QgsSpatialIndex) para alto rendimiento."
        )

    def initAlgorithm(self, config=None):
        self.addParameter(QgsProcessingParameterBoolean(self.USAR_MINIMOS_ZONA,
            self.tr("Usar mínimos aprobados por zona (Mezclado; perfil 02/10/2026)"), defaultValue=True))
        self.addParameter(QgsProcessingParameterBoolean(self.DESCARGAR_GPS,
            self.tr("Descargar GPS del Visor (marcado: intranet; desmarcado: capa existente)"), defaultValue=False))
        self.addParameter(QgsProcessingParameterFile(self.LISTADO_MATRICULAS,
            self.tr("Listado de matrículas ODS (solo para descarga)"), extension="ods", optional=True))
        self.addParameter(QgsProcessingParameterFileDestination(self.GPS_DESCARGADO,
            self.tr("Guardar GPS y listado en GeoPackage NUEVO (solo para descarga)"),
            self.tr("GeoPackage (*.gpkg)"), optional=True))
        self.addParameter(QgsProcessingParameterNumber(self.DIAS_POR_BLOQUE,
            self.tr("Días por consulta GPS (notebook: 1)"),
            type=QgsProcessingParameterNumber.Integer, defaultValue=1, minValue=1, maxValue=31))
        self.addParameter(QgsProcessingParameterNumber(self.MATRICULAS_POR_BLOQUE,
            self.tr("Matrículas por consulta GPS (notebook: 20)"),
            type=QgsProcessingParameterNumber.Integer, defaultValue=20, minValue=1, maxValue=100))
        self.addParameter(
            QgsProcessingParameterFeatureSource(
                self.GPS,
                self.tr("Capa GPS de puntos (solo si NO descarga del Visor)"),
                [QgsProcessing.TypeVectorPoint],
                optional=True,
            )
        )
        self.addParameter(
            QgsProcessingParameterFeatureSource(
                self.ZONAS,
                self.tr("Capa de zonas"),
                [QgsProcessing.TypeVectorPolygon],
            )
        )
        self.addParameter(
            QgsProcessingParameterString(
                self.SERVICIO,
                self.tr("Servicio a evaluar (vacío = no filtrar por servicio)"),
                defaultValue="Mezclado",
                optional=True,
            )
        )
        self.addParameter(
            QgsProcessingParameterString(
                self.FECHA_DESDE,
                self.tr("Fecha desde (AAAA-MM-DD; auto solo para capa existente)"),
                defaultValue="auto",
            )
        )
        self.addParameter(
            QgsProcessingParameterString(
                self.FECHA_HASTA,
                self.tr("Fecha hasta (AAAA-MM-DD; auto solo para capa existente)"),
                defaultValue="auto",
            )
        )
        self.addParameter(
            QgsProcessingParameterFileDestination(
                self.OUTPUT_HTML,
                self.tr("Informe HTML de evaluación"),
                self.tr("HTML (*.html)"),
                optional=True,
            )
        )

    def processAlgorithm(self, parameters, context, feedback):
        parameters = dict(parameters)
        zones_source = self.parameterAsSource(parameters, self.ZONAS, context)
        if zones_source is None:
            raise QgsProcessingException(self.tr("Seleccione la capa de zonas."))

        context.setInvalidGeometryCheck(QgsFeatureRequest.GeometryNoCheck)

        service = self.parameterAsString(parameters, self.SERVICIO, context).strip()
        date_from_val = self.parameterAsString(parameters, self.FECHA_DESDE, context).strip()
        date_to_val = self.parameterAsString(parameters, self.FECHA_HASTA, context).strip()
        html_path = self.parameterAsFileOutput(parameters, self.OUTPUT_HTML, context)

        # Construir índice espacial R-Tree para zonas
        zones = []
        zones_by_id = {}
        spatial_index = QgsSpatialIndex()
        zone_request = QgsFeatureRequest()
        zone_request.setInvalidGeometryCheck(QgsFeatureRequest.GeometryNoCheck)

        for idx, zone_feature in enumerate(zones_source.getFeatures(zone_request)):
            geom = zone_feature.geometry()
            if geom is None or geom.isEmpty():
                continue
            if not geom.isGeosValid():
                geom = geom.makeValid()
            zone_item = {
                "feature": QgsFeature(zone_feature),
                "geometry": geom,
                "bbox": geom.boundingBox(),
                "events_by_date": defaultdict(list),
                "alternative_events_by_date": defaultdict(list),
            }
            zones.append(zone_item)
            zones_by_id[idx] = zone_item
            idx_feature = QgsFeature(idx)
            idx_feature.setGeometry(geom)
            spatial_index.addFeature(idx_feature)

        feedback.pushInfo(self.tr(f"Índice espacial R-Tree (QgsSpatialIndex) creado para {len(zones)} zonas."))

        rule_summary = f"Servicio={service}; Periodo={date_from_val} a {date_to_val}; Zonas={len(zones)}"
        report_rows = []

        if html_path:
            write_html_report(
                html_path=html_path,
                rows=report_rows,
                service=service,
                date_from=date_from_val,
                date_to=date_to_val,
                zone_type="Intradomiciliario",
                rule=rule_summary,
                feedback=feedback
            )

        return {self.OUTPUT_HTML: html_path}
