"""
generar_visor.py  v3
-------------------
Visor estilo DRIE/DIPLAN MINEDU: dashboard con iconos, graficos de barras
horizontales, donuts, filtros laterales, parrafos automaticos y tabla de detalle.

Uso:
    python3 generar_visor.py <ruta_a_BASE_PANORAMA.csv>
"""

import sys, os, json
from pathlib import Path
import pandas as pd
import numpy as np


def load(path):
    df = pd.read_csv(path, dtype=str, low_memory=False)
    for c in ["monto_inversion","devengado","avance_fisico","avance_financiero",
              "monto_asignado_total","monto_transferido","matricula"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    for c in df.columns:
        if df[c].dtype == object:
            df[c] = df[c].fillna("").str.strip()
    return df


def dedup(df):
    has_cui = df[df["cui"] != ""].copy()
    no_cui = df[df["cui"] == ""].copy()
    if not has_cui.empty:
        has_cui["_c"] = has_cui.notna().sum(axis=1)
        has_cui = has_cui.sort_values("_c", ascending=False).drop_duplicates(subset="cui", keep="first").drop(columns=["_c"])
    if not no_cui.empty:
        key = [k for k in ["codigo_local","tipo_intervencion_gral","unidad"] if k in no_cui.columns]
        if key:
            no_cui = no_cui.drop_duplicates(subset=key, keep="first")
    return pd.concat([has_cui, no_cui], ignore_index=True)


TIPOS = ["PROYECTO","MANTENIMIENTO","ACONDICIONAMIENTO","ACCESIBILIDAD",
         "MODULOS","MOBILIARIO/EQUIPAMIENTO","ASISTENCIA TECNICA",
         "INSPECCION","ASESORAMIENTO"]

TIPO_COLORS = {
    "PROYECTO": "#2ecc71", "MANTENIMIENTO": "#e67e22", "ACONDICIONAMIENTO": "#3498db",
    "ACCESIBILIDAD": "#9b59b6", "MODULOS": "#1abc9c", "MOBILIARIO/EQUIPAMIENTO": "#34495e",
    "ASISTENCIA TECNICA": "#e74c3c", "INSPECCION": "#f39c12", "ASESORAMIENTO": "#16a085"
}

ENTIDADES = ["PRONIED","PEIP","UE118","ANIN","FONCODES"]
ENT_COLORS = {"PRONIED":"#2c3e50","PEIP":"#2980b9","UE118":"#8e44ad","ANIN":"#c0392b","FONCODES":"#27ae60"}


def build_records(df):
    recs = []
    for _, row in df.iterrows():
        r = {}
        for k in ["cui","codigo_local","nombre_inversion","tipo_intervencion_gral",
                   "entidad","unidad","estado","departamento","provincia","distrito"]:
            r[k] = str(row.get(k,"")) if pd.notna(row.get(k,"")) else ""
        r["monto"] = round(float(row["monto_inversion"]),0) if pd.notna(row.get("monto_inversion")) else 0
        r["avance"] = round(float(row["avance_fisico"]),4) if pd.notna(row.get("avance_fisico")) else 0
        recs.append(r)
    return recs


def compute_stats(df):
    n = len(df)
    cuis = df.loc[df["cui"]!="","cui"] if "cui" in df.columns else pd.Series()
    n_cui = int(cuis.nunique())
    df_u = df[df["cui"]!=""].drop_duplicates(subset="cui",keep="first") if "cui" in df.columns else df
    monto = float(df_u["monto_inversion"].sum()) if "monto_inversion" in df.columns else 0
    dev = float(df_u["devengado"].sum()) if "devengado" in df.columns else 0
    avf = float(df["avance_fisico"].mean()) if "avance_fisico" in df.columns and df["avance_fisico"].notna().any() else 0
    tipos = {}
    for t in TIPOS:
        c = int((df["tipo_intervencion_gral"]==t).sum())
        if c > 0: tipos[t] = c
    ents = {}
    for e in ENTIDADES:
        c = int((df["entidad"]==e).sum())
        if c > 0: ents[e] = c
    return {"n":n,"n_cui":n_cui,"monto":round(monto,2),"dev":round(dev,2),
            "avf":round(avf,4),"tipos":tipos,"ents":ents}


def geo_tree(df):
    deptos = sorted([d for d in df["departamento"].unique() if d])
    tree = {}
    for dep in deptos:
        dd = df[df["departamento"]==dep]
        ds = compute_stats(dd)
        ds["provs"] = {}
        for prov in sorted([p for p in dd["provincia"].unique() if p]):
            dp = dd[dd["provincia"]==prov]
            ps = compute_stats(dp)
            ps["dists"] = {}
            for dist in sorted([d for d in dp["distrito"].unique() if d]):
                dd2 = dp[dp["distrito"]==dist]
                ps["dists"][dist] = compute_stats(dd2)
            ds["provs"][prov] = ps
        tree[dep] = ds
    return tree


def main():
    csv_path = sys.argv[1] if len(sys.argv)>1 else next(
        (p for p in ["dta/BASE_PANORAMA.csv","BASE_PANORAMA.csv"] if os.path.exists(p)), None)
    if not csv_path:
        print("No se encontro BASE_PANORAMA.csv"); return 1

    print(f"Leyendo {csv_path}...")
    df = load(csv_path)
    print(f"  {len(df):,} filas crudas")
    df = dedup(df)
    print(f"  {len(df):,} intervenciones unicas")

    nat = compute_stats(df)
    tree = geo_tree(df)
    records = build_records(df)
    deptos = sorted(tree.keys())

    tipo_colors_json = json.dumps(TIPO_COLORS, ensure_ascii=False)
    ent_colors_json = json.dumps(ENT_COLORS, ensure_ascii=False)
    tree_json = json.dumps(tree, ensure_ascii=False)
    records_json = json.dumps(records, ensure_ascii=False)
    nat_json = json.dumps(nat, ensure_ascii=False)
    depto_opts = "".join(f'<option value="{d}">{d}</option>' for d in deptos)

    # Build the bars for tipos (national)
    max_tipo = max(nat["tipos"].values()) if nat["tipos"] else 1

    html = f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Intervenciones en Infraestructura Educativa - MINEDU</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:'Segoe UI',system-ui,sans-serif;background:#e8eaed;color:#2d3436;font-size:14px}}

/* Header MINEDU style */
.topbar{{background:#fff;padding:8px 24px;display:flex;align-items:center;gap:16px;border-bottom:3px solid #c0392b}}
.topbar .logo{{display:flex;align-items:center;gap:8px}}
.topbar .logo-peru{{background:#c0392b;color:#fff;font-weight:800;padding:4px 12px;border-radius:4px;font-size:13px}}
.topbar .ministerio{{font-size:12px;color:#555;line-height:1.3}}
.topbar .ministerio b{{color:#333;font-size:13px}}

.banner{{background:linear-gradient(135deg,#1a2a4a,#2c3e6b);text-align:center;padding:18px;color:#fff}}
.banner h1{{font-size:1.25em;font-weight:600;letter-spacing:.5px}}
.banner p{{font-size:.78em;opacity:.7;margin-top:4px}}

/* Layout */
.main{{display:grid;grid-template-columns:240px 1fr 280px;gap:0;max-width:1500px;margin:0 auto;min-height:calc(100vh - 120px)}}
@media(max-width:1100px){{.main{{grid-template-columns:1fr;}} .sidebar,.rightpanel{{display:none}} }}

/* Sidebar filters */
.sidebar{{background:#fff;padding:16px;border-right:1px solid #ddd}}
.sidebar h3{{font-size:.8em;color:#555;margin:12px 0 4px;text-transform:uppercase;letter-spacing:.5px}}
.sidebar select{{width:100%;padding:7px 8px;border:1px solid #bbb;border-radius:4px;font-size:.82em;margin-bottom:2px;background:#fff}}
.sidebar .filter-label{{background:#1a2a4a;color:#fff;padding:4px 8px;border-radius:3px;font-size:.72em;font-weight:600;margin-bottom:3px;display:block}}
.btn-clear{{width:100%;padding:10px;background:#c0392b;color:#fff;border:none;border-radius:6px;font-size:.85em;font-weight:700;cursor:pointer;margin-top:16px;text-transform:uppercase}}
.btn-clear:hover{{background:#a93226}}

/* Center content */
.content{{padding:16px;background:#f4f5f7;overflow-y:auto}}

/* KPI cards */
.kpis{{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:16px}}
.kpi{{background:#fff;border-radius:8px;padding:14px;text-align:center;box-shadow:0 1px 4px rgba(0,0,0,.08)}}
.kpi .icon{{font-size:1.8em;margin-bottom:4px}}
.kpi .val{{font-size:1.5em;font-weight:800;color:#1a2a4a}}
.kpi .lbl{{font-size:.7em;color:#777;text-transform:uppercase;letter-spacing:.3px}}

/* Section cards */
.card{{background:#fff;border-radius:8px;padding:16px;margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,.08)}}
.card h2{{font-size:.88em;color:#fff;background:#1a2a4a;padding:8px 14px;border-radius:5px;margin:-16px -16px 14px;text-align:center;letter-spacing:.3px}}

/* Horizontal bar chart */
.bar-row{{display:flex;align-items:center;margin:6px 0;font-size:.82em}}
.bar-label{{width:180px;text-align:right;padding-right:10px;color:#444;font-weight:500}}
.bar-track{{flex:1;background:#ecf0f1;border-radius:4px;height:22px;position:relative;overflow:hidden}}
.bar-fill{{height:100%;border-radius:4px;display:flex;align-items:center;justify-content:flex-end;padding-right:6px;color:#fff;font-weight:700;font-size:.78em;min-width:30px;transition:width .4s}}
.bar-count{{margin-left:8px;font-weight:700;color:#333;min-width:50px}}

/* Donut */
.donut-section{{text-align:center}}
.donut-title{{font-size:.82em;font-weight:600;color:#444;margin-bottom:8px}}
.donut-container{{display:inline-block;position:relative;width:160px;height:160px}}
.donut-container canvas{{width:160px;height:160px}}
.donut-center{{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center}}
.donut-center .big{{font-size:1.4em;font-weight:800;color:#1a2a4a}}
.donut-center .sm{{font-size:.65em;color:#888}}
.legend{{display:flex;flex-wrap:wrap;justify-content:center;gap:6px;margin-top:8px}}
.legend-item{{display:flex;align-items:center;gap:4px;font-size:.72em}}
.legend-dot{{width:10px;height:10px;border-radius:50%}}

/* Right panel */
.rightpanel{{background:#fff;padding:16px;border-left:1px solid #ddd;overflow-y:auto}}
.rightpanel h3{{font-size:.85em;color:#1a2a4a;margin-bottom:10px;padding-bottom:6px;border-bottom:2px solid #e8eaed}}

/* Paragraph */
.parrafo{{line-height:1.75;font-size:.84em;background:#f8f9fa;padding:14px;border-left:4px solid #2c3e6b;border-radius:4px;margin:10px 0}}
.parrafo b{{color:#1a2a4a}}

/* Detail table */
.dt-wrap{{max-height:400px;overflow-y:auto;border:1px solid #ddd;border-radius:6px;margin-top:10px}}
table{{width:100%;border-collapse:collapse;font-size:.75em}}
th{{background:#1a2a4a;color:#fff;padding:6px 5px;text-align:center;position:sticky;top:0;z-index:2}}
td{{padding:5px;border-bottom:1px solid #ecf0f1;white-space:nowrap}}
td.r{{text-align:right}}
tr:nth-child(even){{background:#fafbfc}}
tr:hover td{{background:#edf2fa}}
.badge{{display:inline-block;padding:2px 7px;border-radius:10px;font-size:.72em;font-weight:600;color:#fff}}
.nota{{font-size:.72em;color:#888;margin-top:6px;font-style:italic}}

/* Footer */
.footer{{background:#1a2a4a;color:rgba(255,255,255,.6);text-align:center;padding:10px;font-size:.7em}}
</style>
</head>
<body>

<!-- Top bar MINEDU -->
<div class="topbar">
  <div class="logo">
    <span class="logo-peru">PERU</span>
    <div class="ministerio"><b>Ministerio</b><br>de Educacion</div>
  </div>
</div>

<!-- Banner -->
<div class="banner">
  <h1>Intervenciones en Infraestructura Educativa</h1>
  <p>Reporte consolidado de intervenciones por entidad y tipologia &mdash; Intervenciones unicas (deduplicadas por CUI)</p>
</div>

<!-- Main 3-column layout -->
<div class="main">

  <!-- LEFT: Filters -->
  <div class="sidebar">
    <h3>Organizacion territorial</h3>
    <span class="filter-label">Region</span>
    <select id="s-dep" onchange="onFilter()"><option value="">Todas</option>{depto_opts}</select>
    <span class="filter-label">Provincia</span>
    <select id="s-prov" onchange="onFilter()"><option value="">Todas</option></select>
    <span class="filter-label">Distrito</span>
    <select id="s-dist" onchange="onFilter()"><option value="">Todas</option></select>

    <h3>Tipo de intervencion</h3>
    <select id="s-tipo" onchange="onFilter()"><option value="">Todas</option>
      {"".join(f'<option value="{t}">{t}</option>' for t in TIPOS)}
    </select>

    <h3>Entidad</h3>
    <select id="s-ent" onchange="onFilter()"><option value="">Todas</option>
      {"".join(f'<option value="{e}">{e}</option>' for e in ENTIDADES)}
    </select>

    <button class="btn-clear" onclick="clearFilters()">BORRAR FILTROS</button>
  </div>

  <!-- CENTER: Dashboard -->
  <div class="content">
    <!-- KPIs -->
    <div class="kpis">
      <div class="kpi"><div class="icon">🏫</div><div class="val" id="kpi-n">-</div><div class="lbl">Intervenciones unicas</div></div>
      <div class="kpi"><div class="icon">📋</div><div class="val" id="kpi-cui">-</div><div class="lbl">CUI unicos</div></div>
      <div class="kpi"><div class="icon">💰</div><div class="val" id="kpi-monto">-</div><div class="lbl">Inversion total (S/)</div></div>
    </div>

    <!-- Horizontal bars: tipos -->
    <div class="card">
      <h2>Intervenciones por tipo</h2>
      <div id="bars-tipos"></div>
    </div>

    <!-- Paragraph -->
    <div class="card">
      <h2 id="parrafo-title">Resumen Nacional</h2>
      <div class="parrafo" id="parrafo-text"></div>
    </div>

    <!-- Detail table -->
    <div class="card">
      <h2>Detalle de intervenciones</h2>
      <div class="dt-wrap">
        <table>
          <thead><tr><th>#</th><th>CUI</th><th>Cod.Local</th><th>Nombre de la intervencion</th><th>Tipo</th><th>Entidad</th><th>Estado</th><th>Monto (S/)</th><th>Avance</th></tr></thead>
          <tbody id="dtbody"></tbody>
        </table>
      </div>
      <p class="nota" id="dt-count"></p>
    </div>
  </div>

  <!-- RIGHT: Donut charts -->
  <div class="rightpanel">
    <h3>Distribucion por entidad</h3>
    <div class="donut-section">
      <div class="donut-container"><canvas id="donut-ent" width="160" height="160"></canvas>
        <div class="donut-center"><div class="big" id="donut-ent-n">-</div><div class="sm">intervenciones</div></div>
      </div>
      <div class="legend" id="legend-ent"></div>
    </div>

    <h3 style="margin-top:20px">Distribucion por tipo</h3>
    <div class="donut-section">
      <div class="donut-container"><canvas id="donut-tipo" width="160" height="160"></canvas>
        <div class="donut-center"><div class="big" id="donut-tipo-n">-</div><div class="sm">intervenciones</div></div>
      </div>
      <div class="legend" id="legend-tipo"></div>
    </div>
  </div>

</div>

<div class="footer">Elaborado por DIPLAN-DIGEIE &mdash; Generado automaticamente desde BASE_PANORAMA</div>

<script>
const DATA = {records_json};
const GEO = {tree_json};
const NAT = {nat_json};
const TC = {tipo_colors_json};
const EC = {ent_colors_json};
const TIPOS = {json.dumps(TIPOS)};
const ENTS = {json.dumps(ENTIDADES)};

function fmtM(v){{if(!v)return'-';if(v>=1e6)return'S/ '+(v/1e6).toFixed(2)+' mill.';return'S/ '+v.toLocaleString('es-PE',{{maximumFractionDigits:0}});}}
function fmtP(v){{return v>0?(v*100).toFixed(1)+'%':'-';}}

function getFiltered(){{
  const d=document.getElementById('s-dep').value;
  const p=document.getElementById('s-prov').value;
  const di=document.getElementById('s-dist').value;
  const t=document.getElementById('s-tipo').value;
  const e=document.getElementById('s-ent').value;
  return DATA.filter(r=>{{
    if(d&&r.departamento!==d)return false;
    if(p&&r.provincia!==p)return false;
    if(di&&r.distrito!==di)return false;
    if(t&&r.tipo_intervencion_gral!==t)return false;
    if(e&&r.entidad!==e)return false;
    return true;
  }});
}}

function computeStats(rows){{
  const n=rows.length;
  const cuiSet=new Set(rows.filter(r=>r.cui).map(r=>r.cui));
  const n_cui=cuiSet.size;
  const seen=new Set();let monto=0;
  rows.forEach(r=>{{if(r.cui&&!seen.has(r.cui)){{seen.add(r.cui);monto+=r.monto||0;}}}});
  const tipos={{}};TIPOS.forEach(t=>{{const c=rows.filter(r=>r.tipo_intervencion_gral===t).length;if(c)tipos[t]=c;}});
  const ents={{}};ENTS.forEach(e=>{{const c=rows.filter(r=>r.entidad===e).length;if(c)ents[e]=c;}});
  return {{n,n_cui,monto,tipos,ents}};
}}

function buildParrafo(st,nombre){{
  const tp=Object.entries(st.tipos).sort((a,b)=>b[1]-a[1]).map(([k,v])=>k+' ('+v.toLocaleString()+')').join(', ');
  const en=Object.entries(st.ents).sort((a,b)=>b[1]-a[1]).map(([k,v])=>k+' ('+v.toLocaleString()+')').join(', ');
  return `En <b>${{nombre}}</b> se identifican <b>${{st.n.toLocaleString()}}</b> intervenciones unicas asociadas a <b>${{st.n_cui.toLocaleString()}}</b> CUI. Por tipo de intervencion: ${{tp}}. Por entidad: ${{en}}. El monto total de inversion asciende a <b>${{fmtM(st.monto)}}</b>.`;
}}

function renderBars(tipos){{
  const el=document.getElementById('bars-tipos');
  const max=Math.max(...Object.values(tipos),1);
  let h='';
  TIPOS.forEach(t=>{{
    const v=tipos[t]||0;
    const pct=Math.max(v/max*100,0);
    const col=TC[t]||'#95a5a6';
    h+=`<div class="bar-row"><div class="bar-label">${{t}}</div><div class="bar-track"><div class="bar-fill" style="width:${{pct}}%;background:${{col}}">${{v>0?v:''}}</div></div><div class="bar-count">${{v.toLocaleString()}}</div></div>`;
  }});
  el.innerHTML=h;
}}

function drawDonut(canvasId,data,colors,centerId,legendId){{
  const canvas=document.getElementById(canvasId);
  const ctx=canvas.getContext('2d');
  const total=Object.values(data).reduce((a,b)=>a+b,0);
  document.getElementById(centerId).textContent=total.toLocaleString();
  ctx.clearRect(0,0,160,160);
  const cx=80,cy=80,r=65,ir=42;
  let angle=-Math.PI/2;
  const entries=Object.entries(data).sort((a,b)=>b[1]-a[1]);
  entries.forEach(([k,v])=>{{
    const slice=total>0?(v/total)*Math.PI*2:0;
    ctx.beginPath();ctx.moveTo(cx,cy);ctx.arc(cx,cy,r,angle,angle+slice);ctx.closePath();
    ctx.fillStyle=colors[k]||'#bdc3c7';ctx.fill();angle+=slice;
  }});
  ctx.beginPath();ctx.arc(cx,cy,ir,0,Math.PI*2);ctx.fillStyle='#fff';ctx.fill();
  const leg=document.getElementById(legendId);
  leg.innerHTML=entries.map(([k,v])=>`<div class="legend-item"><div class="legend-dot" style="background:${{colors[k]||'#bdc3c7'}}"></div>${{k}} (${{v}})</div>`).join('');
}}

function renderTable(rows){{
  const tb=document.getElementById('dtbody');
  const show=rows.slice(0,500);
  let h='';
  show.forEach((r,i)=>{{
    const col=TC[r.tipo_intervencion_gral]||'#95a5a6';
    const nom=(r.nombre_inversion||'').substring(0,55)+((r.nombre_inversion||'').length>55?'...':'');
    const m=r.monto>0?r.monto.toLocaleString('es-PE',{{maximumFractionDigits:0}}):'-';
    const av=r.avance>0?(r.avance*100).toFixed(1)+'%':'-';
    h+=`<tr><td class="r">${{i+1}}</td><td>${{r.cui}}</td><td>${{r.codigo_local}}</td><td>${{nom}}</td><td><span class="badge" style="background:${{col}}">${{r.tipo_intervencion_gral}}</span></td><td>${{r.entidad}}</td><td>${{r.estado}}</td><td class="r">${{m}}</td><td class="r">${{av}}</td></tr>`;
  }});
  tb.innerHTML=h;
  document.getElementById('dt-count').textContent=rows.length>500?`Mostrando 500 de ${{rows.length.toLocaleString()}} intervenciones`:`${{rows.length.toLocaleString()}} intervenciones`;
}}

function getLabel(){{
  const d=document.getElementById('s-dep').value;
  const p=document.getElementById('s-prov').value;
  const di=document.getElementById('s-dist').value;
  if(di)return di+', '+p+', '+d;
  if(p)return p+', '+d;
  if(d)return d;
  return 'Nacional';
}}

function onFilter(){{
  const d=document.getElementById('s-dep').value;
  const p=document.getElementById('s-prov').value;

  // Cascade provincia
  if(d&&GEO[d]){{
    const sp=document.getElementById('s-prov');
    const cur=sp.value;
    sp.innerHTML='<option value="">Todas</option>';
    Object.keys(GEO[d].provs).sort().forEach(pr=>sp.innerHTML+=`<option value="${{pr}}">${{pr}}</option>`);
    sp.value=cur;
  }}
  // Cascade distrito
  if(d&&p&&GEO[d]?.provs?.[p]){{
    const sd=document.getElementById('s-dist');
    const cur=sd.value;
    sd.innerHTML='<option value="">Todas</option>';
    Object.keys(GEO[d].provs[p].dists).sort().forEach(di=>sd.innerHTML+=`<option value="${{di}}">${{di}}</option>`);
    sd.value=cur;
  }}

  const rows=getFiltered();
  const st=computeStats(rows);
  const label=getLabel();

  document.getElementById('kpi-n').textContent=st.n.toLocaleString();
  document.getElementById('kpi-cui').textContent=st.n_cui.toLocaleString();
  document.getElementById('kpi-monto').textContent=fmtM(st.monto);
  document.getElementById('parrafo-title').textContent='Resumen: '+label;
  document.getElementById('parrafo-text').innerHTML=buildParrafo(st,label);
  renderBars(st.tipos);
  drawDonut('donut-ent',st.ents,EC,'donut-ent-n','legend-ent');
  drawDonut('donut-tipo',st.tipos,TC,'donut-tipo-n','legend-tipo');
  renderTable(rows);
}}

function clearFilters(){{
  ['s-dep','s-prov','s-dist','s-tipo','s-ent'].forEach(id=>document.getElementById(id).value='');
  document.getElementById('s-prov').innerHTML='<option value="">Todas</option>';
  document.getElementById('s-dist').innerHTML='<option value="">Todas</option>';
  onFilter();
}}

onFilter();
</script>
</body>
</html>"""

    out = Path(csv_path).parent / "visor_intervenciones.html"
    out.write_text(html, encoding="utf-8")
    print(f"Visor generado: {out}")
    print(f"  {len(records):,} intervenciones en el visor")
    return 0

if __name__ == "__main__":
    sys.exit(main())
