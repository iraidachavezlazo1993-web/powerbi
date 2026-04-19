*! reporte_consulta.do
*! ============================================================================
*! Genera un parrafo-respuesta automatico para requerimientos de informacion.
*!
*! Uso:
*!   do limpieza_por_entidad.do      // primero crea BASE_PANORAMA.dta
*!   global Output "C:\...\03_output"
*!   do reporte_consulta.do DEPARTAMENTO
*!
*! Ejemplos:
*!   do reporte_consulta.do LORETO
*!   do reporte_consulta.do CUSCO
*!   do reporte_consulta.do "MADRE DE DIOS"
*!
*! Si se invoca sin argumento, reporta todo el pais.
*!
*! Produce por pantalla un parrafo con:
*!   - N intervenciones totales
*!   - desglose por entidad (PRONIED, PEIP, UE118, ANIN, FONCODES)
*!   - dentro de PRONIED desglose por unidad (UGEO, UGRD, UGSC, UGME, UGM, UZ)
*!   - monto total de inversion
*!   - devengado acumulado
*!   - avance fisico promedio
*!   - # intervenciones sin CUI o sin geografia
*! ============================================================================

version 15

args depto_filter

if "$Output" == "" global Output "`c(pwd)'/dta"

capture use "${Output}/BASE_PANORAMA.dta", clear
if _rc {
    di as err "ERROR: no existe ${Output}/BASE_PANORAMA.dta"
    di as err "       corra primero: do limpieza_por_entidad.do"
    exit 198
}

* Filtro por departamento si se paso como argumento
local filtro_txt "todo el pais"
if "`depto_filter'" != "" {
    local depto_upper = upper("`depto_filter'")
    quietly count if upper(departamento) == "`depto_upper'"
    if r(N) == 0 {
        di as err "No hay intervenciones en departamento = '`depto_filter''"
        di as err "Verifique con:  tab departamento"
        exit 0
    }
    quietly keep if upper(departamento) == "`depto_upper'"
    local filtro_txt "`depto_upper'"
}

* Conteos
quietly count
local N_total = r(N)

quietly count if !missing(cui)
local N_con_cui = r(N)
local N_sin_cui = `N_total' - `N_con_cui'

quietly count if missing(departamento) | departamento == ""
local N_sin_geo = r(N)

* Monto total
local monto_total = 0
capture confirm numeric variable monto_inversion
if !_rc {
    quietly summarize monto_inversion, meanonly
    local monto_total = r(sum)
}

* Devengado total
local devengado_total = 0
capture confirm numeric variable devengado
if !_rc {
    quietly summarize devengado, meanonly
    local devengado_total = r(sum)
}

* Avance fisico promedio
local avance_prom = .
capture confirm numeric variable avance_fisico
if !_rc {
    quietly summarize avance_fisico, meanonly
    local avance_prom = r(mean)
}

* CUI unicos (misma inversion puede aparecer en multiples unidades)
quietly unique cui if !missing(cui)
local N_cui_unicos = r(unique)
if "`N_cui_unicos'" == "" {
    quietly levelsof cui if !missing(cui), local(culist)
    local N_cui_unicos : word count `culist'
}

*============================================================================
* Armado del parrafo
*============================================================================
di _newline(2)
di as txt "============================================================"
di as res "REPORTE DE INTERVENCIONES - " as res "`filtro_txt'"
di as txt "============================================================"
di _newline(1)

* Linea 1: resumen
local monto_mill : di %12.2fc `monto_total'/1000000
local deve_mill  : di %12.2fc `devengado_total'/1000000
local avance_pct : di %4.1f  (`avance_prom')*100

di as txt "En " as res "`filtro_txt'" as txt " se identifican " ///
    as res `N_total' as txt " registros de intervencion " ///
    as txt "(" as res `N_cui_unicos' as txt " CUI unicos)."

if `monto_total' > 0 {
    di as txt "Monto total de inversion: " as res "S/ `monto_mill' millones" as txt "."
}
if `devengado_total' > 0 {
    di as txt "Devengado acumulado: " as res "S/ `deve_mill' millones" as txt "."
}
if !missing(`avance_prom') {
    di as txt "Avance fisico promedio: " as res "`avance_pct' %" as txt "."
}

* Linea 2: desglose por entidad
di _newline(1) as txt "Desglose por entidad:"
levelsof entidad, local(ents)
foreach e of local ents {
    quietly count if entidad == "`e'"
    local ne = r(N)
    quietly count if entidad == "`e'" & !missing(cui)
    local ne_cui = r(N)
    * Monto por entidad
    local me = 0
    capture confirm numeric variable monto_inversion
    if !_rc {
        quietly summarize monto_inversion if entidad == "`e'", meanonly
        local me = cond(missing(r(sum)), 0, r(sum))
    }
    local me_mill : di %10.2fc `me'/1000000
    di as txt "  - " as res %-12s "`e'" as txt ": " ///
        as res %6.0f `ne' as txt " registros" ///
        as txt " (" as res %6.0f `ne_cui' as txt " con CUI), " ///
        as txt "monto S/ " as res "`me_mill' M"
}

* Linea 3: desglose PRONIED por unidad
quietly count if entidad == "PRONIED"
if r(N) > 0 {
    di _newline(1) as txt "Dentro de PRONIED por unidad/hoja:"
    levelsof unidad if entidad == "PRONIED", local(unidades)
    foreach u of local unidades {
        quietly count if entidad == "PRONIED" & unidad == "`u'"
        di as txt "    * " as res %-30s "`u'" as txt ": " ///
            as res %6.0f r(N) as txt " registros"
    }
}

* Linea 4: conteos por tipo
di _newline(1) as txt "Composicion por tipo de intervencion:"
capture confirm variable tipo_intervencion
if !_rc {
    quietly levelsof tipo_intervencion if !missing(tipo_intervencion), local(tipos)
    foreach t of local tipos {
        quietly count if tipo_intervencion == "`t'"
        di as txt "    - " as res %-30s "`t'" as txt ": " as res %6.0f r(N)
    }
}
capture confirm variable tipo_mantenimiento
if !_rc {
    quietly levelsof tipo_mantenimiento if !missing(tipo_mantenimiento), local(tipos)
    foreach t of local tipos {
        quietly count if tipo_mantenimiento == "`t'"
        di as txt "    - " as res %-30s "`t'" as txt ": " as res %6.0f r(N)
    }
}

* Linea 5: cobertura
di _newline(1) as txt "Cobertura de datos:"
di as txt "  - con CUI:         " as res %6.0f `N_con_cui' ///
   as txt " (" as res %4.1f `N_con_cui'*100/`N_total' as txt " %)"
di as txt "  - sin CUI:         " as res %6.0f `N_sin_cui'
di as txt "  - sin departamento: " as res %6.0f `N_sin_geo'

di _newline(1) as txt "============================================================"


*============================================================================
* Parrafo-respuesta compacto (copy-paste)
*============================================================================
di _newline(2) as res "PARRAFO-RESPUESTA (copiar y pegar):"
di as txt "------------------------------------------------------------"

* Top 3 entidades por N
tempvar order_n
quietly {
    preserve
    contract entidad, freq(_freq)
    gsort -_freq
    local top_txt ""
    local i = 0
    foreach en in `=c(obs)' {
    }
    forvalues r = 1/`=_N' {
        local ++i
        if `i' > 4 continue
        local en = entidad[`r']
        local nr = _freq[`r']
        if `i' == 1 local top_txt "`en' (`nr')"
        else        local top_txt "`top_txt', `en' (`nr')"
    }
    restore
}

di _newline(1)
#delimit ;
di as txt "En " as res "`filtro_txt'"
   as txt " se han identificado " as res `N_total'
   as txt " registros de intervencion asociados a " as res `N_cui_unicos'
   as txt " CUI unicos. La distribucion por entidad es: "
   as res "`top_txt'" as txt ". "
   as txt "El monto total de inversion asciende a "
   as res "S/ `monto_mill' millones" as txt ", "
   as txt "con " as res "S/ `deve_mill' millones" as txt " devengados"
   as txt " y un avance fisico promedio de "
   as res "`avance_pct' %" as txt ".";
#delimit cr

di as txt "------------------------------------------------------------"
di _newline(1)
