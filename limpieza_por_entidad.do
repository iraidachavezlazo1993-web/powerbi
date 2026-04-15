*! limpieza_por_entidad.do
*! ============================================================================
*! Limpieza por entidad en estilo directo (import + rename + drop por base).
*!
*! Incluye 3 helpers al inicio:
*!   clean_code    -> estandariza codigos a N digitos, separados por "/"
*!   clean_date    -> parsea strings a fecha %td (YMD, DMY, MDY)
*!   canon_rename  -> aplica el diccionario comun de nombres
*!
*! Al final hace un append por entidad con variable de origen.
*!
*! Uso:
*!   global Input  "C:\...\01_input"
*!   global Output "C:\...\03_output"
*!   do "...\limpieza_por_entidad.do"
*! ============================================================================

version 15
clear all
set more off

* === Rutas (si no estan globales, usar directorio de trabajo) ===
if "$Input"  == "" global Input  "`c(pwd)'"
if "$Output" == "" global Output "`c(pwd)'/dta"
cap mkdir "${Output}"


*============================================================================
* HELPERS
*============================================================================

* ----- clean_code -----------------------------------------------------------
capture program drop clean_code
program define clean_code
    syntax varname, Digits(integer)
    local v `varlist'
    capture confirm string variable `v'
    if _rc tostring `v', replace force

    quietly {
        replace `v' = ustrregexra(`v', "\s+", "")
        replace `v' = ustrregexra(`v', "[\[\]\(\){}]", "")
        replace `v' = ustrregexra(`v', "[;,\\\\|]", "/")
        replace `v' = ustrregexra(`v', "-[A-Za-z0-9]+", "")
        replace `v' = ustrregexra(`v', "[A-Za-z]+-", "")
        replace `v' = ustrregexra(`v', "[^0-9/]", "")
        replace `v' = ustrregexra(`v', "/+", "/")
        replace `v' = ustrregexra(`v', "^/|/$", "")
    }

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


* ----- clean_date -----------------------------------------------------------
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
    else drop `d'
end


* ----- ren_if : renombra solo si existe -------------------------------------
capture program drop ren_if
program define ren_if
    args from to
    capture confirm variable `from'
    if _rc exit 0
    if "`from'" == "`to'" exit 0
    capture confirm variable `to'
    if !_rc capture rename `from' `from'_alt
    else    rename `from' `to'
end


* ----- rename_from_label ----------------------------------------------------
* Si una variable tiene nombre de 1 o 2 letras (lo que pasa cuando Stata
* no pudo construir un nombre desde el header, o choca con otro nombre
* truncado), reconstruye el nombre desde el variable label, normalizado
* a snake_case ASCII <=32 chars.
capture program drop rename_from_label
program define rename_from_label
    quietly ds
    local used " `r(varlist)' "
    foreach v in `r(varlist)' {
        if !regexm("`v'", "^[A-Za-z]{1,2}$") continue
        local lbl : variable label `v'
        if `"`lbl'"' == "" continue
        local nn = ustrlower(ustrnormalize(`"`lbl'"', "nfd"))
        local nn = ustrregexra("`nn'", "\p{Mn}", "")
        local nn = ustrregexra("`nn'", "[^a-z0-9]+", "_")
        local nn = ustrregexra("`nn'", "^_+|_+$", "")
        if "`nn'" == "" continue
        if regexm("`nn'", "^[0-9]") local nn "v_`nn'"
        local nn = substr("`nn'", 1, 32)
        * desambiguar
        local base "`nn'"
        local i = 1
        while strpos("`used'", " `nn' ") > 0 {
            local suf = "_`i'"
            local nn = substr("`base'", 1, 32 - strlen("`suf'")) + "`suf'"
            local ++i
        }
        capture rename `v' `nn'
        if !_rc local used "`used'`nn' "
    }
end


* ----- canon_rename : aplica diccionario comun a Unicode/Stata var names ----
capture program drop canon_rename
program define canon_rename
    * Llaves
    ren_if CUI                            cui
    ren_if CUIÍDEA                        cui
    ren_if CUIÍdea                        cui
    ren_if CUIIdea                        cui
    ren_if CUIIDEA                        cui
    ren_if CódigoÚnicodeInversionesCUI    cui
    ren_if CódigoÚnicodeInversionesC      cui
    ren_if CódigoÚnicodeInversiones       cui
    ren_if CódigoLocal                    codigo_local
    ren_if CódigodelLocalEducativo        codigo_local
    ren_if CódigoModular                  codigo_modular
    ren_if CODIGOMODULAR                  codigo_modular
    ren_if CODMODULAR                     codigo_modular
    ren_if CodModular                     codigo_modular
    ren_if Códigosmodularesintervenidos   codigos_modulares
    ren_if CódigosmodularesintervenidosD  codigos_modulares

    * Nombres
    ren_if NombreCorto                    nombre_corto
    ren_if NombrecortoPI                  nombre_corto
    ren_if NombrelargoPI                  nombre_inversion
    ren_if NombredelaInversión            nombre_inversion
    ren_if NombredelProyecto              nombre_inversion
    ren_if NOMBREIE                       nombre_ie
    ren_if NombredelaIE                   nombre_ie
    ren_if NombreIE                       nombre_ie
    ren_if NombredelPEIP                  nombre_peip
    ren_if IE                             nombre_ie

    * Ubicacion
    ren_if Departamento                   departamento
    ren_if DEPARTAMENTO                   departamento
    ren_if Provincia                      provincia
    ren_if PROVINCIA                      provincia
    ren_if Distrito                       distrito
    ren_if DISTRITO                       distrito

    * Estado / fase / etapa
    ren_if Estado                         estado
    ren_if ESTADOPROYECTO                 estado
    ren_if EstadodelaIntervención         estado
    ren_if EstadodelaInversión            estado
    ren_if Fasedelaobra                   fase_obra
    ren_if Fasedelcomponente              fase_obra
    ren_if Etapadelaobra                  etapa_obra
    ren_if Etapadelcomponente             etapa_obra
    ren_if EtapadelaintervenciónIdea      etapa_intervencion

    * Tipos
    ren_if Tipodeintervención             tipo_intervencion
    ren_if TipodeintervenciónMBRoME       tipo_intervencion
    ren_if Tipodesistemamodular           tipo_sistema_modular
    ren_if TipodeInversión                tipo_inversion
    ren_if TipodelaInversión              tipo_inversion
    ren_if TipodeMantenimiento            tipo_mantenimiento
    ren_if TIPODEMANTENIMIENTO            tipo_mantenimiento

    * Montos
    ren_if MontodeinversiónS              monto_inversion
    ren_if MontototaldeinversiónS         monto_inversion
    ren_if MontodelaInversiónSoles        monto_inversion
    ren_if Montodeinversióndelcomponent   monto_inversion
    ren_if MONTODELAINTERVENCIÓN2025      monto_inversion
    ren_if MONTODELAINTERVENCIÓN2026      monto_inversion
    ren_if CostoActualizado               monto_inversion
    ren_if DevengadoAcumulado             devengado

    * Avance
    ren_if Avancefísico                   avance_fisico
    ren_if AvanceDISEÑO                   avance_diseno
    ren_if AVANCE                         avance_fisico
    ren_if Avancefinanciero               avance_financiero
    ren_if AvanceFinanciero               avance_financiero
    ren_if AvanceFísico                   avance_fisico

    * Fechas
    ren_if FechadeIniciodeObra            fecha_inicio
    ren_if Fechadeiniciodelaobraoestimada fecha_inicio
    ren_if FECHADEINICIO                  fecha_inicio
    ren_if FechadeCulminacióndeObra       fecha_culminacion
    ren_if Fechadeculminacióndeobrao      fecha_culminacion
    ren_if FECHADECULMINACIÓN             fecha_culminacion
    ren_if FECHADECULMINACIONESTIMADA     fecha_culminacion
    ren_if FechadeRecepcióndeObra         fecha_recepcion
    ren_if Fechaderecepcióndeobraoes      fecha_recepcion
    ren_if Fechaderecepciónoestimada      fecha_recepcion
    ren_if FechadeEntregadeObra           fecha_entrega
    ren_if Fechadeentregadeobraoesti      fecha_entrega
    ren_if Fechadeentregaoestimada        fecha_entrega
    ren_if FechadeLiquidación             fecha_liquidacion
    ren_if Fechadeinauguraciónoesti       fecha_inauguracion
    ren_if CulminadosEntregadosFecha      fecha_culminacion

    * Comentarios
    ren_if Comentarios                    comentario_general
    ren_if Comentario                     comentario_general
    ren_if COMENTARIO                     comentario_general
    ren_if ComentariosOtrasvariablesq     comentario_general
    ren_if ComentariosOtrasvariablesQ     comentario_general

    * Variantes adicionales observadas en ANIN, FONCODES, etc.
    ren_if Ord                            ord
    ren_if NOMBRECORTO                    nombre_corto
    ren_if NOMBREDELAINVERSIÓN            nombre_inversion
    ren_if DEAVANCEDISEÑO                 avance_diseno
    ren_if DEAVANCEFÍSICODEOBRA           avance_fisico
    ren_if COSTOACTUALIZADO               monto_inversion
    ren_if DEVENGADOACUMULADO             devengado
    ren_if AvanceFinanciero               avance_financiero
    ren_if PAM2025                        pam_2025
    ren_if PAM2026                        pam_2026
    ren_if CONVENIOMANTENIMIENTO          convenio_mantenimiento
    ren_if CONVENIO                       convenio_mantenimiento
    ren_if ESTADO                         estado
    ren_if ESTADOA                        estado_convenio
    ren_if EstadoA                        estado_convenio
    ren_if NOMBRECONVENIO                 nombre_convenio

    * FONCODES cabeceras mayusculas
    ren_if CODIGODELLOCALEDUCATIVO        codigo_local
    ren_if NOMBREDELPROYECTO              nombre_inversion
    ren_if TIPODELAINVERSIÓN              tipo_inversion
    ren_if ESTADODELAINVERSIÓN            estado
    ren_if MONTODELAINVERSIÓNSOLES        monto_inversion
    ren_if AVANCEFÍSICO                   avance_fisico
    ren_if FECHADEINICIODEOBRA            fecha_inicio
    ren_if FECHADECULMINACIÓNDEOBRA       fecha_culminacion
    ren_if FECHADELIQUIDACIÓN             fecha_liquidacion
    ren_if FECHADERECEPCIÓNDEOBRA         fecha_recepcion
    ren_if NOMBREIE                       nombre_ie

    * PEIP / CONTINGENCIA
    ren_if CantidaddemódulosPRONIED       cantidad_modulos_pronied
    ren_if CantidaddemódulosPEIP          cantidad_modulos_peip
    ren_if Añodeinstalacióndelosmódulo    ano_instalacion_modulos

    * PEIP / MANTENIMIENTO - alcance / plan
    ren_if CuentaconPlanoManualdeMa       cuenta_plan_mantenimiento
    ren_if AlcancedelPlanoManualMan       alcance_plan_mantenimiento
    ren_if AñodelaentregadelPEIP          ano_entrega_peip
    ren_if Fechadeiniciodelmantenimien    fecha_inicio_mantenimiento
    ren_if Fechadeculminacióndemantenim   fecha_culminacion_mantenimiento

    * Conservar codigos de columna unica que no son junk
    ren_if Programa                       programa
    ren_if PROGRAMA                       programa
end


* ----- post_clean : limpieza final comun por base ---------------------------
* Aplica despues de los renames manuales. Se encarga de:
*   - limpiar strings (trim, missings)
*   - limpiar codigos (cui, codigo_local, codigo_modular, codigos_modulares)
*   - parsear fechas (cualquier var que empiece con fecha_)
*   - coercion numerica de monto_inversion, devengado, avance_*
*   - formatos
*   - order canonico
capture program drop post_clean
program define post_clean
    * Recuperar nombres desde labels en vars con nombre-letra (A, B, G, ...)
    rename_from_label

    * Reaplicar diccionario (por si el rename_from_label expuso nombres nuevos)
    canon_rename

    * Strings
    quietly ds, has(type string)
    foreach v in `r(varlist)' {
        quietly replace `v' = subinstr(`v', char(10), " ", .)
        quietly replace `v' = subinstr(`v', char(13), " ", .)
        quietly replace `v' = subinstr(`v', char(9),  " ", .)
        quietly replace `v' = strtrim(stritrim(`v'))
        quietly replace `v' = "" if inlist(ustrlower(`v'), ///
            "-","--","---","----","-----","------","n/a","na","n.a.") ///
            | inlist(ustrlower(`v'), "nan","none","null",".","..","s/d","s/i")
    }

    * Filas 100% vacias
    tempvar hasdata
    quietly gen byte `hasdata' = 0
    quietly ds
    foreach v in `r(varlist)' {
        capture confirm string variable `v'
        if !_rc quietly replace `hasdata' = 1 if `v' != ""
        else    quietly replace `hasdata' = 1 if !missing(`v')
    }
    quietly drop if `hasdata' == 0

    * Codigos
    foreach c in codigo_local {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(6)
    }
    foreach c in codigo_modular codigos_modulares {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(7)
    }
    foreach c in cui {
        capture confirm variable `c'
        if !_rc clean_code `c', digits(7)
    }

    * Fechas (protegido: ds fecha* falla si ninguna variable matchea)
    capture ds fecha*, has(type string)
    if !_rc & `"`r(varlist)'"' != "" {
        foreach v in `r(varlist)' {
            clean_date `v'
        }
    }

    * Numericos
    foreach v in monto_inversion devengado avance_fisico avance_financiero avance_diseno {
        capture confirm variable `v'
        if !_rc {
            capture confirm string variable `v'
            if !_rc destring `v', replace force
        }
    }

    * Formatos
    capture confirm numeric variable monto_inversion
    if !_rc format monto_inversion %15.2fc
    capture confirm numeric variable devengado
    if !_rc format devengado %15.2fc
    foreach v in avance_fisico avance_financiero avance_diseno {
        capture confirm numeric variable `v'
        if !_rc format `v' %6.4f
    }

    * Orden canonico
    local front "cui cui_snip cui_idea codigo_local codigo_modular codigos_modulares nombre_ie nombre_inversion nombre_corto nombre_peip departamento provincia distrito estado fase_obra etapa_obra etapa_intervencion tipo_inversion tipo_intervencion tipo_mantenimiento tipo_sistema_modular monto_inversion devengado avance_fisico avance_financiero avance_diseno fecha_inicio fecha_culminacion fecha_recepcion fecha_entrega fecha_inauguracion fecha_liquidacion comentario_general"
    local ord ""
    foreach v of local front {
        capture confirm variable `v'
        if !_rc local ord "`ord' `v'"
    }
    if "`ord'" != "" order `ord'
end


*============================================================================
* PASO 1 - Importar cada Excel, renombrar/limpiar y guardar .dta
*============================================================================

* ---------- ANIN / Anexo 1 --------------------------------------------------
import excel "${Input}/ANIN.xlsx", sheet("Anexo 1") cellrange(A3) firstrow ///
    allstring clear

capture rename CUIÍDEA                     CUI
capture rename CulminadosEntregadosFecha   DETALLE

* DETALLE + COMENTARIO -> COMENTARIO_GENERAL
gen COMENTARIO_GENERAL = DETALLE
replace COMENTARIO_GENERAL = COMENTARIO if missing(DETALLE) | DETALLE == ""
replace COMENTARIO_GENERAL = DETALLE + " | " + COMENTARIO ///
    if !missing(DETALLE) & DETALLE != "" & !missing(COMENTARIO) & COMENTARIO != ""
drop DETALLE COMENTARIO

canon_rename
rename COMENTARIO_GENERAL comentario_general

post_clean
duplicates drop cui, force
save "${Output}/ANIN.dta", replace
di as res "ANIN: " _N " obs"


* ---------- PEIP / IMPLEMENTADOS --------------------------------------------
import excel "${Input}/PEIP.xlsx", sheet("IMPLEMENTADOS") cellrange(A3) firstrow ///
    allstring clear

capture drop N
capture drop PQT

canon_rename
post_clean
duplicates drop cui codigo_local, force
save "${Output}/PEIP_IMPLEMENTADOS.dta", replace
di as res "PEIP_IMPLEMENTADOS: " _N " obs"


* ---------- PEIP / CONTINGENCIA ---------------------------------------------
import excel "${Input}/PEIP.xlsx", sheet("CONTINGENCIA") cellrange(A3) firstrow ///
    allstring clear

capture drop N

* Quitar duplicados 100% identicos (llave + cantidades)
duplicates drop CUI CódigoLocal NombredelPEIP Tipodesistemamodular ///
    CantidaddemódulosPRONIED CantidaddemódulosPEIP ///
    Añodeinstalacióndelosmódulo, force

* Sumar cantidades a nivel de la llave real
destring CantidaddemódulosPRONIED CantidaddemódulosPEIP, replace force
collapse (sum) CantidaddemódulosPRONIED CantidaddemódulosPEIP, ///
    by(CUI CódigoLocal NombredelPEIP Tipodesistemamodular Añodeinstalacióndelosmódulo)

rename CantidaddemódulosPRONIED cantidad_modulos_pronied
rename CantidaddemódulosPEIP    cantidad_modulos_peip
rename Añodeinstalacióndelosmódulo ano_instalacion_modulos

canon_rename
post_clean
save "${Output}/PEIP_CONTINGENCIA.dta", replace
di as res "PEIP_CONTINGENCIA: " _N " obs"


* ---------- PEIP / MANTENIMIENTO --------------------------------------------
* Stata trunca a 32 chars las cabeceras; al haber 4 columnas repetidas por
* categoria (rutinario, preventivo, correctivo) las siguientes se nombran
* con la letra de columna de Excel. Renombramos manualmente a <tipo>_<ano>.
import excel "${Input}/PEIP.xlsx", sheet("MANTENIMIENTO") cellrange(A3) firstrow ///
    allstring clear

capture drop N

* rutinario (col F-I)
capture rename Montoanualdemantenimientorec monto_rutinario_2025
capture rename G monto_rutinario_2026
capture rename H monto_rutinario_2027
capture rename I monto_rutinario_2028
* preventivo (col J-M)
capture rename Montoanualdemantenimientopre monto_preventivo_2025
capture rename K monto_preventivo_2026
capture rename L monto_preventivo_2027
capture rename M monto_preventivo_2028
* correctivo (col N-Q)
capture rename Montoanualdemantenimientocor monto_correctivo_2025
capture rename O monto_correctivo_2026
capture rename P monto_correctivo_2027
capture rename Q monto_correctivo_2028

destring monto_*, replace force

canon_rename
post_clean
duplicates drop
save "${Output}/PEIP_MANTENIMIENTO.dta", replace
di as res "PEIP_MANTENIMIENTO: " _N " obs"


* ---------- UGRD / PIRCC ----------------------------------------------------
import excel "${Input}/UGRD.xlsx", sheet("PIRCC") cellrange(A3) firstrow ///
    allstring clear

capture drop N
duplicates drop

canon_rename
post_clean
save "${Output}/UGRD_PIRCC.dta", replace
di as res "UGRD_PIRCC: " _N " obs"


* ---------- UGRD / MBR ------------------------------------------------------
import excel "${Input}/UGRD.xlsx", sheet("MBR") cellrange(A3) firstrow ///
    allstring clear

capture drop N
duplicates drop

* Homogeneizar etiquetas de Fase de la obra
capture replace Fasedelaobra = "OBRA CULMINADA-FUNCIONAMIENTO"   if Fasedelaobra == "15. OBRA CULMINADA"
capture replace Fasedelaobra = "EJECUCION CONTRACTUAL-EJECUCION" if Fasedelaobra == "14. EN EJECUCIÓN CONTRACTUAL"

canon_rename
post_clean
save "${Output}/UGRD_MBR.dta", replace
di as res "UGRD_MBR: " _N " obs"


* ---------- UGRD / ME -------------------------------------------------------
import excel "${Input}/UGRD.xlsx", sheet("ME") cellrange(A3) firstrow ///
    allstring clear

capture drop N
duplicates drop

canon_rename
post_clean
save "${Output}/UGRD_ME.dta", replace
di as res "UGRD_ME: " _N " obs"


* ---------- UGEO ------------------------------------------------------------
import excel "${Input}/UGEO.xlsx", sheet("UGEO") cellrange(A3) firstrow ///
    allstring clear

capture drop N
* columnas basura del final (vacias). drop por letra de columna
foreach L in R S T U V {
    capture drop `L'
}

duplicates drop

canon_rename
post_clean
save "${Output}/UGEO.dta", replace
di as res "UGEO: " _N " obs"


* ---------- UE118 / PMESUT --------------------------------------------------
import excel "${Input}/UE118.xlsx", sheet("PMESUT") cellrange(A2) firstrow ///
    allstring clear

capture drop A                          /* primera columna vacia */
capture rename Programa programa

canon_rename
post_clean
duplicates drop
save "${Output}/UE118_PMESUT.dta", replace
di as res "UE118_PMESUT: " _N " obs"


* ---------- UE118 / PMESTP --------------------------------------------------
import excel "${Input}/UE118.xlsx", sheet("PMESTP") cellrange(A2) firstrow ///
    allstring clear

capture drop A
capture rename Programa programa

canon_rename
post_clean
duplicates drop
save "${Output}/UE118_PMESTP.dta", replace
di as res "UE118_PMESTP: " _N " obs"


* ---------- FONCODES / LE INTERVENIDOS 2017-2025 ----------------------------
import excel "${Input}/FONCODES.xlsx", sheet("LE_INTERVENIDOS_2017-2025") ///
    cellrange(A2) firstrow allstring clear

canon_rename
post_clean
duplicates drop
save "${Output}/FONCODES_LE_INTERVENIDOS.dta", replace
di as res "FONCODES_LE_INTERVENIDOS: " _N " obs"


* ---------- FONCODES / MANT_2025 --------------------------------------------
import excel "${Input}/FONCODES.xlsx", sheet("REPORTE_MANT_ACOND_2025") ///
    cellrange(A2) firstrow allstring clear

capture drop N

canon_rename
post_clean
duplicates drop
save "${Output}/FONCODES_MANT_2025.dta", replace
di as res "FONCODES_MANT_2025: " _N " obs"


* ---------- FONCODES / MANT_2026 --------------------------------------------
import excel "${Input}/FONCODES.xlsx", sheet("REPORTE_MANT_ACOND_2026") ///
    cellrange(A2) firstrow allstring clear

capture drop N

canon_rename
post_clean
duplicates drop
save "${Output}/FONCODES_MANT_2026.dta", replace
di as res "FONCODES_MANT_2026: " _N " obs"


* ---------- MEF / Banco de Inversiones (auxiliar) ---------------------------
capture {
    import excel "${Input}/2026.04.13 Base de Inversiones.xlsx", sheet("Data") ///
        cellrange(A5) firstrow allstring clear

    * Nombres ya vienen en MAYUSCULAS snake-ish. Solo mapear lo basico.
    capture rename CODIGO_UNICO      cui
    capture rename CODIGO_SNIP       cui_snip
    capture rename CODIGO_IDEA       cui_idea
    capture rename NOMBRE_INVERSION  nombre_inversion
    capture rename DEPARTAMENTO_CUI  departamento
    capture rename PROVINCIA_CUI     provincia
    capture rename DISTRITO          distrito

    post_clean
    duplicates drop
    save "${Output}/MEF_Base_Inversiones.dta", replace
    di as res "MEF_Base_Inversiones: " _N " obs"
}


* ---------- CUI cartera GN (auxiliar) ---------------------------------------
capture {
    import excel "${Input}/CUI_cartera_GN.xlsx", sheet("Hoja1") firstrow ///
        allstring clear
    capture rename CUI cui
    post_clean
    duplicates drop
    save "${Output}/CUI_cartera_GN.dta", replace
    di as res "CUI_cartera_GN: " _N " obs"
}


*============================================================================
* PASO 2 - Consolidar por entidad (append con tag de origen)
*============================================================================

* --- PRONIED (UGEO + UGRD_*) -----------------------------------------------
capture {
    use "${Output}/UGEO.dta", clear
    gen unidad = "UGEO"
    append using "${Output}/UGRD_PIRCC.dta"
    replace unidad = "UGRD_PIRCC" if missing(unidad)
    append using "${Output}/UGRD_MBR.dta"
    replace unidad = "UGRD_MBR" if missing(unidad)
    append using "${Output}/UGRD_ME.dta"
    replace unidad = "UGRD_ME" if missing(unidad)
    order unidad, first
    save "${Output}/PRONIED.dta", replace
    di as res "PRONIED consolidado: " _N " obs"
}

* --- PEIP -------------------------------------------------------------------
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

* --- UE118 ------------------------------------------------------------------
capture {
    use "${Output}/UE118_PMESUT.dta", clear
    gen programa_ue = "PMESUT"
    append using "${Output}/UE118_PMESTP.dta"
    replace programa_ue = "PMESTP" if missing(programa_ue)
    order programa_ue, first
    save "${Output}/UE118.dta", replace
    di as res "UE118 consolidado: " _N " obs"
}

* --- FONCODES ---------------------------------------------------------------
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


di _newline(2) as res "===== LISTO ====="
di as txt "Bases .dta en: ${Output}"
di as txt "Entidades PRONIED pendientes: UGSC, UGME, UGM, Uzonal."
