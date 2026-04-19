"""
generar_visor.py
----------------
Lee BASE_PANORAMA.csv y genera visor_intervenciones.html:
un reporte HTML autocontenido con filtros, parrafos automaticos
y matriz de tipologias por nivel geografico.

Uso:
    python3 generar_visor.py <ruta_a_BASE_PANORAMA.csv>
    python3 generar_visor.py              # busca en ./dta/
"""

import sys, os, json
from pathlib import Path
from collections import defaultdict

import pandas as pd
import numpy as np


def load(path):
    df = pd.read_csv(path, dtype=str, low_memory=False)
    for c in ["monto_inversion","devengado","pim","pia","costo_actualizado_bi",
              "avance_fisico","avance_financiero","matricula",
              "monto_asignado_total","monto_transferido","total_bienes",
              "capacidad_operativa","latitud","longitud"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    for c in df.columns:
        if df[c].dtype == object:
            df[c] = df[c].fillna("").str.strip()
    return df


TIPOS = ["PROYECTO","MANTENIMIENTO","ACONDICIONAMIENTO","ACCESIBILIDAD",
         "MODULOS","MOBILIARIO/EQUIPAMIENTO","ASISTENCIA TECNICA",
         "INSPECCION","ASESORAMIENTO"]


def stats(df):
    n = len(df)
    cuis = df.loc[df["cui"].replace("",np.nan).notna(), "cui"] if "cui" in df.columns else pd.Series()
    n_cui = cuis.nunique()
    # Monto y devengado: desduplicar por CUI para no contabilizar doble
    if "cui" in df.columns and "monto_inversion" in df.columns:
        df_cui = df[df["cui"] != ""].drop_duplicates(subset="cui", keep="first")
        monto = df_cui["monto_inversion"].sum()
    else:
        monto = 0
    if "cui" in df.columns and "devengado" in df.columns:
        df_cui = df[df["cui"] != ""].drop_duplicates(subset="cui", keep="first")
        dev = df_cui["devengado"].sum()
    else:
        dev = 0
    avf = df["avance_fisico"].mean() if "avance_fisico" in df.columns else np.nan
    return n, n_cui, monto, dev, avf


def tipologia_matrix(df, group_col):
    rows = []
    for name, g in df.groupby(group_col):
        if not name:
            continue
        n_cui = g.loc[g["cui"].replace("",np.nan).notna(), "cui"].nunique() if "cui" in g.columns else 0
        row = {"nombre": name, "total": len(g), "n_cui": n_cui}
        for t in TIPOS:
            row[t] = int((g["tipo_intervencion_gral"] == t).sum())
        rows.append(row)
    rows.sort(key=lambda x: -x["total"])
    return rows


def parrafo(nombre, df):
    n, n_cui, monto, dev, avf = stats(df)
    by_tipo = df.groupby("tipo_intervencion_gral").size().sort_values(ascending=False)
    tipos_txt = ", ".join(f"{t} ({c})" for t, c in by_tipo.items() if c > 0)
    by_ent = df.groupby("entidad").size().sort_values(ascending=False)
    ent_txt = ", ".join(f"{e} ({c})" for e, c in by_ent.items() if c > 0)
    m = f"S/ {monto/1e6:,.2f} millones" if monto > 0 else "sin dato de monto"
    d = f"S/ {dev/1e6:,.2f} millones devengados" if dev > 0 else ""
    a = f"avance fisico promedio de {avf*100:.1f}%" if not np.isnan(avf) and avf > 0 else ""
    parts = [m]
    if d: parts.append(d)
    if a: parts.append(a)
    econ = ", con ".join(parts)

    return (f"En <b>{nombre}</b> se identifican <b>{n:,}</b> registros de intervencion "
            f"asociados a <b>{n_cui:,}</b> CUI unicos (monto sin duplicar por CUI). "
            f"Por tipo de intervencion: {tipos_txt}. "
            f"Por entidad: {ent_txt}. "
            f"El monto total de inversion asciende a <b>{econ}</b>.")


def build_html(df):
    # Precompute data
    deptos = sorted(df["departamento"].unique())
    deptos = [d for d in deptos if d]

    # National stats
    nat_parr = parrafo("TODO EL PAIS", df)
    nat_matrix = tipologia_matrix(df, "departamento")

    # Per-depto data (JSON for JS)
    depto_data = {}
    for dep in deptos:
        dd = df[df["departamento"] == dep]
        depto_data[dep] = {
            "parrafo": parrafo(dep, dd),
            "provs": {}
        }
        provs = sorted(dd["provincia"].unique())
        for prov in [p for p in provs if p]:
            dp = dd[dd["provincia"] == prov]
            depto_data[dep]["provs"][prov] = {
                "parrafo": parrafo(f"{prov}, {dep}", dp),
                "dists": {}
            }
            dists = sorted(dp["distrito"].unique())
            for dist in [d for d in dists if d]:
                dd2 = dp[dp["distrito"] == dist]
                depto_data[dep]["provs"][prov]["dists"][dist] = {
                    "parrafo": parrafo(f"{dist}, {prov}, {dep}", dd2),
                    "locales": {}
                }
                if "codigo_local" in dd2.columns:
                    for cl, gl in dd2.groupby("codigo_local"):
                        if not cl:
                            continue
                        nie = gl["nombre_ie"].iloc[0] if "nombre_ie" in gl.columns and gl["nombre_ie"].iloc[0] else cl
                        depto_data[dep]["provs"][prov]["dists"][dist]["locales"][cl] = {
                            "nombre": nie,
                            "parrafo": parrafo(f"Local {cl} - {nie}", gl)
                        }

    # Tipologia table by depto
    tip_rows_html = ""
    for r in nat_matrix:
        tip_rows_html += "<tr>"
        tip_rows_html += f"<td class='dept-link' onclick=\"selectDepto('{r['nombre']}')\">{r['nombre']}</td>"
        tip_rows_html += f"<td class='num'>{r['total']:,}</td>"
        tip_rows_html += f"<td class='num'>{r.get('n_cui',0):,}</td>"
        for t in TIPOS:
            v = r.get(t, 0)
            cls = "num has" if v > 0 else "num zero"
            tip_rows_html += f"<td class='{cls}'>{v}</td>"
        tip_rows_html += "</tr>\n"

    tip_header = "".join(f"<th>{t[:12]}</th>" for t in TIPOS)

    n_total, n_cui, monto_t, dev_t, avf_t = stats(df)

    depto_options = "".join(f'<option value="{d}">{d}</option>' for d in deptos)

    html = f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Visor de Intervenciones - MINEDU</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: 'Segoe UI', system-ui, sans-serif; background: #f5f6fa; color: #333; }}
.header {{ background: linear-gradient(135deg, #1a237e, #283593); color: white; padding: 20px 30px; }}
.header h1 {{ font-size: 1.4em; }}
.header p {{ opacity: 0.8; font-size: 0.85em; margin-top: 4px; }}
.container {{ max-width: 1400px; margin: 0 auto; padding: 15px; }}
.kpis {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; margin: 15px 0; }}
.kpi {{ background: white; border-radius: 8px; padding: 15px; box-shadow: 0 1px 3px rgba(0,0,0,.1); }}
.kpi .label {{ font-size: 0.75em; color: #666; text-transform: uppercase; }}
.kpi .value {{ font-size: 1.6em; font-weight: 700; color: #1a237e; }}
.card {{ background: white; border-radius: 8px; padding: 18px; margin: 12px 0; box-shadow: 0 1px 3px rgba(0,0,0,.1); }}
.card h2 {{ font-size: 1.05em; color: #1a237e; margin-bottom: 10px; border-bottom: 2px solid #e8eaf6; padding-bottom: 6px; }}
.parrafo {{ line-height: 1.7; font-size: 0.9em; background: #fafafa; padding: 12px; border-left: 4px solid #3f51b5; border-radius: 4px; }}
.parrafo b {{ color: #1a237e; }}
.filters {{ display: flex; gap: 10px; flex-wrap: wrap; align-items: center; margin: 12px 0; }}
.filters select {{ padding: 6px 10px; border: 1px solid #ccc; border-radius: 4px; font-size: 0.85em; }}
.filters label {{ font-size: 0.8em; font-weight: 600; color: #555; }}
table {{ width: 100%; border-collapse: collapse; font-size: 0.78em; }}
th {{ background: #283593; color: white; padding: 6px 4px; text-align: center; position: sticky; top: 0; }}
td {{ padding: 5px 4px; border-bottom: 1px solid #e0e0e0; }}
td.num {{ text-align: right; }}
td.has {{ background: #e8f5e9; font-weight: 600; }}
td.zero {{ color: #ccc; }}
tr:hover {{ background: #e8eaf6; }}
.dept-link {{ color: #1565c0; cursor: pointer; text-decoration: underline; font-weight: 600; }}
.scroll-table {{ max-height: 500px; overflow-y: auto; }}
#detail {{ display: none; }}
.btn {{ padding: 6px 14px; background: #3f51b5; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 0.8em; }}
.btn:hover {{ background: #283593; }}
.back {{ margin-bottom: 10px; }}
</style>
</head>
<body>
<div class="header">
  <h1>Visor de Intervenciones en Infraestructura Educativa</h1>
  <p>MINEDU &mdash; Generado desde BASE_PANORAMA</p>
</div>
<div class="container">

<!-- KPIs -->
<div class="kpis">
  <div class="kpi"><div class="label">Total intervenciones</div><div class="value">{n_total:,}</div></div>
  <div class="kpi"><div class="label">CUI unicos</div><div class="value">{n_cui:,}</div></div>
  <div class="kpi"><div class="label">Monto inversion</div><div class="value">S/ {monto_t/1e6:,.1f} M</div></div>
  <div class="kpi"><div class="label">Devengado</div><div class="value">S/ {dev_t/1e6:,.1f} M</div></div>
  <div class="kpi"><div class="label">Avance fisico prom.</div><div class="value">{(avf_t or 0)*100:.1f}%</div></div>
</div>

<!-- Nacional -->
<div class="card">
  <h2>Reporte Nacional</h2>
  <div class="parrafo">{nat_parr}</div>
</div>

<!-- Matriz tipologias por departamento -->
<div class="card">
  <h2>Matriz de tipologias por departamento</h2>
  <p style="font-size:0.78em;color:#666;margin-bottom:8px;">Click en el departamento para ver detalle por provincia/distrito/local.</p>
  <div class="scroll-table">
  <table>
    <thead><tr><th>Departamento</th><th>Total</th><th>CUI unicos</th>{tip_header}</tr></thead>
    <tbody>{tip_rows_html}</tbody>
  </table>
  </div>
</div>

<!-- Filtros para detalle -->
<div class="card" id="detail">
  <button class="btn back" onclick="goBack()">&#8592; Volver a Nacional</button>
  <h2 id="detail-title">Detalle</h2>

  <div class="filters">
    <div><label>Departamento</label><br><select id="sel-depto" onchange="onDepto()"><option value="">-- Seleccione --</option>{depto_options}</select></div>
    <div><label>Provincia</label><br><select id="sel-prov" onchange="onProv()"><option value="">-- Todas --</option></select></div>
    <div><label>Distrito</label><br><select id="sel-dist" onchange="onDist()"><option value="">-- Todos --</option></select></div>
    <div><label>Local educativo</label><br><select id="sel-local" onchange="onLocal()"><option value="">-- Todos --</option></select></div>
  </div>

  <div class="parrafo" id="detail-parrafo"></div>
</div>

</div>

<script>
const DATA = {json.dumps(depto_data, ensure_ascii=False)};

function selectDepto(d) {{
  document.getElementById('sel-depto').value = d;
  onDepto();
  document.getElementById('detail').style.display = 'block';
  document.getElementById('detail').scrollIntoView({{behavior:'smooth'}});
}}

function onDepto() {{
  const d = document.getElementById('sel-depto').value;
  document.getElementById('detail').style.display = d ? 'block' : 'none';
  if (!d) return;
  const info = DATA[d];
  document.getElementById('detail-title').textContent = d;
  document.getElementById('detail-parrafo').innerHTML = info.parrafo;
  // populate provs
  const sp = document.getElementById('sel-prov');
  sp.innerHTML = '<option value="">-- Todas --</option>';
  Object.keys(info.provs).sort().forEach(p => {{
    sp.innerHTML += `<option value="${{p}}">${{p}}</option>`;
  }});
  document.getElementById('sel-dist').innerHTML = '<option value="">-- Todos --</option>';
  document.getElementById('sel-local').innerHTML = '<option value="">-- Todos --</option>';
}}

function onProv() {{
  const d = document.getElementById('sel-depto').value;
  const p = document.getElementById('sel-prov').value;
  if (!p) {{ onDepto(); return; }}
  const info = DATA[d].provs[p];
  document.getElementById('detail-title').textContent = p + ', ' + d;
  document.getElementById('detail-parrafo').innerHTML = info.parrafo;
  const sd = document.getElementById('sel-dist');
  sd.innerHTML = '<option value="">-- Todos --</option>';
  Object.keys(info.dists).sort().forEach(di => {{
    sd.innerHTML += `<option value="${{di}}">${{di}}</option>`;
  }});
  document.getElementById('sel-local').innerHTML = '<option value="">-- Todos --</option>';
}}

function onDist() {{
  const d = document.getElementById('sel-depto').value;
  const p = document.getElementById('sel-prov').value;
  const di = document.getElementById('sel-dist').value;
  if (!di) {{ onProv(); return; }}
  const info = DATA[d].provs[p].dists[di];
  document.getElementById('detail-title').textContent = di + ', ' + p + ', ' + d;
  document.getElementById('detail-parrafo').innerHTML = info.parrafo;
  const sl = document.getElementById('sel-local');
  sl.innerHTML = '<option value="">-- Todos --</option>';
  Object.keys(info.locales).sort().forEach(cl => {{
    const nom = info.locales[cl].nombre;
    sl.innerHTML += `<option value="${{cl}}">${{cl}} - ${{nom}}</option>`;
  }});
}}

function onLocal() {{
  const d = document.getElementById('sel-depto').value;
  const p = document.getElementById('sel-prov').value;
  const di = document.getElementById('sel-dist').value;
  const cl = document.getElementById('sel-local').value;
  if (!cl) {{ onDist(); return; }}
  const info = DATA[d].provs[p].dists[di].locales[cl];
  document.getElementById('detail-title').textContent = 'Local ' + cl + ' - ' + info.nombre;
  document.getElementById('detail-parrafo').innerHTML = info.parrafo;
}}

function goBack() {{
  document.getElementById('detail').style.display = 'none';
  document.getElementById('sel-depto').value = '';
  window.scrollTo({{top: 0, behavior: 'smooth'}});
}}
</script>
</body>
</html>"""
    return html


def main():
    if len(sys.argv) > 1:
        csv_path = sys.argv[1]
    else:
        for p in ["dta/BASE_PANORAMA.csv", "BASE_PANORAMA.csv"]:
            if os.path.exists(p):
                csv_path = p
                break
        else:
            print("No se encontro BASE_PANORAMA.csv")
            print("Uso: python3 generar_visor.py <ruta_csv>")
            return 1

    print(f"Leyendo {csv_path}...")
    df = load(csv_path)
    print(f"  {len(df):,} filas, {len(df.columns)} columnas")

    print("Generando HTML...")
    html = build_html(df)

    out = Path(csv_path).parent / "visor_intervenciones.html"
    out.write_text(html, encoding="utf-8")
    print(f"Visor generado: {out}")
    print(f"  Abrir en navegador: file:///{out.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
