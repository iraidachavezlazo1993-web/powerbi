*! clean_excel_to_dta.do   v2
*! ============================================================================
*! Limpieza integral Excel -> DTA para MINEDU.
*!
*! Novedades de esta version:
*!   1) Limpieza de codigos (codigo_local=6 digitos, codigo_modular=7,
*!      codigo_institucion=8, CUI=7) con padding de ceros y separador unico "/".
*!      - Soporta multiples codigos en una misma celda.
*!      - Elimina espacios, corchetes "[]", parentesis, ";", ",", "\", "|".
*!      - Quita sufijos/prefijos tipo "-1", "-A", "A-".
*!   2) Parseo de fechas (YMD, DMY, MDY) a formato Stata %td.
*!   3) Coercion a numerico cuando >=80% de valores no vacios parsean.
*!   4) Diccionario comun de variables: renombra sinonimos al nombre canonico
*!      (cui, codigo_local, codigo_modular, monto_inversion, fecha_inicio,
*!      fase_obra, etapa_obra, estado, avance_fisico, comentario_general,
*!      departamento, provincia, distrito, nombre_inversion, nombre_corto,
*!      nombre_ie).
*!   5) Guarda una .dta por unidad/hoja con la nomenclatura estandar.
*!
*! Uso:
*!      do clean_excel_to_dta.do
*! ============================================================================

version 15
clear all
set more off

* === Rutas (ajustar si es necesario) =======================================
if "$Input" == "" global Input  "`c(pwd)'"
if "$Output" == "" global Output "`c(pwd)'/dta"
cap mkdir "${Output}"


*============================================================================
* HELPERS
*============================================================================

*------------------------------------------------------------
* _rename_any : renombra `from' -> `to' si `from' existe.
*               Si `to' ya existe, renombra `from' a `from'_alt
*               para no perder informacion.
*------------------------------------------------------------
capture program drop _rename_any
program define _rename_any
    args from to
    capture confirm variable `from'
    if _rc exit 0
    if "`from'" == "`to'" exit 0
    capture confirm variable `to'
    if !_rc {
        capture rename `from' `from'_alt
    }
    else {
        rename `from' `to'
    }
end


*------------------------------------------------------------
* clean_code : estandariza una variable de codigo a digitos
*              separados por "/" y con padding a `digits' chars.
*              Ejemplos:
*                "[123456]"              -> "123456"
*                "123456-1"              -> "123456"
*                "A-123456"              -> "123456"
*                "123456 / 7890"         -> "123456/0007890"
*                "123456;7890"           -> "123456/0007890"
*                " 12345 "               -> "012345"  (si digits=6)
*------------------------------------------------------------
capture program drop clean_code
program define clean_code
    syntax varname, Digits(integer)
    local v `varlist'

    capture confirm string variable `v'
    if _rc {
        tostring `v', replace force
    }

    quietly {
        * Limpieza masiva con regex sobre todo el vector
        replace `v' = ustrregexra(`v', "\s+", "")
        replace `v' = ustrregexra(`v', "[\[\]\(\){}]", "")
        replace `v' = ustrregexra(`v', "[;,\\\\|]", "/")
        replace `v' = ustrregexra(`v', "-[A-Za-z0-9]+", "")
        replace `v' = ustrregexra(`v', "[A-Za-z]+-", "")
        replace `v' = ustrregexra(`v', "[^0-9/]", "")
        replace `v' = ustrregexra(`v', "/+", "/")
        replace `v' = ustrregexra(`v', "^/|/$", "")
    }

    * Pad cada pieza a `digits' digitos
    local zeros = "000000000000"
    tempvar newv
    quietly gen `newv' = ""
    quietly count
    local N = r(N)
    forvalues i = 1/`N' {
        local raw = `v'[`i']
        if "`raw'" == "" continue
        local parts : subinstr local raw "/" " ", all
        local out ""
        foreach p of local parts {
            if regexm("`p'", "^[0-9]+$") {
                local len = strlen("`p'")
                if `len' < `digits' {
                    local npad = `digits' - `len'
                    local p = substr("`zeros'", 1, `npad') + "`p'"
                }
                if "`out'" == "" local out "`p'"
                else             local out "`out'/`p'"
            }
        }
        quietly replace `newv' = "`out'" in `i'
    }
    quietly replace `v' = `newv'
    drop `newv'
end


*------------------------------------------------------------
* clean_date : intenta parsear una variable string a fecha %td
*              (prueba YMD, DMY, MDY). Solo convierte si >=80%
*              de los valores no vacios parsean.
*------------------------------------------------------------
capture program drop clean_date
program define clean_date
    syntax varname
    local v `varlist'

    capture confirm string variable `v'
    if _rc exit 0

    tempvar d
    quietly gen double `d' = .
    quietly replace `d' = daily(`v', "YMD hms") if missing(`d') & `v' != ""
    quietly replace `d' = daily(`v', "YMD")     if missing(`d') & `v' != ""
    quietly replace `d' = daily(`v', "DMY")     if missing(`d') & `v' != ""
    quietly replace `d' = daily(`v', "MDY")     if missing(`d') & `v' != ""

    quietly count if `v' != ""
    local total = r(N)
    if `total' == 0 {
        drop `d'
        exit 0
    }
    quietly count if `v' != "" & !missing(`d')
    local ok = r(N)
    if (`ok'/`total') >= 0.8 {
        local lbl : variable label `v'
        drop `v'
        rename `d' `v'
        format `v' %td
        if `"`lbl'"' != "" label variable `v' `"`lbl'"'
    }
    else {
        drop `d'
    }
end


*------------------------------------------------------------
* apply_dictionary : renombra variables a nombres canonicos
*              del diccionario comun. Se ejecuta DESPUES de que
*              clean_one normalizo los nombres a snake_case ASCII.
*------------------------------------------------------------
capture program drop apply_dictionary
program define apply_dictionary
    * --- Llaves ---
    _rename_any cui_idea                              cui
    _rename_any codigo_unico_de_inversiones_cui       cui
    _rename_any codigo_unico_de_inversiones_c         cui
    _rename_any codigo_unico                          cui
    _rename_any codigo_de_la_inversion                cui
    _rename_any codigo_inversion                      cui
    _rename_any codigo_snip                           cui_snip
    _rename_any codigo_idea                           cui_idea

    _rename_any codigo_del_local_educativo            codigo_local
    _rename_any cod_local                             codigo_local

    _rename_any cod_modular                           codigo_modular
    _rename_any cod_mod                               codigo_modular
    _rename_any codigos_modulares_intervenidos_d      codigos_modulares
    _rename_any codigos_modulares_intervenidos        codigos_modulares

    * --- Nombres ---
    _rename_any nombre_corto_pi                       nombre_corto
    _rename_any nombre_largo_pi                       nombre_inversion
    _rename_any nombre_de_la_inversion                nombre_inversion
    _rename_any nombre_del_proyecto                   nombre_inversion
    _rename_any nombre_del_peip                       nombre_inversion
    _rename_any nombre_de_la_i_e                      nombre_ie
    _rename_any i_e                                   nombre_ie

    * --- Ubicacion ---
    _rename_any departamento_cui                      departamento
    _rename_any departamento_proxy                    departamento
    _rename_any provincia_cui                         provincia

    * --- Estado / etapa / fase ---
    _rename_any estado_de_la_inversion                estado
    _rename_any estado_de_la_intervencion             estado
    _rename_any estado_proyecto                       estado
    _rename_any fase_de_la_obra                       fase_obra
    _rename_any fase_del_componente                   fase_obra
    _rename_any etapa_de_la_obra                      etapa_obra
    _rename_any etapa_del_componente                  etapa_obra
    _rename_any etapa_de_la_intervencion_idea         etapa_intervencion

    * --- Montos ---
    _rename_any monto_de_inversion_s                  monto_inversion
    _rename_any monto_total_de_inversion_s            monto_inversion
    _rename_any monto_de_la_inversion_soles           monto_inversion
    _rename_any monto_de_inversion_del_componen       monto_inversion
    _rename_any monto_de_inversion_del_component      monto_inversion
    _rename_any monto_de_la_intervencion_2025         monto_inversion
    _rename_any monto_de_la_intervencion_2026         monto_inversion
    _rename_any monto_de_la_inversion_actuali         monto_inversion
    _rename_any monto_de_la_inversion                 monto_inversion
    _rename_any costo_actualizado                     monto_inversion
    _rename_any devengado_acumulado                   devengado

    * --- Avance ---
    _rename_any avance_fisico                         avance_fisico
    _rename_any avance_fisico_al_22_03_202            avance_fisico
    _rename_any de_avance_fisico_de_obra              avance_fisico
    _rename_any avance_financiero                     avance_financiero
    _rename_any de_avance_diseno                      avance_diseno
    _rename_any avance                                avance_fisico

    * --- Fechas ---
    _rename_any fecha_de_inicio_de_la_obra_o_est      fecha_inicio
    _rename_any fecha_de_inicio_de_obra               fecha_inicio
    _rename_any fecha_de_inicio                       fecha_inicio
    _rename_any fecha_inicio_de_obra                  fecha_inicio

    _rename_any fecha_de_culminacion_de_obra_o_e      fecha_culminacion
    _rename_any fecha_de_culminacion_de_obra          fecha_culminacion
    _rename_any fecha_de_culminacion                  fecha_culminacion
    _rename_any fecha_de_culminacion_estimada         fecha_culminacion

    _rename_any fecha_de_recepcion_de_obra_o_est      fecha_recepcion
    _rename_any fecha_de_recepcion_o_estimada         fecha_recepcion

    _rename_any fecha_de_entrega_de_obra_o_estim      fecha_entrega
    _rename_any fecha_de_entrega_o_estimada           fecha_entrega

    _rename_any fecha_de_inauguracion_o_estimada      fecha_inauguracion

    _rename_any culminados_entregados_fecha           fecha_culminacion

    * --- Comentarios ---
    _rename_any comentarios                           comentario_general
    _rename_any comentarios_otras_variables           comentario_general
    _rename_any comentarios_otras_variables_q         comentario_general
    _rename_any comentario                            comentario_general

    * --- Otros ---
    _rename_any tipo_de_mantenimiento                 tipo_mantenimiento
    _rename_any tipo_de_inversion_pi_regular_ioa      tipo_inversion
    _rename_any tipo_de_la_inversion                  tipo_inversion
    _rename_any tipo_de_intervencion_mbr_o_me         tipo_intervencion
    _rename_any tipo_de_sistema_modular               tipo_sistema_modular
end


*============================================================================
* clean_one : procesa una hoja de Excel y exporta .dta limpia
*============================================================================
capture program drop clean_one
program define clean_one
    syntax, FILE(string) SHEET(string) ROW(integer) PREFIX(string)

    di _newline(1) as txt "===== " as res "`prefix'" as txt " ====="

    * -------- 1. IMPORTAR ----------------------------------------------
    capture import excel using "`file'", sheet("`sheet'") ///
        cellrange(A`row') firstrow allstring clear
    if _rc {
        di as err "  no se pudo importar `file' / `sheet' (rc=`_rc'), se omite."
        exit 0
    }
    local N0 = _N

    * -------- 2. NORMALIZAR NOMBRES DE VARIABLES -----------------------
    quietly ds
    local oldvars `r(varlist)'
    local i = 0
    foreach v of local oldvars {
        local ++i
        rename `v' __v`i'
    }

    local used ""
    local i = 0
    foreach v of local oldvars {
        local ++i
        local lbl : variable label __v`i'
        if `"`lbl'"' == "" local lbl "`v'"
        local nn = ustrlower(ustrnormalize(`"`lbl'"', "nfd"))
        local nn = ustrregexra("`nn'", "\p{Mn}", "")
        local nn = ustrregexra("`nn'", "[^a-z0-9]+", "_")
        local nn = ustrregexra("`nn'", "^_+|_+$", "")
        if "`nn'" == "" local nn "col"
        if regexm("`nn'", "^[0-9]") local nn "v_`nn'"
        local nn = substr("`nn'", 1, 32)
        local base "`nn'"
        local j = 1
        while strpos(" `used' ", " `nn' ") > 0 {
            local suf = "_`j'"
            local nn = substr("`base'", 1, 32 - strlen("`suf'")) + "`suf'"
            local ++j
        }
        rename __v`i' `nn'
        label variable `nn' `"`lbl'"'
        local used "`used' `nn'"
    }

    * -------- 3. LIMPIAR STRINGS (espacios, saltos, missing) -----------
    quietly ds, has(type string)
    foreach v in `r(varlist)' {
        quietly replace `v' = subinstr(`v', char(10), " ", .)
        quietly replace `v' = subinstr(`v', char(13), " ", .)
        quietly replace `v' = subinstr(`v', char(9),  " ", .)
        quietly replace `v' = strtrim(stritrim(`v'))
        quietly replace `v' = "" if inlist(ustrlower(`v'), ///
            "-","--","---","----","-----","------","-------", ///
            "n/a","na","n.a.","nan","none","null",".","..", ///
            "s/d","s/i","-.",".-")
    }

    * -------- 4. DROP FILAS 100% VACIAS --------------------------------
    tempvar hasdata
    quietly gen byte `hasdata' = 0
    quietly ds
    foreach v in `r(varlist)' {
        capture confirm string variable `v'
        if !_rc {
            quietly replace `hasdata' = 1 if `v' != ""
        }
        else {
            quietly replace `hasdata' = 1 if !missing(`v')
        }
    }
    quietly drop if `hasdata' == 0

    * -------- 5. DICCIONARIO COMUN ------------------------------------
    apply_dictionary

    * -------- 6. LIMPIAR CODIGOS (largo fijo, separados por "/") -------
    *   codigo_local      -> 6 digitos
    *   codigo_modular    -> 7 digitos
    *   codigo_institucion-> 8 digitos
    *   cui / cui_snip    -> 7 digitos
    foreach c in codigo_local codigo_local_alt {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(6)
    }
    foreach c in codigo_modular codigo_modular_alt codigos_modulares codigos_modulares_alt {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(7)
    }
    foreach c in codigo_institucion codigo_institucion_alt {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(8)
    }
    foreach c in cui cui_alt cui_snip cui_idea {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(7)
    }

    * -------- 7. PARSEAR FECHAS (cualquier variable que empiece con fecha_) --
    quietly ds fecha*, has(type string)
    if "`r(varlist)'" != "" {
        foreach v in `r(varlist)' {
            clean_date `v'
        }
    }

    * -------- 8. COERCION NUMERICA (resto de strings con >=80% numeros) --
    quietly ds, has(type string)
    foreach v in `r(varlist)' {
        * No coaccionar codigos ni nombres
        if inlist("`v'", "cui","cui_snip","cui_idea", ///
                 "codigo_local","codigo_modular","codigo_institucion", ///
                 "codigos_modulares") continue
        tempvar nv
        quietly gen double `nv' = real(`v')
        quietly count if `v' != ""
        local nn_ne = r(N)
        quietly count if !missing(`nv')
        local nn_num = r(N)
        if `nn_ne' > 0 & (`nn_num'/`nn_ne') >= 0.8 {
            local lbl : variable label `v'
            drop `v'
            rename `nv' `v'
            if `"`lbl'"' != "" label variable `v' `"`lbl'"'
        }
        else {
            drop `nv'
        }
    }

    * -------- 9. FORMATO ------------------------------------------------
    capture confirm numeric variable monto_inversion
    if !_rc format monto_inversion %15.2fc
    capture confirm numeric variable devengado
    if !_rc format devengado %15.2fc
    capture confirm numeric variable avance_fisico
    if !_rc format avance_fisico %6.4f
    capture confirm numeric variable avance_financiero
    if !_rc format avance_financiero %6.4f

    * -------- 10. DUPLICADOS EXACTOS -----------------------------------
    quietly duplicates drop
    local N1 = _N
    di as txt "  filas raw/limpias: " as res "`N0' -> `N1'"

    * -------- 11. REPORTE DE LLAVES ------------------------------------
    foreach k in cui codigo_local codigo_modular {
        capture confirm variable `k'
        if !_rc {
            tempvar tag
            quietly duplicates tag `k', gen(`tag')
            capture confirm string variable `k'
            if !_rc {
                quietly count if `tag' > 0 & `k' != ""
            }
            else {
                quietly count if `tag' > 0 & !missing(`k')
            }
            di as txt "  llave `k': " r(N) " obs con valor duplicado"
            drop `tag'
        }
    }

    * -------- 12. ORDENAR VARIABLES DE FORMA CANONICA ------------------
    local front "cui cui_snip cui_idea codigo_local codigo_modular codigos_modulares nombre_ie nombre_inversion nombre_corto departamento provincia distrito estado fase_obra etapa_obra tipo_inversion tipo_intervencion tipo_mantenimiento tipo_sistema_modular monto_inversion devengado avance_fisico avance_financiero fecha_inicio fecha_culminacion fecha_recepcion fecha_entrega fecha_inauguracion comentario_general"
    local ord_existing ""
    foreach v of local front {
        capture confirm variable `v'
        if !_rc local ord_existing "`ord_existing' `v'"
    }
    if "`ord_existing'" != "" order `ord_existing'

    * -------- 13. GUARDAR ----------------------------------------------
    save "${Output}/`prefix'.dta", replace
    di as txt "  -> ${Output}/`prefix'.dta"
end


*============================================================================
* PASO 1 - Procesar todas las hojas
*============================================================================

* --- PRONIED -------------------------------------------------------------
clean_one, file("${Input}/UGEO.xlsx") sheet("UGEO")            row(3) prefix("PRONIED_UGEO")
clean_one, file("${Input}/UGRD.xlsx") sheet("PIRCC")           row(3) prefix("PRONIED_UGRD_PIRCC")
clean_one, file("${Input}/UGRD.xlsx") sheet("MBR")             row(3) prefix("PRONIED_UGRD_MBR")
clean_one, file("${Input}/UGRD.xlsx") sheet("ME")              row(3) prefix("PRONIED_UGRD_ME")

* --- PEIP ----------------------------------------------------------------
clean_one, file("${Input}/PEIP.xlsx") sheet("IMPLEMENTADOS")   row(3) prefix("PEIP_IMPLEMENTADOS")
clean_one, file("${Input}/PEIP.xlsx") sheet("CONTINGENCIA")    row(3) prefix("PEIP_CONTINGENCIA")
clean_one, file("${Input}/PEIP.xlsx") sheet("MANTENIMIENTO")   row(3) prefix("PEIP_MANTENIMIENTO")

* --- UE118 ---------------------------------------------------------------
clean_one, file("${Input}/UE118.xlsx") sheet("PMESUT")         row(2) prefix("UE118_PMESUT")
clean_one, file("${Input}/UE118.xlsx") sheet("PMESTP")         row(2) prefix("UE118_PMESTP")

* --- ANIN ----------------------------------------------------------------
clean_one, file("${Input}/ANIN.xlsx") sheet("Anexo 1")         row(3) prefix("ANIN")

* --- FONCODES ------------------------------------------------------------
clean_one, file("${Input}/FONCODES.xlsx") sheet("LE_INTERVENIDOS_2017-2025") row(2) prefix("FONCODES_LE_INTERVENIDOS")
clean_one, file("${Input}/FONCODES.xlsx") sheet("REPORTE_MANT_ACOND_2025")   row(2) prefix("FONCODES_MANT_2025")
clean_one, file("${Input}/FONCODES.xlsx") sheet("REPORTE_MANT_ACOND_2026")   row(2) prefix("FONCODES_MANT_2026")

* --- Auxiliares ----------------------------------------------------------
clean_one, file("${Input}/2026.04.13 Base de Inversiones.xlsx") sheet("Data") row(5) prefix("MEF_Base_Inversiones")
clean_one, file("${Input}/CUI_cartera_GN.xlsx")                sheet("Hoja1") row(1) prefix("CUI_cartera_GN")


*============================================================================
* PASO 2 - Consolidar por entidad (append con variable "source")
*============================================================================

* --- PRONIED (apila las 4 unidades con variable `unidad`) ----------------
capture {
    use "${Output}/PRONIED_UGEO.dta", clear
    gen unidad = "UGEO"
    append using "${Output}/PRONIED_UGRD_PIRCC.dta"
    replace unidad = "UGRD_PIRCC" if missing(unidad)
    append using "${Output}/PRONIED_UGRD_MBR.dta"
    replace unidad = "UGRD_MBR" if missing(unidad)
    append using "${Output}/PRONIED_UGRD_ME.dta"
    replace unidad = "UGRD_ME" if missing(unidad)
    order unidad, first
    save "${Output}/PRONIED.dta", replace
    di as res "PRONIED consolidado: " _N " obs"
}

* --- PEIP (apila IMPLEMENTADOS, CONTINGENCIA, MANTENIMIENTO) --------------
capture {
    use "${Output}/PEIP_IMPLEMENTADOS.dta", clear
    gen tipo_reporte = "IMPLEMENTADOS"
    append using "${Output}/PEIP_CONTINGENCIA.dta"
    replace tipo_reporte = "CONTINGENCIA" if missing(tipo_reporte)
    append using "${Output}/PEIP_MANTENIMIENTO.dta"
    replace tipo_reporte = "MANTENIMIENTO" if missing(tipo_reporte)
    order tipo_reporte, first
    save "${Output}/PEIP.dta", replace
    di as res "PEIP consolidado: " _N " obs"
}

* --- UE118 (apila PMESUT + PMESTP) ---------------------------------------
capture {
    use "${Output}/UE118_PMESUT.dta", clear
    gen programa = "PMESUT"
    append using "${Output}/UE118_PMESTP.dta"
    replace programa = "PMESTP" if missing(programa)
    order programa, first
    save "${Output}/UE118.dta", replace
    di as res "UE118 consolidado: " _N " obs"
}

* --- FONCODES (apila las 3 hojas) ----------------------------------------
capture {
    use "${Output}/FONCODES_LE_INTERVENIDOS.dta", clear
    gen tipo_reporte = "LE_INTERVENIDOS_2017_2025"
    append using "${Output}/FONCODES_MANT_2025.dta"
    replace tipo_reporte = "MANT_2025" if missing(tipo_reporte)
    append using "${Output}/FONCODES_MANT_2026.dta"
    replace tipo_reporte = "MANT_2026" if missing(tipo_reporte)
    order tipo_reporte, first
    save "${Output}/FONCODES.dta", replace
    di as res "FONCODES consolidado: " _N " obs"
}


*============================================================================
* PASO 3 - Reporte final
*============================================================================
di _newline(2) as txt "===== BASES GENERADAS ====="
foreach f in PRONIED PRONIED_UGEO PRONIED_UGRD_PIRCC PRONIED_UGRD_MBR PRONIED_UGRD_ME ///
             PEIP PEIP_IMPLEMENTADOS PEIP_CONTINGENCIA PEIP_MANTENIMIENTO ///
             UE118 UE118_PMESUT UE118_PMESTP ///
             ANIN ///
             FONCODES FONCODES_LE_INTERVENIDOS FONCODES_MANT_2025 FONCODES_MANT_2026 ///
             MEF_Base_Inversiones CUI_cartera_GN {
    capture use "${Output}/`f'.dta", clear
    if _rc continue
    di as res "`f'" as txt " -> " _N " obs, " c(k) " vars"
}

di _newline(2) as res "Listo. Los .dta estan en ${Output}"
di as txt "Entidades PRONIED pendientes: UGSC, UGME, UGM, Uzonal."
