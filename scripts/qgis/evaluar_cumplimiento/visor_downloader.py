# visor_downloader.py - Descargador de posiciones GPS con reintentos de red y timeouts resilientes
import datetime as _dt
import os
import math
import re
import sqlite3
import tempfile
import time
from collections import Counter
from contextlib import closing
import xml.etree.ElementTree as ET

from qgis.PyQt.QtCore import QVariant
from qgis.core import (
    QgsCoordinateTransform,
    QgsCoordinateReferenceSystem,
    QgsFeature,
    QgsFields,
    QgsField,
    QgsGeometry,
    QgsPointXY,
    QgsVectorLayer,
    QgsVectorFileWriter,
    QgsProcessingException,
)

GPS_API_URL = "https://intranet.imm.gub.uy/app/visor-vehiculos-v2/api/vehiculos/posiciones"


def visor_plate(value):
    text = str(value or "").strip().upper()
    match = re.search(r"[A-Z]{3}\s*\d{4}", text)
    if match:
        return match.group(0).replace(" ", "")
    return re.sub(r"[^A-Z0-9]", "", text)


def visor_blocks(start, end, plates, days, count):
    cursor = start
    while cursor <= end:
        stop = min(cursor + _dt.timedelta(days=days) - _dt.timedelta(seconds=1), end)
        for index in range(0, len(plates), count):
            yield cursor, stop, plates[index:index + count]
        cursor = stop + _dt.timedelta(seconds=1)


def visor_request(params, max_retries=4, base_backoff_sec=2, timeout=(10, 120), feedback=None):
    """
    Realiza la consulta HTTP GET a la API del Visor de Intranet IMM con:
    - Timeouts explícitos (conexión: 10s, lectura: 120s)
    - Reintentos exponenciales (retries) ante caídas o lags temporales del servidor
    - Manejo seguro de excepciones HTTP
    """
    import requests

    last_exception = None
    for attempt in range(1, max_retries + 1):
        if feedback and feedback.isCanceled():
            raise QgsProcessingException("Consulta cancelada por el usuario.")
        try:
            response = requests.get(GPS_API_URL, params=params, timeout=timeout, verify=True)
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, list):
                raise ValueError("La API del Visor no devolvió una lista de posiciones válida.")
            return data
        except (requests.exceptions.ConnectionError,
                requests.exceptions.Timeout,
                requests.exceptions.HTTPError,
                ValueError) as exc:
            last_exception = exc
            if attempt < max_retries:
                sleep_sec = base_backoff_sec * (2 ** (attempt - 1))
                if feedback:
                    feedback.pushWarning(
                        f"Reintento {attempt}/{max_retries} tras error en consulta ({type(exc).__name__}). Reintentando en {sleep_sec}s..."
                    )
                time.sleep(sleep_sec)
            else:
                raise QgsProcessingException(
                    f"Fallo persistente en la API del Visor Intranet tras {max_retries} intentos. "
                    f"Detalle: {type(exc).__name__} - {str(exc)}. Verifique la conexión a Intranet o VPN."
                ) from last_exception


def read_visor_ods(ods_path, feedback_fn):
    import zipfile
    try:
        with zipfile.ZipFile(ods_path, 'r') as z:
            content = z.read("content.xml")
        root = ET.fromstring(content)
        ns = {"table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0", "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0"}
        table = root.find(".//table:table", ns)
        if table is None:
            raise ValueError("No se encontro tabla ODS")
        rows = []
        for row in table.findall("table:table-row", ns):
            current_row = []
            for cell in row.findall("table:table-cell", ns):
                repeat = int(cell.attrib.get("{urn:oasis:names:tc:opendocument:xmlns:table:1.0}number-columns-repeated", "1"))
                texts = [t.text for t in cell.findall(".//text:p", ns) if t.text]
                cell_value = " ".join(texts).strip() if texts else ""
                for _ in range(repeat):
                    current_row.append(cell_value)
            if any(current_row):
                rows.append(current_row)
        if len(rows) < 2:
            raise ValueError("La planilla ODS esta vacia o no tiene datos de matricula")
        headers = [str(cell).strip() for cell in rows[0]]
        if "Matricula" not in headers:
            raise ValueError("La planilla ODS debe incluir la columna 'Matricula'")
        result, seen = [], set()
        for values in rows[1:]:
            record = {name: values[i] if i < len(values) else "" for i, name in enumerate(headers) if name}
            plate = visor_plate(record.get("Matricula"))
            if not plate:
                continue
            if plate in seen:
                if feedback_fn:
                    feedback_fn("Matricula repetida en ODS: " + plate + "; se conserva la primera.")
                continue
            seen.add(plate)
            record["Matricula_visor"] = plate
            result.append(record)
        if not result:
            raise ValueError("No hay matriculas validas en la planilla ODS")
        return result
    except Exception as exc:
        raise QgsProcessingException("No se pudo leer el listado ODS: " + str(exc)) from exc


def download_gps_dataset(ods_path, destination_gpkg, day_from, day_to, days_per_block, count_per_block, context, feedback, float_parser):
    destination = os.path.abspath(destination_gpkg)
    if os.path.exists(destination):
        raise QgsProcessingException("El GeoPackage ya existe. Elija otro nombre para no sobrescribirlo.")
    parent = os.path.dirname(destination)
    if not os.path.isdir(parent):
        raise QgsProcessingException("La carpeta de salida GPS no existe.")

    start = _dt.datetime.combine(day_from, _dt.time.min)
    end = _dt.datetime.combine(day_to, _dt.time(23, 59, 59))
    catalogue = read_visor_ods(ods_path, feedback.pushWarning if feedback else None)
    metadata = {r["Matricula_visor"]: r for r in catalogue}

    blocks = list(visor_blocks(start, end, list(metadata), days_per_block, count_per_block))
    points, seen, logs = [], set(), []
    if feedback:
        feedback.pushInfo(f"Descarga de Intranet activa: {len(metadata)} matrículas; {len(blocks)} consultas de bloque.")

    for i, (a, b, plates) in enumerate(blocks, 1):
        if feedback and feedback.isCanceled():
            raise QgsProcessingException("Descarga cancelada.")
        params = {"matricula": ",".join(plates), "fechaDesde": a.isoformat(),
                  "fechaHasta": b.isoformat(), "grupo": "sisconve", "showStopsOnly": "false"}
        if feedback:
            feedback.setProgressText(f"GPS Visor: bloque {i}/{len(blocks)}; fecha {a.date()}; {len(plates)} matrículas")
        
        batch = visor_request(params, feedback=feedback)

        for item in batch:
            try:
                plate = visor_plate(item.get("matricula"))
                stamp = _dt.datetime.strptime(item["tiempo"], "%d-%m-%Y %H:%M:%S")
                lon, lat = item["coordenadas"]["coordinates"][:2]
                lon, lat = float(lon), float(lat)
                if plate not in plates or not a <= stamp <= b:
                    continue
                if not math.isfinite(lon) or not math.isfinite(lat) or not -180 <= lon <= 180 or not -90 <= lat <= 90:
                    continue
                key = (plate, stamp, lat, lon)
                if key in seen:
                    continue
                seen.add(key)
                points.append((plate, stamp, lon, lat, item.get("velocidad"), item.get("orientacion"), item.get("power")))
            except Exception:
                continue
        logs.append((i, a.isoformat(), b.isoformat(), ",".join(plates), len(batch), "ok_sin_puntos" if not batch else "ok"))
        if feedback:
            feedback.setProgress(int(35 * i / len(blocks)))

    layer = QgsVectorLayer("Point?crs=EPSG:32721", "gps_puntos", "memory")
    provider = layer.dataProvider()
    names = [("matricula", QVariant.String), ("tiempo", QVariant.String),
             ("fecha", QVariant.String), ("hora", QVariant.String), ("velocidad_kmh", QVariant.Double),
             ("Orientacion_grados", QVariant.Double), ("Motor_encendido", QVariant.String),
             ("marca_planilla", QVariant.String), ("servicio_planilla", QVariant.String), ("base", QVariant.String)]
    provider.addAttributes([QgsField(n, t) for n, t in names])
    layer.updateFields()
    transform = QgsCoordinateTransform(QgsCoordinateReferenceSystem("EPSG:4326"), layer.crs(), context.transformContext())
    features = []
    counts = Counter()
    for plate, stamp, lon, lat, speed, orientation, power in sorted(points, key=lambda p: (p[0], p[1])):
        meta = metadata[plate]
        f = QgsFeature(layer.fields())
        f.setGeometry(QgsGeometry.fromPointXY(transform.transform(QgsPointXY(lon, lat))))
        f.setAttributes([plate, stamp.isoformat(), stamp.date().isoformat(), stamp.strftime("%H:%M:%S"),
                         float_parser(speed), float_parser(orientation), None if power is None else str(power),
                         meta.get("Marca") or None, meta.get("Servicio") or None, meta.get("Base") or None])
        features.append(f)
        counts[plate] += 1
        if len(features) >= 5000:
            provider.addFeatures(features)
            features = []
    if features:
        provider.addFeatures(features)
    layer.updateExtents()

    with tempfile.TemporaryDirectory(prefix="gps_descarga_", dir=parent) as temp:
        staging = os.path.join(temp, "gps.gpkg")
        options = QgsVectorFileWriter.SaveVectorOptions()
        options.driverName = "GPKG"
        options.layerName = "gps_puntos"
        result = QgsVectorFileWriter.writeAsVectorFormatV3(layer, staging, context.transformContext(), options)
        if result[0] != QgsVectorFileWriter.NoError:
            raise QgsProcessingException("No se pudo guardar el GeoPackage GPS: " + str(result[1]))
        with closing(sqlite3.connect(staging)) as conn:
            columns = list(dict.fromkeys(k for r in catalogue for k in r))
            quote = lambda s: '"' + s.replace('"', '""') + '"'
            conn.execute("CREATE TABLE matriculas_intra (" + ",".join(quote(c) + " TEXT" for c in columns) + ")")
            conn.executemany("INSERT INTO matriculas_intra VALUES (" + ",".join("?" for _ in columns) + ")", [[r.get(c) for c in columns] for r in catalogue])
            conn.execute("CREATE TABLE descarga_consultas (consulta INTEGER, desde TEXT, hasta TEXT, matriculas TEXT, registros INTEGER, estado TEXT)")
            conn.executemany("INSERT INTO descarga_consultas VALUES (?,?,?,?,?,?)", logs)
            for name in ("matriculas_intra", "descarga_consultas"):
                conn.execute("INSERT INTO gpkg_contents(table_name,data_type,identifier) VALUES (?, 'attributes', ?)", (name, name))
            conn.commit()
        os.rename(staging, destination)
    if feedback:
        feedback.pushInfo(f"GPS guardado en: {destination} ({len(points)} puntos unicos).")
    return layer, destination
