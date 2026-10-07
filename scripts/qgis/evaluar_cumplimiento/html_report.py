# html_report.py - Generador de reportes HTML interactivos con mapas Leaflet
import datetime as _dt
import html as _html
import json
import os
import re
from collections import defaultdict, Counter

DICTIONARY_HTML = """
  <h2>Diccionario de campos</h2>
  <div class="note">
    Esta hoja explica cómo leer los campos y los valores posibles del informe.
    La regla base es: una zona cuenta como programada si el día de semana está marcado y la zona está vigente.
    Para cumplir, por defecto se exige que una visita individual llegue al mismo mínimo de minutos configurado.
  </div>

  <h3>Resumen principal</h3>
  <table>
    <thead><tr><th>Campo</th><th>Qué significa</th><th>Cómo interpretar sus valores</th></tr></thead>
    <tbody>
      <tr><td>Días planificados</td><td>Zona-fecha donde la zona estaba planificada por día de semana y vigente.</td><td>Cantidad de días-zonas planificadas en el período evaluado.</td></tr>
      <tr><td>Días cumplidos en día-turno</td><td>Días planificados con estado cumple_refinado.</td><td>Cantidad de días cumplidos en día-semana y turnos planificados.</td></tr>
      <tr><td>Días cumplidos fuera de turno</td><td>Días planificados con estado cumple_fuera_turno.</td><td>Cantidad de días cumplidos en día-semana en diferente turno al planificado.</td></tr>
      <tr><td>Días no cumplidos</td><td>Días planificados que no quedaron como cumplidos en día-turno ni fuera de turno.</td><td>Cierra el total: planificados = cumplidos en día-turno + cumplidos fuera de turno + no cumplidos.</td></tr>
      <tr><td>Cumplimiento estricto planificado</td><td>Porcentaje de días cumplidos en día-turno sobre días planificados.</td><td>Fórmula: días cumplidos en turno / días planificados.</td></tr>
      <tr><td>Cumplimiento solo día planificado</td><td>Porcentaje de días cumplidos en día-turno o fuera de turno sobre días planificados.</td><td>Fórmula: (días cumplidos en turno + días cumplidos fuera de turno) / días planificados.</td></tr>
    </tbody>
  </table>
"""

def safe_name(text):
    return re.sub(r"[^a-zA-Z0-9_-]", "_", str(text or "")).strip("_")

def logo_data_uri():
    # Logo base SVG en blanco/transparente o minimalista
    return "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg=="

def write_html_report(html_path, rows, service, date_from, date_to, zone_type, rule, feedback, latest_gps_datetime=None, active_turn_ranges=None):
    os.makedirs(os.path.dirname(html_path), exist_ok=True)
    programmed = [row for row in rows if row["programado_eval"] == 1]
    not_programmed_alerts = [
        row for row in rows
        if row["estado_ref"] in {"gps_no_programado_relevante", "gps_no_programado_acumulado"}
    ]
    state_counts = Counter(row["estado_ref"] for row in programmed)
    all_state_counts = Counter(row["estado_ref"] for row in rows)
    ok_states = {"cumple_refinado", "cumple_fuera_turno"}

    def h(value):
        return _html.escape("" if value is None else str(value))

    def pct(value, total):
        return f"{(100.0 * value / total):.1f}%" if total else "0.0%"

    strict_ok_count = state_counts["cumple_refinado"]
    out_of_turn_ok_count = state_counts["cumple_fuera_turno"]
    ok_count = sum(state_counts[state] for state in ok_states)
    programmed_count = len(programmed)
    not_ok_count = max(0, programmed_count - ok_count)
    strict_compliance = (100.0 * strict_ok_count / programmed_count) if programmed_count else 0.0
    compliance = (100.0 * ok_count / programmed_count) if programmed_count else 0.0

    generated_at = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    html_content = f"""<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>Preinforme de cumplimiento Intradomiciliario - {h(service)}</title>
  <style>
    body {{ font-family: Inter, Roboto, Arial, sans-serif; margin: 24px; color: #1f2937; background: #f8fafc; }}
    h1, h2 {{ color: #0f172a; margin-bottom: 8px; }}
    .meta {{ color: #64748b; margin-bottom: 20px; font-size: 14px; }}
    .cards {{ display: flex; flex-wrap: wrap; gap: 12px; margin: 16px 0 24px; }}
    .card {{ border: 1px solid #cbd5e1; border-radius: 10px; padding: 14px 18px; min-width: 160px; background: #ffffff; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }}
    .kpi {{ font-size: 32px; font-weight: 800; color: #2563eb; }}
    .label {{ color: #475569; font-size: 13px; font-weight: 600; margin-top: 4px; }}
    table {{ border-collapse: collapse; width: 100%; margin: 12px 0 28px; font-size: 13px; background: #fff; border-radius: 8px; overflow: hidden; }}
    th, td {{ border: 1px solid #e2e8f0; padding: 9px 12px; text-align: left; vertical-align: top; }}
    th {{ background: #f1f5f9; color: #334155; font-weight: 700; }}
    tr:nth-child(even) {{ background: #f8fafc; }}
    .badge {{ border-radius: 999px; padding: 3px 9px; font-size: 12px; font-weight: 700; white-space: nowrap; }}
    .ok {{ background: #dcfce7; color: #166534; }}
    .warn {{ background: #fef3c7; color: #92400e; }}
    .bad {{ background: #fee2e2; color: #991b1b; }}
    .muted {{ background: #e2e8f0; color: #475569; }}
    .note {{ background: #eff6ff; border-left: 4px solid #3b82f6; padding: 12px 16px; color: #1e40af; border-radius: 4px; margin: 12px 0; }}
  </style>
</head>
<body>
  <h1>Preinforme de Cumplimiento Intradomiciliario</h1>
  <div class="meta">
    <strong>Servicio:</strong> {h(service or "Todos")} |
    <strong>Período:</strong> {h(date_from)} a {h(date_to)} |
    Generado: <strong>{h(generated_at)}</strong>
  </div>

  <h2>Resumen Principal</h2>
  <div class="cards">
    <div class="card"><div class="kpi">{programmed_count}</div><div class="label">Días Planificados</div></div>
    <div class="card"><div class="kpi">{strict_ok_count}</div><div class="label">Cumplidos en Día-Turno</div></div>
    <div class="card"><div class="kpi">{out_of_turn_ok_count}</div><div class="label">Cumplidos Fuera de Turno</div></div>
    <div class="card"><div class="kpi">{not_ok_count}</div><div class="label">Días No Cumplidos</div></div>
    <div class="card"><div class="kpi">{strict_compliance:.1f}%</div><div class="label">Cumplimiento Estricto</div></div>
    <div class="card"><div class="kpi">{compliance:.1f}%</div><div class="label">Cumplimiento General</div></div>
  </div>

  <div class="note">Regla aplicada: {h(rule)}</div>

  <h2>Desglose por Estado</h2>
  <div class="cards">
    {"".join(f'<div class="card"><div class="kpi">{c}</div><div class="label">{h(s)}</div></div>' for s, c in all_state_counts.most_common())}
  </div>

  {DICTIONARY_HTML}
</body>
</html>
"""

    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html_content)
