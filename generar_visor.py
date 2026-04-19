"""
generar_visor.py  v2
-------------------
Lee BASE_PANORAMA.csv, deduplica intervenciones por CUI, y genera
visor_intervenciones.html: reporte HTML autocontenido con:
  - KPIs nacionales
  - Matriz de tipologias por departamento
  - Filtros cascada (departamento/provincia/distrito)
  - Parrafo automatico segun el nivel seleccionado
  - Tabla de detalle con cada intervencion unica

Uso:
    python3 generar_visor.py <ruta_a_BASE_PANORAMA.csv>
    python3 generar_visor.py              # busca en ./dta/
"""

import sys, os, json
from pathlib import Path
import pandas as pd
import numpy as np


def load(path):
    df = pd.read_csv(path, dtype=str, low_memory=False)
    for c in ["monto_inversion","devengado","avance_fisico","avance_financiero"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    for c in df.columns:
        if df[c].dtype == object:
            df[c] = df[c].fillna("").str.strip()
    return df


def dedup(df):
    """Deduplica intervenciones:
    - Con CUI: una fila por CUI (la mas completa / primer registro)
    - Sin CUI: una fila por codigo_local + tipo_intervencion_gral + unidad
    """
    has_cui = df[df["cui"] != ""].copy()
    no_cui = df[df["cui"] == ""].copy()

    if not has_cui.empty:
        has_cui["_completeness"] = has_cui.notna().sum(axis=1)
        has_cui = has_cui.sort_values("_completeness", ascending=False)
        has_cui = has_cui.drop_duplicates(subset="cui", keep="first")
        has_cui = has_cui.drop(columns=["_completeness"])

    if not no_cui.empty:
        key = ["codigo_local","tipo_intervencion_gral","unidad"]
        key = [k for k in key if k in no_cui.columns]
        if key:
            no_cui = no_cui.drop_duplicates(subset=key, keep="first")

    return pd.concat([has_cui, no_cui], ignore_index=True)


TIPOS = ["PROYECTO","MANTENIMIENTO","ACONDICIONAMIENTO","ACCESIBILIDAD",
         "MODULOS","MOBILIARIO/EQUIPAMIENTO","ASISTENCIA TECNICA",
         "INSPECCION","ASESORAMIENTO"]


def fmt_money(v):
    if pd.isna(v) or v == 0:
        return "-"
    return f"S/ {v/1e6:,.2f} M"


def fmt_pct(v):
    if pd.isna(v) or v == 0:
        return "-"
    return f"{v*100:.1f}%"


def build_detail_records(df):
    """Construye lista de dicts para la tabla de detalle JS."""
    cols = {
        "cui": "CUI", "codigo_local": "Cod.Local",
        "nombre_inversion": "Nombre", "tipo_intervencion_gral": "Tipo",
        "entidad": "Entidad", "unidad": "Unidad",
        "estado": "Estado", "monto_inversion": "Monto",
        "avance_fisico": "Avance", "departamento": "Depto",
        "provincia": "Provincia", "distrito": "Distrito"
    }
    records = []
    for _, row in df.iterrows():
        r = {}
        for k, label in cols.items():
            if k not in df.columns:
                r[k] = ""
                continue
            v = row[k]
            if k == "monto_inversion":
                r[k] = round(v, 2) if pd.notna(v) else 0
            elif k == "avance_fisico":
                r[k] = round(v, 4) if pd.notna(v) else 0
            else:
                r[k] = str(v) if pd.notna(v) else ""
        records.append(r)
    return records


def stats_from_df(df):
    n = len(df)
    n_cui = df.loc[df["cui"] != "", "cui"].nunique() if "cui" in df.columns else 0
    monto = df["monto_inversion"].sum() if "monto_inversion" in df.columns else 0
    dev = df["devengado"].sum() if "devengado" in df.columns else 0
    avf = df["avance_fisico"].mean() if "avance_fisico" in df.columns else 0
    return {"n": int(n), "n_cui": int(n_cui),
            "monto": round(float(monto), 2),
            "dev": round(float(dev), 2),
            "avf": round(float(avf if pd.notna(avf) else 0), 4)}


def build_html(df):
    nat = stats_from_df(df)

    # Tipologia matrix by depto
    matrix = []
    deptos = sorted([d for d in df["departamento"].unique() if d])
    for dep in deptos:
        dd = df[df["departamento"] == dep]
        row = {"dep": dep, "n": len(dd),
               "n_cui": int(dd.loc[dd["cui"]!="","cui"].nunique())}
        for t in TIPOS:
            row[t] = int((dd["tipo_intervencion_gral"] == t).sum())
        matrix.append(row)
    matrix.sort(key=lambda x: -x["n"])

    # All records for JS detail table
    records = build_detail_records(df)

    # Per-depto/prov/dist stats for paragraphs
    geo_stats = {}
    for dep in deptos:
        dd = df[df["departamento"] == dep]
        dep_stats = stats_from_df(dd)
        dep_stats["tipos"] = {t: int((dd["tipo_intervencion_gral"]==t).sum()) for t in TIPOS if (dd["tipo_intervencion_gral"]==t).sum()>0}
        dep_stats["ents"] = {e: int((dd["entidad"]==e).sum()) for e in dd["entidad"].unique() if e}
        provs_data = {}
        for prov in sorted([p for p in dd["provincia"].unique() if p]):
            dp = dd[dd["provincia"] == prov]
            p_stats = stats_from_df(dp)
            p_stats["tipos"] = {t: int((dp["tipo_intervencion_gral"]==t).sum()) for t in TIPOS if (dp["tipo_intervencion_gral"]==t).sum()>0}
            p_stats["ents"] = {e: int((dp["entidad"]==e).sum()) for e in dp["entidad"].unique() if e}
            dists_data = {}
            for dist in sorted([d for d in dp["distrito"].unique() if d]):
                dd2 = dp[dp["distrito"] == dist]
                d_stats = stats_from_df(dd2)
                d_stats["tipos"] = {t: int((dd2["tipo_intervencion_gral"]==t).sum()) for t in TIPOS if (dd2["tipo_intervencion_gral"]==t).sum()>0}
                d_stats["ents"] = {e: int((dd2["entidad"]==e).sum()) for e in dd2["entidad"].unique() if e}
                dists_data[dist] = d_stats
            p_stats["dists"] = dists_data
            provs_data[prov] = p_stats
        dep_stats["provs"] = provs_data
        geo_stats[dep] = dep_stats

    # Matrix HTML rows
    matrix_rows = ""
    for r in matrix:
        matrix_rows += "<tr>"
        matrix_rows += f'<td class="link" onclick="selectDepto(\'{r["dep"]}\')">{r["dep"]}</td>'
        matrix_rows += f'<td class="n">{r["n"]:,}</td>'
        matrix_rows += f'<td class="n">{r["n_cui"]:,}</td>'
        for t in TIPOS:
            v = r[t]
            c = "n has" if v > 0 else "n z"
            matrix_rows += f'<td class="{c}">{v}</td>'
        matrix_rows += "</tr>\n"

    th_tipos = "".join(f"<th>{t[:10]}</th>" for t in TIPOS)

    html = f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Visor de Intervenciones - MINEDU</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:'Segoe UI',system-ui,sans-serif;background:#f0f2f5;color:#2d3436}}
.hd{{background:linear-gradient(135deg,#0c2461,#1e3799);color:#fff;padding:24px 32px}}
.hd h1{{font-size:1.3em;font-weight:600}}
.hd p{{opacity:.75;font-size:.82em;margin-top:4px}}
.wrap{{max-width:1440px;margin:0 auto;padding:16px}}
.kpis{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px;margin:14px 0}}
.kpi{{background:#fff;border-radius:10px;padding:16px;box-shadow:0 2px 8px rgba(0,0,0,.06)}}
.kpi .lb{{font-size:.7em;color:#636e72;text-transform:uppercase;letter-spacing:.5px}}
.kpi .vl{{font-size:1.5em;font-weight:700;color:#0c2461;margin-top:2px}}
.cd{{background:#fff;border-radius:10px;padding:20px;margin:12px 0;box-shadow:0 2px 8px rgba(0,0,0,.06)}}
.cd h2{{font-size:.95em;color:#0c2461;margin-bottom:10px;padding-bottom:6px;border-bottom:2px solid #dfe6e9}}
.pr{{line-height:1.8;font-size:.88em;background:#f8f9fa;padding:14px 16px;border-left:4px solid #3742fa;border-radius:6px;margin:8px 0}}
.pr b{{color:#0c2461}}
.fl{{display:flex;gap:10px;flex-wrap:wrap;margin:10px 0}}
.fl select{{padding:7px 10px;border:1px solid #b2bec3;border-radius:6px;font-size:.84em;min-width:180px}}
.fl label{{font-size:.72em;font-weight:600;color:#636e72;display:block;margin-bottom:2px}}
table{{width:100%;border-collapse:collapse;font-size:.76em}}
th{{background:#0c2461;color:#fff;padding:7px 5px;text-align:center;position:sticky;top:0;z-index:2}}
td{{padding:5px;border-bottom:1px solid #ecf0f1}}
td.n{{text-align:right}}
td.has{{background:#e8f5e9;font-weight:600}}
td.z{{color:#ccc}}
td.link{{color:#1e3799;cursor:pointer;text-decoration:underline;font-weight:600}}
tr:hover td{{background:#f0f3ff}}
.scroll{{max-height:420px;overflow-y:auto;border:1px solid #dfe6e9;border-radius:6px}}
.dt-scroll{{max-height:500px;overflow-y:auto;border:1px solid #dfe6e9;border-radius:6px;margin-top:10px}}
.btn{{padding:7px 16px;background:#3742fa;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:.8em}}
.btn:hover{{background:#0c2461}}
.badge{{display:inline-block;padding:2px 8px;border-radius:10px;font-size:.72em;font-weight:600}}
.badge-p{{background:#e8f5e9;color:#27ae60}}.badge-m{{background:#fff3e0;color:#e67e22}}
.badge-a{{background:#e3f2fd;color:#2980b9}}.badge-o{{background:#f3e5f5;color:#8e44ad}}
#detail-section{{display:none}}
.nota{{font-size:.75em;color:#636e72;margin-top:6px;font-style:italic}}
</style>
</head>
<body>
<div class="hd">
  <h1>Reporte de Intervenciones en Infraestructura Educativa</h1>
  <p>MINEDU &mdash; Intervenciones unicas (deduplicadas por CUI)</p>
</div>
<div class="wrap">

<div class="kpis">
  <div class="kpi"><div class="lb">Intervenciones unicas</div><div class="vl">{nat['n']:,}</div></div>
  <div class="kpi"><div class="lb">CUI unicos</div><div class="vl">{nat['n_cui']:,}</div></div>
  <div class="kpi"><div class="lb">Inversion total</div><div class="vl">{fmt_money(nat['monto'])}</div></div>
  <div class="kpi"><div class="lb">Devengado</div><div class="vl">{fmt_money(nat['dev'])}</div></div>
  <div class="kpi"><div class="lb">Avance fisico prom.</div><div class="vl">{fmt_pct(nat['avf'])}</div></div>
</div>

<div class="cd">
  <h2>Matriz de intervenciones por departamento y tipologia</h2>
  <p class="nota">Haga click en el departamento para ver detalle con parrafo y tabla de intervenciones.</p>
  <div class="scroll">
  <table>
    <thead><tr><th>Departamento</th><th>Total</th><th>CUI</th>{th_tipos}</tr></thead>
    <tbody>{matrix_rows}</tbody>
  </table>
  </div>
</div>

<div class="cd" id="detail-section">
  <button class="btn" onclick="goBack()" style="margin-bottom:12px">&#8592; Volver al resumen nacional</button>
  <h2 id="detail-title">Detalle</h2>

  <div class="fl">
    <div><label>Departamento</label><select id="s-dep" onchange="onDep()"><option value="">-- Seleccione --</option>
      {"".join(f'<option value="{d}">{d}</option>' for d in deptos)}
    </select></div>
    <div><label>Provincia</label><select id="s-prov" onchange="onProv()"><option value="">-- Todas --</option></select></div>
    <div><label>Distrito</label><select id="s-dist" onchange="onDist()"><option value="">-- Todos --</option></select></div>
  </div>

  <div class="pr" id="detail-parrafo"></div>

  <h2 style="margin-top:16px" id="table-title">Intervenciones</h2>
  <div class="dt-scroll">
  <table id="detail-table">
    <thead><tr>
      <th>#</th><th>CUI</th><th>Cod.Local</th><th>Nombre</th><th>Tipo</th>
      <th>Entidad</th><th>Estado</th><th>Monto (S/)</th><th>Avance</th>
    </tr></thead>
    <tbody id="detail-tbody"></tbody>
  </table>
  </div>
  <p class="nota" id="detail-count"></p>
</div>

</div>

<script>
const GEO = {json.dumps(geo_stats, ensure_ascii=False)};
const DATA = {json.dumps(records, ensure_ascii=False)};

function fmtM(v) {{ return v > 0 ? 'S/ ' + (v/1e6).toLocaleString('es-PE',{{minimumFractionDigits:2,maximumFractionDigits:2}}) + ' M' : '-'; }}
function fmtP(v) {{ return v > 0 ? (v*100).toFixed(1) + '%' : '-'; }}

function buildParrafo(st, nombre) {{
  let tipos = Object.entries(st.tipos||{{}}).map(([k,v])=>k+' ('+v+')').join(', ');
  let ents = Object.entries(st.ents||{{}}).sort((a,b)=>b[1]-a[1]).map(([k,v])=>k+' ('+v+')').join(', ');
  return `En <b>${{nombre}}</b> se identifican <b>${{st.n.toLocaleString()}}</b> intervenciones unicas `+
    `asociadas a <b>${{st.n_cui.toLocaleString()}}</b> CUI. `+
    `Por tipo: ${{tipos}}. Por entidad: ${{ents}}. `+
    `Monto de inversion: <b>${{fmtM(st.monto)}}</b>, devengado: <b>${{fmtM(st.dev)}}</b>, `+
    `avance fisico promedio: <b>${{fmtP(st.avf)}}</b>.`;
}}

function filterData(dep, prov, dist) {{
  return DATA.filter(r => {{
    if (dep && r.departamento !== dep) return false;
    if (prov && r.provincia !== prov) return false;
    if (dist && r.distrito !== dist) return false;
    return true;
  }});
}}

function renderTable(rows) {{
  const tb = document.getElementById('detail-tbody');
  tb.innerHTML = '';
  rows.forEach((r, i) => {{
    const tipo = r.tipo_intervencion_gral || '';
    let bc = 'badge-o';
    if (tipo.includes('PROYECTO')) bc='badge-p';
    else if (tipo.includes('MANT')) bc='badge-m';
    else if (tipo.includes('ACOND')||tipo.includes('ACCES')) bc='badge-a';
    const m = r.monto_inversion > 0 ? r.monto_inversion.toLocaleString('es-PE',{{maximumFractionDigits:0}}) : '-';
    const av = r.avance_fisico > 0 ? (r.avance_fisico*100).toFixed(1)+'%' : '-';
    const nom = (r.nombre_inversion||'').substring(0,60) + ((r.nombre_inversion||'').length>60?'...':'');
    tb.innerHTML += `<tr>
      <td class="n">${{i+1}}</td>
      <td>${{r.cui}}</td><td>${{r.codigo_local}}</td>
      <td>${{nom}}</td>
      <td><span class="badge ${{bc}}">${{tipo}}</span></td>
      <td>${{r.entidad}}</td><td>${{r.estado}}</td>
      <td class="n">${{m}}</td><td class="n">${{av}}</td>
    </tr>`;
  }});
  document.getElementById('detail-count').textContent =
    rows.length + ' intervenciones unicas mostradas';
}}

function selectDepto(d) {{
  document.getElementById('s-dep').value = d;
  onDep();
  document.getElementById('detail-section').style.display = 'block';
  document.getElementById('detail-section').scrollIntoView({{behavior:'smooth'}});
}}

function onDep() {{
  const d = document.getElementById('s-dep').value;
  document.getElementById('detail-section').style.display = d ? 'block' : 'none';
  if (!d) return;
  const st = GEO[d]; if (!st) return;
  document.getElementById('detail-title').textContent = d;
  document.getElementById('detail-parrafo').innerHTML = buildParrafo(st, d);
  document.getElementById('table-title').textContent = 'Intervenciones en ' + d;
  const sp = document.getElementById('s-prov');
  sp.innerHTML = '<option value="">-- Todas --</option>';
  Object.keys(st.provs||{{}}).sort().forEach(p => sp.innerHTML += `<option value="${{p}}">${{p}}</option>`);
  document.getElementById('s-dist').innerHTML = '<option value="">-- Todos --</option>';
  renderTable(filterData(d,'',''));
}}

function onProv() {{
  const d = document.getElementById('s-dep').value;
  const p = document.getElementById('s-prov').value;
  if (!p) {{ onDep(); return; }}
  const st = GEO[d]?.provs?.[p]; if (!st) return;
  const label = p + ', ' + d;
  document.getElementById('detail-title').textContent = label;
  document.getElementById('detail-parrafo').innerHTML = buildParrafo(st, label);
  document.getElementById('table-title').textContent = 'Intervenciones en ' + label;
  const sd = document.getElementById('s-dist');
  sd.innerHTML = '<option value="">-- Todos --</option>';
  Object.keys(st.dists||{{}}).sort().forEach(di => sd.innerHTML += `<option value="${{di}}">${{di}}</option>`);
  renderTable(filterData(d,p,''));
}}

function onDist() {{
  const d = document.getElementById('s-dep').value;
  const p = document.getElementById('s-prov').value;
  const di = document.getElementById('s-dist').value;
  if (!di) {{ onProv(); return; }}
  const st = GEO[d]?.provs?.[p]?.dists?.[di]; if (!st) return;
  const label = di + ', ' + p + ', ' + d;
  document.getElementById('detail-title').textContent = label;
  document.getElementById('detail-parrafo').innerHTML = buildParrafo(st, label);
  document.getElementById('table-title').textContent = 'Intervenciones en ' + label;
  renderTable(filterData(d,p,di));
}}

function goBack() {{
  document.getElementById('detail-section').style.display = 'none';
  document.getElementById('s-dep').value = '';
  window.scrollTo({{top:0,behavior:'smooth'}});
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
            return 1

    print(f"Leyendo {csv_path}...")
    df = load(csv_path)
    print(f"  {len(df):,} filas crudas")

    print("Deduplicando intervenciones...")
    df = dedup(df)
    print(f"  {len(df):,} intervenciones unicas")

    print("Generando HTML...")
    html = build_html(df)

    out = Path(csv_path).parent / "visor_intervenciones.html"
    out.write_text(html, encoding="utf-8")
    print(f"Visor generado: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
