*! reporte_intervenciones.do
*! ============================================================================
*! Genera reporte de intervenciones desde BASE_PANORAMA.dta:
*!   - Tabla de tipologias por departamento (consola + HTML)
*!   - Parrafo automatico por nivel (nacional, depto, provincia, distrito)
*!   - Exporta visor_intervenciones.html (estatico, sin dependencias)
*!
*! Uso:
*!   do reporte_intervenciones.do                   // todo el pais
*!   do reporte_intervenciones.do LORETO            // un departamento
*!   do reporte_intervenciones.do LORETO MAYNAS     // depto + provincia
*! ============================================================================

version 15
args filtro_depto filtro_prov filtro_dist

if "$Output" == "" global Output "`c(pwd)'/dta"

capture use "${Output}/BASE_PANORAMA.dta", clear
if _rc {
    di as err "ERROR: no existe ${Output}/BASE_PANORAMA.dta"
    di as err "       corra primero: do limpieza_por_entidad.do"
    exit 198
}

* ===================================================================
* Programa: generar parrafo para un subconjunto
* ===================================================================
capture program drop _parrafo
program define _parrafo
    args nombre handle

    quietly count
    local n_total = r(N)
    if `n_total' == 0 {
        if "`handle'" != "" file write `handle' `"<p>Sin datos para `nombre'.</p>"' _n
        di as txt "Sin datos para `nombre'."
        exit 0
    }

    * CUI unicos
    tempvar cui_ok
    quietly gen `cui_ok' = (cui != "" & !missing(cui))
    quietly levelsof cui if `cui_ok', local(cuis_list) clean
    local n_cui : word count `cuis_list'

    * Monto y devengado SIN duplicar por CUI
    tempvar first_cui
    quietly bysort cui: gen `first_cui' = (_n == 1) if `cui_ok'
    quietly summarize monto_inversion if `first_cui' == 1, meanonly
    local monto = cond(missing(r(sum)), 0, r(sum))
    quietly summarize devengado if `first_cui' == 1, meanonly
    local dev = cond(missing(r(sum)), 0, r(sum))

    * Avance fisico promedio (sobre todos los registros)
    quietly summarize avance_fisico, meanonly
    local avf = cond(missing(r(mean)), 0, r(mean))

    * Conteo por tipo de intervencion
    local tipos_txt ""
    foreach t in PROYECTO MANTENIMIENTO ACONDICIONAMIENTO ACCESIBILIDAD ///
                 MODULOS "MOBILIARIO/EQUIPAMIENTO" "ASISTENCIA TECNICA" ///
                 INSPECCION ASESORAMIENTO {
        quietly count if tipo_intervencion_gral == "`t'"
        local nt = r(N)
        if `nt' > 0 {
            if "`tipos_txt'" == "" local tipos_txt "`t' (`nt')"
            else                   local tipos_txt "`tipos_txt', `t' (`nt')"
        }
    }

    * Conteo por entidad
    local ent_txt ""
    foreach e in PRONIED PEIP UE118 ANIN FONCODES {
        quietly count if entidad == "`e'"
        local ne = r(N)
        if `ne' > 0 {
            if "`ent_txt'" == "" local ent_txt "`e' (`ne')"
            else                 local ent_txt "`ent_txt', `e' (`ne')"
        }
    }

    local monto_mill : di %12.2fc `monto'/1000000
    local dev_mill   : di %12.2fc `dev'/1000000
    local avf_pct    : di %4.1f   `avf'*100

    * Consola
    di _newline(1)
    di as res "--- `nombre' ---"
    di as txt "Registros: " as res `n_total' as txt "  |  CUI unicos: " as res `n_cui'
    di as txt "Monto inversion (sin dup CUI): S/ " as res "`monto_mill' millones"
    di as txt "Devengado (sin dup CUI): S/ " as res "`dev_mill' millones"
    di as txt "Avance fisico promedio: " as res "`avf_pct' %"
    di as txt "Por tipo: `tipos_txt'"
    di as txt "Por entidad: `ent_txt'"

    * HTML
    if "`handle'" != "" {
        file write `handle' `"<div class="card"><h2>`nombre'</h2>"' _n
        file write `handle' `"<div class="parrafo">"' _n
        file write `handle' `"En <b>`nombre'</b> se identifican <b>`n_total'</b> registros "' _n
        file write `handle' `"asociados a <b>`n_cui'</b> CUI unicos (monto sin duplicar por CUI). "' _n
        file write `handle' `"Por tipo de intervencion: `tipos_txt'. "' _n
        file write `handle' `"Por entidad: `ent_txt'. "' _n
        file write `handle' `"El monto total de inversion asciende a <b>S/ `monto_mill' millones</b>"' _n
        file write `handle' `", con <b>S/ `dev_mill' millones</b> devengados"' _n
        file write `handle' `" y un avance fisico promedio de <b>`avf_pct' %</b>."' _n
        file write `handle' `"</div></div>"' _n
    }

    drop `cui_ok' `first_cui'
end


* ===================================================================
* Programa: tabla de tipologias por departamento
* ===================================================================
capture program drop _tabla_tipologias
program define _tabla_tipologias
    args handle

    di _newline(2) as res "===== MATRIZ DE TIPOLOGIAS POR DEPARTAMENTO ====="

    * Header consola
    di as txt _col(1)  %-15s "DEPARTAMENTO" ///
       _col(17) %7s "TOTAL" ///
       _col(25) %7s "CUI" ///
       _col(33) %6s "PROY" ///
       _col(40) %6s "MANT" ///
       _col(47) %6s "ACOND" ///
       _col(54) %6s "ACCES" ///
       _col(61) %6s "MODUL" ///
       _col(68) %6s "MOB" ///
       _col(75) %6s "ASIST" ///
       _col(82) %6s "INSP" ///
       _col(89) %6s "ASES"

    * HTML header
    if "`handle'" != "" {
        file write `handle' `"<div class="card"><h2>Matriz de tipologias por departamento</h2>"' _n
        file write `handle' `"<table><thead><tr>"' _n
        file write `handle' `"<th>Departamento</th><th>Total</th><th>CUI</th>"' _n
        file write `handle' `"<th>Proyecto</th><th>Mant.</th><th>Acond.</th><th>Accesib.</th>"' _n
        file write `handle' `"<th>Modulos</th><th>Mob/Eq.</th><th>Asist.Tec</th>"' _n
        file write `handle' `"<th>Inspecc.</th><th>Asesor.</th>"' _n
        file write `handle' `"</tr></thead><tbody>"' _n
    }

    quietly levelsof departamento if departamento != "", local(deptos)
    foreach d of local deptos {
        quietly count if departamento == "`d'"
        local nt = r(N)
        quietly levelsof cui if departamento == "`d'" & cui != "", local(cl) clean
        local nc : word count `cl'

        local vals ""
        foreach t in PROYECTO MANTENIMIENTO ACONDICIONAMIENTO ACCESIBILIDAD ///
                     MODULOS "MOBILIARIO/EQUIPAMIENTO" "ASISTENCIA TECNICA" ///
                     INSPECCION ASESORAMIENTO {
            quietly count if departamento == "`d'" & tipo_intervencion_gral == "`t'"
            local v = r(N)
            local vals "`vals' `v'"
        }

        tokenize `vals'
        di as txt _col(1)  %-15s "`d'" ///
           _col(17) %7.0f `nt' ///
           _col(25) %7.0f `nc' ///
           _col(33) %6.0f `1' ///
           _col(40) %6.0f `2' ///
           _col(47) %6.0f `3' ///
           _col(54) %6.0f `4' ///
           _col(61) %6.0f `5' ///
           _col(68) %6.0f `6' ///
           _col(75) %6.0f `7' ///
           _col(82) %6.0f `8' ///
           _col(89) %6.0f `9'

        if "`handle'" != "" {
            file write `handle' `"<tr>"' _n
            file write `handle' `"<td>`d'</td><td>`nt'</td><td>`nc'</td>"' _n
            forvalues i = 1/9 {
                local v = ``i''
                if `v' > 0 file write `handle' `"<td class="has">`v'</td>"' _n
                else        file write `handle' `"<td class="zero">0</td>"' _n
            }
            file write `handle' `"</tr>"' _n
        }
    }

    if "`handle'" != "" {
        file write `handle' `"</tbody></table></div>"' _n
    }
end


* ===================================================================
* PRINCIPAL
* ===================================================================

* Aplicar filtros si se pasaron
if "`filtro_depto'" != "" {
    local filtro_depto = upper("`filtro_depto'")
    quietly count if upper(departamento) == "`filtro_depto'"
    if r(N) == 0 {
        di as err "Departamento '`filtro_depto'' no encontrado."
        tab departamento
        exit 0
    }
    quietly keep if upper(departamento) == "`filtro_depto'"
}
if "`filtro_prov'" != "" {
    local filtro_prov = upper("`filtro_prov'")
    quietly keep if upper(provincia) == "`filtro_prov'"
}
if "`filtro_dist'" != "" {
    local filtro_dist = upper("`filtro_dist'")
    quietly keep if upper(distrito) == "`filtro_dist'"
}

* KPIs generales
tempvar cui_ok first_cui
quietly gen `cui_ok' = (cui != "" & !missing(cui))
quietly bysort cui: gen `first_cui' = (_n == 1) if `cui_ok'
quietly count
local kpi_n = r(N)
quietly levelsof cui if `cui_ok', local(cl) clean
local kpi_cui : word count `cl'
quietly summarize monto_inversion if `first_cui' == 1, meanonly
local kpi_monto = cond(missing(r(sum)), 0, r(sum))
quietly summarize devengado if `first_cui' == 1, meanonly
local kpi_dev = cond(missing(r(sum)), 0, r(sum))
quietly summarize avance_fisico, meanonly
local kpi_avf = cond(missing(r(mean)), 0, r(mean))
drop `cui_ok' `first_cui'

local kpi_m_mill : di %12.2fc `kpi_monto'/1000000
local kpi_d_mill : di %12.2fc `kpi_dev'/1000000
local kpi_a_pct  : di %4.1f   `kpi_avf'*100

di _newline(2) as res "===== REPORTE DE INTERVENCIONES ====="
di as txt "Total: " as res `kpi_n' as txt " registros"
di as txt "CUI unicos: " as res `kpi_cui'
di as txt "Monto inversion (sin dup CUI): S/ " as res "`kpi_m_mill' M"
di as txt "Devengado (sin dup CUI): S/ " as res "`kpi_d_mill' M"
di as txt "Avance fisico promedio: " as res "`kpi_a_pct' %"

* --- Abrir archivo HTML ---
tempname fh
local html_path "${Output}/visor_intervenciones.html"
file open `fh' using "`html_path'", write replace

file write `fh' `"<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">"' _n
file write `fh' `"<title>Reporte de Intervenciones - MINEDU</title>"' _n
file write `fh' `"<style>"' _n
file write `fh' `"body{font-family:'Segoe UI',sans-serif;background:#f5f6fa;color:#333;margin:0;padding:0}"' _n
file write `fh' `".header{background:linear-gradient(135deg,#1a237e,#283593);color:white;padding:20px 30px}"' _n
file write `fh' `".container{max-width:1400px;margin:0 auto;padding:15px}"' _n
file write `fh' `".kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:15px 0}"' _n
file write `fh' `".kpi{background:white;border-radius:8px;padding:15px;box-shadow:0 1px 3px rgba(0,0,0,.1)}"' _n
file write `fh' `".kpi .label{font-size:.75em;color:#666;text-transform:uppercase}"' _n
file write `fh' `".kpi .value{font-size:1.6em;font-weight:700;color:#1a237e}"' _n
file write `fh' `".card{background:white;border-radius:8px;padding:18px;margin:12px 0;box-shadow:0 1px 3px rgba(0,0,0,.1)}"' _n
file write `fh' `".card h2{font-size:1em;color:#1a237e;margin-bottom:10px;border-bottom:2px solid #e8eaf6;padding-bottom:6px}"' _n
file write `fh' `".parrafo{line-height:1.7;font-size:.9em;background:#fafafa;padding:12px;border-left:4px solid #3f51b5;border-radius:4px}"' _n
file write `fh' `".parrafo b{color:#1a237e}"' _n
file write `fh' `"table{width:100%;border-collapse:collapse;font-size:.78em}"' _n
file write `fh' `"th{background:#283593;color:white;padding:6px 4px;text-align:center}"' _n
file write `fh' `"td{padding:5px 4px;border-bottom:1px solid #e0e0e0;text-align:right}"' _n
file write `fh' `"td:first-child{text-align:left;font-weight:600}"' _n
file write `fh' `"td.has{background:#e8f5e9;font-weight:600}"' _n
file write `fh' `"td.zero{color:#ccc}"' _n
file write `fh' `"tr:hover{background:#e8eaf6}"' _n
file write `fh' `"</style></head><body>"' _n
file write `fh' `"<div class="header"><h1>Reporte de Intervenciones en Infraestructura Educativa</h1>"' _n
file write `fh' `"<p>MINEDU &mdash; Generado desde BASE_PANORAMA</p></div>"' _n
file write `fh' `"<div class="container">"' _n

* KPIs HTML
file write `fh' `"<div class="kpis">"' _n
file write `fh' `"<div class="kpi"><div class="label">Total intervenciones</div><div class="value">`kpi_n'</div></div>"' _n
file write `fh' `"<div class="kpi"><div class="label">CUI unicos</div><div class="value">`kpi_cui'</div></div>"' _n
file write `fh' `"<div class="kpi"><div class="label">Monto inversion</div><div class="value">S/ `kpi_m_mill' M</div></div>"' _n
file write `fh' `"<div class="kpi"><div class="label">Devengado</div><div class="value">S/ `kpi_d_mill' M</div></div>"' _n
file write `fh' `"<div class="kpi"><div class="label">Avance fisico</div><div class="value">`kpi_a_pct' %</div></div>"' _n
file write `fh' `"</div>"' _n

* Parrafo nacional
_parrafo "NACIONAL" `fh'

* Tabla tipologias
_tabla_tipologias `fh'

* Parrafos por departamento
file write `fh' `"<div class="card"><h2>Detalle por departamento</h2></div>"' _n
quietly levelsof departamento if departamento != "", local(deptos)
foreach d of local deptos {
    preserve
    quietly keep if departamento == "`d'"
    _parrafo "`d'" `fh'

    * Parrafos por provincia dentro del departamento
    quietly levelsof provincia if provincia != "", local(provs)
    foreach p of local provs {
        preserve
        quietly keep if provincia == "`p'"
        _parrafo "`p', `d'" `fh'

        * Parrafos por distrito
        quietly levelsof distrito if distrito != "", local(dists)
        foreach di of local dists {
            preserve
            quietly keep if distrito == "`di'"
            _parrafo "`di', `p', `d'" `fh'
            restore
        }
        restore
    }
    restore
}

* Cerrar HTML
file write `fh' `"</div></body></html>"' _n
file close `fh'

di _newline(2) as res "HTML generado: `html_path'"
di as txt "Abrir en navegador para ver el reporte completo."
