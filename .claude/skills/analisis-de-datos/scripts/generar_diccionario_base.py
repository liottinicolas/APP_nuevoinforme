"""
Genera el esqueleto TÉCNICO de un diccionario de datos a partir de un CSV
(o cualquier archivo que pandas pueda leer). Deja la columna "Significado de
negocio" en blanco a propósito: eso se completa después de la entrevista con
el usuario (Fase 0 de la skill), nunca se debe inventar.

Uso:
    python generar_diccionario_base.py ruta/al/archivo.csv [--sep ";"] [--out diccionario_base.md]
"""

import argparse
import sys

import pandas as pd


def cargar(ruta: str, sep: str | None) -> pd.DataFrame:
    intentos = [sep] if sep else [",", ";", "\t", "|"]
    ultimo_error = None
    for s in intentos:
        try:
            df = pd.read_csv(ruta, sep=s, engine="python")
            if df.shape[1] > 1:
                return df
        except Exception as e:  # noqa: BLE001
            ultimo_error = e
    if ultimo_error:
        raise ultimo_error
    raise ValueError("No se pudo inferir el separador del archivo.")


def resumen_columna(df: pd.DataFrame, col: str) -> dict:
    serie = df[col]
    n = len(serie)
    n_nulos = serie.isna().sum()
    pct_nulos = round(100 * n_nulos / n, 1) if n else 0
    n_unicos = serie.nunique(dropna=True)
    ejemplos = serie.dropna().unique()[:4]
    ejemplos_str = ", ".join(str(e) for e in ejemplos)
    return {
        "columna": col,
        "tipo": str(serie.dtype),
        "pct_nulos": pct_nulos,
        "n_unicos": n_unicos,
        "ejemplos": ejemplos_str,
    }


def generar_markdown(df: pd.DataFrame, nombre_fuente: str) -> str:
    filas = [resumen_columna(df, c) for c in df.columns]
    lineas = [
        f"# Diccionario de datos (esqueleto técnico) — {nombre_fuente}",
        "",
        f"Filas: {len(df)} · Columnas: {len(df.columns)}",
        "",
        "> La columna 'Significado de negocio' se completa después de preguntarle "
        "al usuario (Fase 0). No inventar.",
        "",
        "| Columna | Tipo | % Nulos | Valores únicos | Ejemplos | Significado de negocio |",
        "|---|---|---|---|---|---|",
    ]
    for f in filas:
        lineas.append(
            f"| {f['columna']} | {f['tipo']} | {f['pct_nulos']}% | "
            f"{f['n_unicos']} | {f['ejemplos']} | _(completar)_ |"
        )
    return "\n".join(lineas)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archivo", help="Ruta al CSV (u otro archivo tabular)")
    parser.add_argument("--sep", default=None, help="Separador (si no, se infiere)")
    parser.add_argument(
        "--out", default="diccionario_base.md", help="Archivo de salida markdown"
    )
    args = parser.parse_args()

    df = cargar(args.archivo, args.sep)
    md = generar_markdown(df, args.archivo)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write(md)

    print(f"Diccionario base generado en: {args.out}")
    print(f"({len(df)} filas, {len(df.columns)} columnas)")


if __name__ == "__main__":
    sys.exit(main())
