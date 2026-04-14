"""
clean_excel_to_dta.py
---------------------
Convierte los Excel de cada entidad (PRONIED, PEIP, UE118, ANIN, FONCODES, etc.)
a formato Stata (.dta), aplicando limpieza general:

- Normaliza nombres de columnas (quita tildes, espacios, saltos de línea y
  caracteres especiales; usa snake_case y respeta el limite de 32 chars de Stata).
- Hace strip() de strings, convierte "-", "---", "N/A", "n/a" en missing.
- Elimina filas completamente vacías y duplicados exactos.
- Fuerza a numerico/fecha cuando es posible.
- Identifica llaves candidatas (CUI, codigo local, codigo modular) e imprime
  un reporte con duplicados de esas llaves.
- Exporta una .dta por hoja en el directorio ./dta/, con el prefijo de la entidad.

Uso:
    python3 clean_excel_to_dta.py
"""

from __future__ import annotations

import os
import re
import sys
import unicodedata
from pathlib import Path

import numpy as np
import pandas as pd


BASE_DIR = Path(__file__).resolve().parent
OUT_DIR = BASE_DIR / "dta"
OUT_DIR.mkdir(exist_ok=True)

# Valores que deben tratarse como missing.
MISSING_TOKENS = {"", "-", "--", "---", "----", "-----", "------", "-------",
                  "n/a", "na", "n.a.", "nan", "none", "null", ".", "..",
                  "s/d", "s/i", "-.", ".-"}

# (archivo, hoja, fila_encabezado, prefijo_salida).
# fila_encabezado usa indice 0 (mismo que pandas "header").
DATASETS: list[tuple[str, str, int, str]] = [
    # PRONIED - UGEO
    ("UGEO.xlsx",     "UGEO",                        2, "PRONIED_UGEO"),
    # PRONIED - UGRD
    ("UGRD.xlsx",     "PIRCC",                       2, "PRONIED_UGRD_PIRCC"),
    ("UGRD.xlsx",     "MBR",                         2, "PRONIED_UGRD_MBR"),
    ("UGRD.xlsx",     "ME",                          2, "PRONIED_UGRD_ME"),
    # PEIP
    ("PEIP.xlsx",     "IMPLEMENTADOS",               2, "PEIP_IMPLEMENTADOS"),
    ("PEIP.xlsx",     "CONTINGENCIA",                2, "PEIP_CONTINGENCIA"),
    ("PEIP.xlsx",     "MANTENIMIENTO",               2, "PEIP_MANTENIMIENTO"),
    # UE118
    ("UE118.xlsx",    "PMESUT",                      1, "UE118_PMESUT"),
    ("UE118.xlsx",    "PMESTP",                      1, "UE118_PMESTP"),
    # ANIN
    ("ANIN.xlsx",     "Anexo 1",                     2, "ANIN_Anexo1"),
    # FONCODES
    ("FONCODES.xlsx", "LE_INTERVENIDOS_2017-2025",   1, "FONCODES_LE_INTERVENIDOS"),
    ("FONCODES.xlsx", "REPORTE_MANT_ACOND_2025",     1, "FONCODES_MANT_2025"),
    ("FONCODES.xlsx", "REPORTE_MANT_ACOND_2026",     1, "FONCODES_MANT_2026"),
    # Banco de Inversiones MEF (auxiliar)
    ("2026.04.13 Base de Inversiones.xlsx", "Data",  4, "MEF_Base_Inversiones"),
    # Tabla auxiliar cartera GN
    ("CUI_cartera_GN.xlsx", "Hoja1",                 0, "CUI_cartera_GN"),
]

# Pistas de llaves candidatas (se matchean contra el nombre ya normalizado).
KEY_HINTS = [
    "cui", "codigo_unico", "codigo_snip", "codigo_idea", "codigo_inversion",
    "codigo_local", "cod_local", "codigo_modular", "cod_modular", "cod_mod",
]


# ---------------------------------------------------------------------------
# Utilidades de limpieza
# ---------------------------------------------------------------------------

def strip_accents(text: str) -> str:
    """Elimina tildes y diacriticos (NFD)."""
    return "".join(
        c for c in unicodedata.normalize("NFD", text)
        if unicodedata.category(c) != "Mn"
    )


def normalize_colname(name: str, seen: set[str]) -> str:
    """Convierte el nombre de columna a snake_case ASCII <=32 chars,
    evitando colisiones con `seen`."""
    if name is None:
        name = "col"
    s = str(name)
    s = s.replace("\n", " ").replace("\r", " ").replace("\t", " ")
    s = strip_accents(s)
    s = s.lower()
    # Reemplaza cualquier caracter no alfanumerico por _
    s = re.sub(r"[^a-z0-9]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    if not s:
        s = "col"
    if s[0].isdigit():
        s = "v_" + s
    s = s[:32]
    base, i = s, 1
    while s in seen:
        suf = f"_{i}"
        s = (base[: 32 - len(suf)]) + suf
        i += 1
    seen.add(s)
    return s


def clean_string_cell(x):
    if not isinstance(x, str):
        return x
    s = x.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    s = re.sub(r"\s+", " ", s).strip()
    if s.lower() in MISSING_TOKENS:
        return np.nan
    return s


def coerce_numeric(series: pd.Series) -> pd.Series:
    """Intenta convertir la serie a numerico si >=80% de los no-nulos son numeros."""
    if series.dtype.kind in "iufb":
        return series
    sample = series.dropna()
    if sample.empty:
        return series
    as_num = pd.to_numeric(sample, errors="coerce")
    hit = as_num.notna().mean()
    if hit >= 0.8:
        return pd.to_numeric(series, errors="coerce")
    return series


def coerce_datetime(series: pd.Series) -> pd.Series:
    if series.dtype.kind in "Mm":
        return series
    if series.dtype != object:
        return series
    sample = series.dropna().astype(str)
    if sample.empty:
        return series
    looks_datey = sample.str.contains(
        r"\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4}", regex=True
    ).mean()
    if looks_datey < 0.8:
        return series
    try:
        return pd.to_datetime(series, errors="coerce")
    except Exception:
        return series


# ---------------------------------------------------------------------------
# Procesamiento por dataset
# ---------------------------------------------------------------------------

def load_clean(
    file: str, sheet: str, header_row: int, prefix: str
) -> tuple[pd.DataFrame, list[str], dict]:
    """Carga una hoja, la limpia y devuelve (df, keys, info)."""
    info: dict = {"file": file, "sheet": sheet, "prefix": prefix}

    path = BASE_DIR / file
    df = pd.read_excel(path, sheet_name=sheet, header=header_row, dtype=object)
    info["rows_raw"] = len(df)
    info["cols_raw"] = df.shape[1]

    # 1. Renombrar columnas.
    seen: set[str] = set()
    new_cols = [normalize_colname(c, seen) for c in df.columns]
    df.columns = new_cols

    # 2. Descartar columnas totalmente vacias.
    df = df.dropna(axis=1, how="all")

    # 3. Descartar columnas "basura" de tipo unnamed/col que quedaron sin datos
    #    utiles (columnas de margen con algun espacio).
    to_drop = []
    for c in df.columns:
        if c.startswith(("unnamed", "col")) and df[c].dropna().empty:
            to_drop.append(c)
    if to_drop:
        df = df.drop(columns=to_drop)

    # 4. Limpiar strings.
    for c in df.columns:
        if df[c].dtype == object:
            df[c] = df[c].map(clean_string_cell)

    # 5. Quitar filas totalmente vacias.
    df = df.dropna(axis=0, how="all").reset_index(drop=True)

    # 6. Quitar duplicados exactos.
    before = len(df)
    df = df.drop_duplicates().reset_index(drop=True)
    info["dup_rows_removed"] = before - len(df)

    # 7. Coercion de tipos.
    for c in df.columns:
        df[c] = coerce_datetime(df[c])
        if df[c].dtype == object:
            df[c] = coerce_numeric(df[c])
        # Normaliza objetos residuales a str para que Stata no falle.
        if df[c].dtype == object:
            df[c] = df[c].astype("string")

    # 8. Detectar llaves candidatas.
    keys = []
    for c in df.columns:
        for hint in KEY_HINTS:
            if hint in c:
                keys.append(c)
                break

    # 9. Reporte de duplicados en llaves.
    dup_info = {}
    for k in keys:
        dup_count = df[k].dropna().duplicated().sum()
        dup_info[k] = int(dup_count)
    info["keys"] = keys
    info["key_dups"] = dup_info
    info["rows_clean"] = len(df)
    info["cols_clean"] = df.shape[1]

    return df, keys, info


def write_dta(df: pd.DataFrame, out_path: Path) -> None:
    # Stata requiere nombres ASCII snake_case (ya hecho). Versión 118 (Stata 14+)
    # soporta strings unicode y variables hasta 32 chars.
    df_to_write = df.copy()

    # Stata no acepta StringDtype/pandas NA sin castear. Forzamos object.
    for c in df_to_write.columns:
        if pd.api.types.is_string_dtype(df_to_write[c]):
            df_to_write[c] = df_to_write[c].astype(object)
        # Stata no admite columnas totalmente NaN tipadas; las dejamos como str vacio.
        if df_to_write[c].isna().all() and df_to_write[c].dtype == object:
            df_to_write[c] = ""

    df_to_write.to_stata(
        out_path,
        write_index=False,
        version=118,
        variable_labels={
            c: (c[:80]) for c in df_to_write.columns
        },
    )


def main() -> int:
    all_info = []
    for file, sheet, header_row, prefix in DATASETS:
        path = BASE_DIR / file
        if not path.exists():
            print(f"[WARN] no existe {file}, se omite")
            continue
        try:
            df, keys, info = load_clean(file, sheet, header_row, prefix)
        except Exception as e:
            print(f"[ERROR] {file} / {sheet}: {e}")
            continue

        out_path = OUT_DIR / f"{prefix}.dta"
        try:
            write_dta(df, out_path)
            info["out"] = str(out_path.relative_to(BASE_DIR))
        except Exception as e:
            info["out"] = f"ERROR: {e}"
            print(f"[ERROR] escribir {out_path.name}: {e}")

        all_info.append(info)
        print(
            f"OK {prefix:30s} "
            f"raw={info['rows_raw']:>6} "
            f"clean={info['rows_clean']:>6} "
            f"dup_drop={info['dup_rows_removed']:>4} "
            f"keys={keys}"
        )

    # Reporte markdown.
    lines = ["# Reporte de limpieza y conversion Excel -> DTA", ""]
    lines.append("| Dataset | Archivo | Hoja | Filas raw | Filas limpias | Dup. eliminados | Llaves (dup. encontrados) | Salida |")
    lines.append("|---|---|---|---:|---:|---:|---|---|")
    for i in all_info:
        keys_txt = ", ".join(
            f"`{k}`({i['key_dups'].get(k, 0)})" for k in i["keys"]
        ) or "-"
        lines.append(
            f"| {i['prefix']} | {i['file']} | {i['sheet']} | "
            f"{i['rows_raw']} | {i['rows_clean']} | {i['dup_rows_removed']} | "
            f"{keys_txt} | {i.get('out','-')} |"
        )
    lines += [
        "",
        "## Notas",
        "- Llaves detectadas automaticamente por coincidencia con pistas: "
        + ", ".join(f"`{h}`" for h in KEY_HINTS) + ".",
        "- Los numeros entre parentesis al lado de cada llave son "
        "**valores duplicados** (no filas duplicadas) en esa columna. "
        "Si son > 0, la llave por si sola no es unica -> considerar una llave compuesta.",
        "- Valores tratados como missing: " + ", ".join(
            f"`{t}`" for t in sorted(MISSING_TOKENS) if t
        ) + ".",
        "- Formato .dta: version 118 (Stata 14+), soporta Unicode y variables <=32 chars.",
        "",
        "## Entidades pendientes de PRONIED",
        "Falta entregar las bases de UGSC, UGME, UGM y Uzonal para consolidar PRONIED "
        "como una sola base por entidad.",
    ]

    (BASE_DIR / "REPORTE_LIMPIEZA.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"\nReporte guardado en {BASE_DIR / 'REPORTE_LIMPIEZA.md'}")
    print(f"DTAs en {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
