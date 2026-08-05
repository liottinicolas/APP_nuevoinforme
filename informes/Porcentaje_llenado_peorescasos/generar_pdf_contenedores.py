import os
import pyreadr
import pandas as pd
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

# Genera un PDF con una sección por cada gid presente en $resultado (salida de
# analizar_peores_contenedores() en PorcentajeLlenado.R): identificación,
# historial crudo de visitas filtrado a ese gid, y sus métricas agregadas.
# Se invoca vía generar_pdf_contenedores.R (reticulate), que deja los datos
# en data/pdf_resultado.rds y data/pdf_crudo.rds antes de correr este script.

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")
SALIDAS_DIR = os.path.normpath(os.path.join(BASE_DIR, "..", "salidas"))

COLUMNAS_IDENTIFICACION = ["Circuito", "Posicion", "Direccion", "gid", "Circuito_corto", "Oficina"]
COLUMNAS_CRUDO = ["Fecha", "Levantado", "Turno_levantado", "Porcentaje_llenado", "Incidencia", "Condicion"]
COLUMNAS_RESULTADO = ["n_recolecciones", "n_saturaciones", "tasa_saturacion", "llenado_promedio", "frecuencia_dias", "cuadrante"]

ESTILO_TABLA = TableStyle([
    ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
    ("LINEBELOW", (0, 0), (-1, 0), 1, colors.grey),
    ("GRID", (0, 0), (-1, -1), 0.5, colors.lightgrey),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("TOPPADDING", (0, 0), (-1, -1), 3),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f7f7f5")]),
])

ESTILO_HEADER = ParagraphStyle("Header", fontName="Helvetica-Bold", fontSize=7.5, leading=9)
ESTILO_CELDA = ParagraphStyle("Celda", fontName="Helvetica", fontSize=7.5, leading=9)

ANCHO_TABLA = 18 * cm
# Peso relativo de cada columna conocida (columnas no listadas usan 1.5 por defecto);
# cuadrante es texto largo y necesita mucho más espacio que el resto para no cortarse.
PESO_COLUMNA = {
    "Direccion": 2.6, "Incidencia": 2, "Condicion": 2, "cuadrante": 4,
    "Circuito": 2.2, "Circuito_corto": 1.3, "Turno_levantado": 1.4,
}


def df_a_tabla(df, columnas, ancho_total=ANCHO_TABLA):
    columnas_presentes = [c for c in columnas if c in df.columns]
    # astype(object) primero: pyreadr trae columnas de factor de R como Categorical,
    # que no admite fillna("") si "" no es una categoría existente. where() en vez de
    # fillna() evita el warning de downcasting de pandas al mezclar tipos.
    df_fmt = df[columnas_presentes].astype(object)
    df_fmt = df_fmt.where(df_fmt.notna(), "").astype(str)

    encabezado = [Paragraph(c, ESTILO_HEADER) for c in columnas_presentes]
    filas = [[Paragraph(valor, ESTILO_CELDA) for valor in fila] for fila in df_fmt.values.tolist()]
    datos = [encabezado] + filas

    pesos = [PESO_COLUMNA.get(c, 1.5) for c in columnas_presentes]
    total_peso = sum(pesos)
    anchos = [ancho_total * p / total_peso for p in pesos]

    t = Table(datos, colWidths=anchos)
    t.setStyle(ESTILO_TABLA)
    return t


def formatear_resultado(fila):
    fila = fila.copy()
    if "tasa_saturacion" in fila:
        fila["tasa_saturacion"] = f"{float(fila['tasa_saturacion']) * 100:.1f}%"
    if "llenado_promedio" in fila:
        fila["llenado_promedio"] = f"{float(fila['llenado_promedio']):.1f}"
    if "frecuencia_dias" in fila:
        fila["frecuencia_dias"] = f"{float(fila['frecuencia_dias']):.2f}"
    return fila


def generar_pdf(resultado, crudo, ruta_salida):
    doc = SimpleDocTemplate(
        ruta_salida, pagesize=A4,
        rightMargin=1.5 * cm, leftMargin=1.5 * cm,
        topMargin=1.5 * cm, bottomMargin=1.5 * cm
    )
    estilos = getSampleStyleSheet()
    estilo_titulo = ParagraphStyle("Titulo", parent=estilos["Heading1"], fontSize=13, spaceAfter=10)
    estilo_gid = ParagraphStyle("Gid", parent=estilos["Heading2"], fontSize=12, spaceBefore=4, spaceAfter=6, textColor=colors.HexColor("#a50f15"))
    estilo_seccion = ParagraphStyle("Seccion", parent=estilos["Heading3"], fontSize=10, spaceBefore=8, spaceAfter=4)

    elementos = [Paragraph("Informe por contenedor — peores casos de saturación", estilo_titulo)]

    gids = resultado["gid"].astype(str).tolist()
    for i, gid in enumerate(gids):
        fila_resultado = resultado[resultado["gid"].astype(str) == gid].iloc[0]
        crudo_gid = crudo[crudo["gid"].astype(str) == gid].copy()
        crudo_gid["Fecha"] = crudo_gid["Fecha"].astype(str)
        crudo_gid = crudo_gid.sort_values(by="Fecha", ascending=False)

        elementos.append(Paragraph(f"Contenedor {gid}", estilo_gid))

        # --- Identificación: fila más reciente del crudo para este gid ---
        if not crudo_gid.empty:
            identificacion = crudo_gid.iloc[[0]]
            elementos.append(Paragraph("Identificación", estilo_seccion))
            elementos.append(df_a_tabla(identificacion, COLUMNAS_IDENTIFICACION))
            elementos.append(Spacer(1, 8))

        # --- Historial crudo filtrado a este gid ---
        elementos.append(Paragraph(f"Historial de visitas ({len(crudo_gid)} filas)", estilo_seccion))
        if crudo_gid.empty:
            elementos.append(Paragraph("Sin filas crudas para este gid en la ventana analizada.", estilos["Normal"]))
        else:
            elementos.append(df_a_tabla(crudo_gid, COLUMNAS_CRUDO))
        elementos.append(Spacer(1, 8))

        # --- Resultado agregado ---
        elementos.append(Paragraph("Resultado (métricas agregadas)", estilo_seccion))
        fila_fmt = formatear_resultado(fila_resultado)
        tabla_resultado = pd.DataFrame([fila_fmt])
        elementos.append(df_a_tabla(tabla_resultado, COLUMNAS_RESULTADO))

        if i < len(gids) - 1:
            elementos.append(PageBreak())

    doc.build(elementos)


if __name__ == "__main__":
    resultado = pyreadr.read_r(os.path.join(DATA_DIR, "pdf_resultado.rds"))[None]
    crudo = pyreadr.read_r(os.path.join(DATA_DIR, "pdf_crudo.rds"))[None]

    if resultado.empty:
        print("No hay contenedores en el resultado; no se genera PDF.")
    else:
        os.makedirs(SALIDAS_DIR, exist_ok=True)
        nombre_salida = os.environ.get("PDF_CONTENEDORES_SALIDA", "informe_contenedores.pdf")
        ruta_salida = os.path.join(SALIDAS_DIR, nombre_salida)
        generar_pdf(resultado, crudo, ruta_salida)
        print(f"PDF generado: {ruta_salida}")
