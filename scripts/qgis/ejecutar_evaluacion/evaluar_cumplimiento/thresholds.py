# thresholds.py - Perfiles de mínimos y reglas por zona (con carga desde JSON externo)
import json
import os
import unicodedata
from qgis.core import QgsProcessingException

DEFAULT_CONFIG_PATH = os.path.join(os.path.dirname(__file__), "thresholds_mezclado.json")

def load_thresholds_config(config_path=None):
    """Carga los mínimos por zona desde un archivo JSON externo. Si no existe, usa la ruta por defecto."""
    target_path = config_path or DEFAULT_CONFIG_PATH
    if os.path.exists(target_path):
        try:
            with open(target_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                result = {}
                for zone_id, item in data.get("zonas", {}).items():
                    result[zone_id] = (
                        item["nombre"],
                        float(item["minutos"]),
                        int(item["puntos_totales"]),
                        int(item["puntos_movimiento"])
                    )
                return result, data.get("perfil", "Mezclado (JSON Externo)")
        except Exception:
            pass
    return DEFAULT_MINIMOS_MEZCLADO, "Mezclado 2026-10-02"

DEFAULT_MINIMOS_MEZCLADO = {
    "173": ("31 DE AGOSTO", 5, 20, 10),
    "9": ("ABAYUBA", 60, 20, 10),
    "93": ("BARRIO 14", 17, 20, 10),
    "135": ("BARRIO ZITARROSA", 60, 20, 10),
    "134": ("BELLA ITALIA 1", 60, 20, 10),
    "160": ("BELLA ITALIA 2", 60, 20, 10),
    "14": ("CAPURRO 1", 60, 20, 10),
    "1": ("CAPURRO 2", 60, 20, 10),
    "2": ("CAPURRO 3", 60, 20, 10),
    "17": ("CARRASCO 1", 60, 20, 10),
    "18": ("CARRASCO 2", 60, 20, 10),
    "176": ("CARRASCO NORTE", 60, 20, 10),
    "88": ("CERRO", 60, 20, 10),
    "6": ("CERRO", 60, 20, 10),
    "7": ("COMPLEJO HABITACIONAL TOBAS", 3, 15, 4),
    "166": ("COOPERATIVAS F", 60, 20, 10),
    "30": ("LA TEJA 1", 60, 20, 10),
    "31": ("LA TEJA 2", 60, 20, 10),
    "32": ("LA TEJA 3", 60, 20, 10),
    "170": ("LAS ACACIAS", 29, 20, 10),
    "10": ("LOS BULEVARES", 60, 20, 10),
    "95": ("MALVIN 1", 60, 20, 10),
    "13": ("NUEVO LLAMAS", 60, 20, 10),
    "157": ("NUEVO PARIS 1", 60, 20, 10),
    "158": ("NUEVO PARIS 2", 60, 20, 10),
    "178": ("PARQUE GUARANI", 60, 20, 10),
    "97": ("PARQUE RIVERA 1", 55, 20, 10),
    "96": ("PARQUE RIVERA 2", 60, 20, 10),
    "159": ("PLAN JUNTOS", 30, 20, 10),
    "8": ("PRADO NORTE", 60, 20, 10),
    "11": ("SAN BARTOLO Y ANEXO", 60, 20, 10),
    "12": ("SANTIAGO VAZQUEZ", 60, 20, 10),
    "132": ("TRANSATLANTICO", 60, 20, 10),
    "179": ("VILLA ESPAÑOLA", 60, 20, 10),
    "156": ("VIVIENDAS DIONISIO DIAZ", 55, 20, 10),
}
MINIMOS_MEZCLADO = DEFAULT_MINIMOS_MEZCLADO

DAY_FIELDS = {
    0: "dia_lunes",
    1: "dia_martes",
    2: "dia_miercoles",
    3: "dia_jueves",
    4: "dia_viernes",
    5: "dia_sabado",
    6: "dia_domingo",
}

def threshold_name(value):
    text = unicodedata.normalize("NFKD", str(value or ""))
    return " ".join("".join(c for c in text if not unicodedata.combining(c)).upper().split())

def get_zone_thresholds(feature, service, enabled, minutes, points, moving, feature_value_fn, service_key_fn, config_path=None):
    default = (minutes, points, moving, "general")
    if not enabled or service_key_fn(service) != service_key_fn("Mezclado"):
        return default
    
    thresholds_dict, profile_name = load_thresholds_config(config_path)
    
    zone_id = str(feature_value_fn(feature, "id") or "").strip()
    if zone_id.endswith(".0"):
        zone_id = zone_id[:-2]
    entry = thresholds_dict.get(zone_id)
    if entry is None:
        return default
    if threshold_name(feature_value_fn(feature, "nombre")) != threshold_name(entry[0]):
        raise QgsProcessingException(
            f"El ID {zone_id} del perfil de mínimos corresponde a {entry[0]}, pero el nombre de la capa difiere. "
            "Revise la capa o desmarque Usar mínimos aprobados por zona."
        )
    return (float(entry[1]), entry[2], entry[3], profile_name)
