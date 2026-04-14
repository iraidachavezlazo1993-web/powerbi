"""
Consolidación de bases PEIP, ANIN, UGRD, UGEO contra CUI_cartera_GN.

- Lee los CUIs de cada fuente.
- Elimina duplicados dentro de cada fuente.
- Hace cruce con CUI_cartera_GN: si el CUI ya existe, lo conserva;
  si no existe, lo agrega con la procedencia correspondiente
  en la columna `cartera_gn`.
- Etiquetas de procedencia:
    ANIN                       -> "ANIN"
    PEIP hoja IMPLEMENTADOS    -> "PEIP - IMPLEMENTADOS"
    PEIP hoja CONTINGENCIA     -> "PEIP - CONTINGENCIA"
    UGRD hoja PIRCC            -> "UGRD - PIRCC"
    UGRD hoja MBR              -> "UGRD - MBR"
    UGRD hoja ME               -> "UGRD - ME"
    UGEO                       -> "UGEO - Obra Pública"
"""

import pandas as pd
from pathlib import Path

BASE = Path(__file__).parent

# (archivo, hoja, nombre columna CUI en la fila de cabecera, etiqueta cartera_gn)
FUENTES = [
    ("ANIN.xlsx",  "Anexo 1",       "CUI / ÍDEA",   "ANIN"),
    ("PEIP.xlsx",  "IMPLEMENTADOS", "CUI",          "PEIP - IMPLEMENTADOS"),
    ("PEIP.xlsx",  "CONTINGENCIA",  "CUI",          "PEIP - CONTINGENCIA"),
    ("UGRD.xlsx",  "PIRCC",         "CUI",          "UGRD - PIRCC"),
    ("UGRD.xlsx",  "MBR",           "CUI",          "UGRD - MBR"),
    ("UGRD.xlsx",  "ME",            "CUI",          "UGRD - ME"),
    ("UGEO.xlsx",  "UGEO",          "CUI",          "UGEO - Obra Pública"),
]

HEADER_ROW = 2  # Los encabezados reales están en la 3ra fila (índice 2)


def normaliza_cui(valor):
    """Convierte el CUI a string limpio. Descarta vacíos / no numéricos."""
    if pd.isna(valor):
        return None
    s = str(valor).strip()
    if not s or s.lower() in {"nan", "none", "-", "—"}:
        return None
    # Si viene como float (p.ej. 2503451.0) lo pasamos a entero.
    try:
        f = float(s.replace(",", ""))
        if f.is_integer():
            return str(int(f))
    except ValueError:
        pass
    return s


def cargar_cuis(archivo, hoja, col_cui, etiqueta):
    ruta = BASE / archivo
    df = pd.read_excel(ruta, sheet_name=hoja, header=HEADER_ROW)
    if col_cui not in df.columns:
        raise KeyError(f"No se encontró columna '{col_cui}' en {archivo}/{hoja}. "
                       f"Columnas: {list(df.columns)}")
    cuis = df[col_cui].map(normaliza_cui).dropna()
    # Deduplicación dentro de la fuente
    cuis = cuis.drop_duplicates()
    out = pd.DataFrame({"CUI": cuis.values, "cartera_gn": etiqueta})
    print(f"  {archivo:<15} / {hoja:<15} -> {len(out):>5} CUIs únicos")
    return out


def main():
    # 1) Base existente
    base_gn = pd.read_excel(BASE / "CUI_cartera_GN.xlsx", sheet_name="Hoja1")
    base_gn["CUI"] = base_gn["CUI"].map(normaliza_cui)
    base_gn = base_gn.dropna(subset=["CUI"]).drop_duplicates(subset=["CUI"])
    print(f"CUI_cartera_GN inicial: {len(base_gn)} registros únicos\n")

    print("Cargando fuentes:")
    fuentes = [cargar_cuis(a, h, c, e) for a, h, c, e in FUENTES]
    nuevos = pd.concat(fuentes, ignore_index=True)

    # 2) Deduplicar entre las nuevas fuentes (si un CUI está en varias hojas,
    #    concatenamos las etiquetas separadas por " | ")
    nuevos = (nuevos
              .groupby("CUI", as_index=False)["cartera_gn"]
              .agg(lambda x: " | ".join(sorted(set(x)))))
    print(f"\nTotal de CUIs únicos aportados por las fuentes: {len(nuevos)}")

    # 3) Cruce con CUI_cartera_GN: sólo agregamos los que NO están
    cuis_existentes = set(base_gn["CUI"])
    mask_nuevos = ~nuevos["CUI"].isin(cuis_existentes)
    a_agregar = nuevos[mask_nuevos].copy()
    print(f"CUIs nuevos a agregar (no estaban en CUI_cartera_GN): {len(a_agregar)}")
    print(f"CUIs que ya estaban (se conservan con su etiqueta original): "
          f"{len(nuevos) - len(a_agregar)}")

    consolidado = pd.concat([base_gn, a_agregar], ignore_index=True)
    consolidado = consolidado.drop_duplicates(subset=["CUI"]).reset_index(drop=True)

    # 4) Exportar
    salida = BASE / "CUI_cartera_GN_consolidado.xlsx"
    with pd.ExcelWriter(salida, engine="openpyxl") as w:
        consolidado.to_excel(w, sheet_name="Consolidado", index=False)
        a_agregar.to_excel(w, sheet_name="Solo_Nuevos", index=False)
        nuevos.to_excel(w, sheet_name="Todas_las_Fuentes", index=False)
    print(f"\nArchivo generado: {salida.name}")
    print(f"Total final en 'Consolidado': {len(consolidado)} CUIs")


if __name__ == "__main__":
    main()
