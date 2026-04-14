*! clean_excel_to_dta.do
*! --------------------------------------------------------------------------
*! Convierte los Excel de cada entidad (PRONIED, PEIP, UE118, ANIN, FONCODES,
*! MEF Banco de Inversiones, CUI_cartera_GN) a formato .dta, con limpieza:
*!
*!   - Normaliza nombres de variables: minuscula, sin tildes, sin caracteres
*!     especiales, snake_case, maximo 32 chars, sin colisiones.
*!   - Limpia strings: strtrim + stritrim, elimina saltos de linea.
*!   - Convierte "-", "---", "N/A", "s/d", etc. en missing ("").
*!   - Elimina filas 100% vacias.
*!   - Elimina duplicados exactos.
*!   - Convierte a numerico cuando >=80% de valores no vacios son numeros.
*!   - Reporta llaves candidatas (CUI, codigo_local, codigo_modular, etc.) y
*!     cuantos valores duplicados tienen.
*!
*! Requiere Stata 14 o superior (por Unicode y ustrregexra).
*! Uso:   do clean_excel_to_dta.do
*! --------------------------------------------------------------------------

version 14
clear all
set more off

* Carpeta de trabajo = carpeta donde esta el .do (ajustar si es necesario)
* cd "`c(pwd)'"
capture mkdir "dta"


*===========================================================================
* Programa clean_one: procesa una hoja y la guarda como .dta
*===========================================================================
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

    * -------- 2. RENOMBRAR VARIABLES -----------------------------------
    * Stata convierte la primera fila a nombres validos; el texto original
    * queda como "variable label". Reconstruimos snake_case ASCII desde el
    * label. Primero renombramos a nombres temporales __v1, __v2... para
    * poder asignar libremente sin colisiones.
    quietly ds
    local oldvars `r(varlist)'
    local n_old : word count `oldvars'
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
        local nn = ustrregexra("`nn'", "\p{Mn}", "")          // quita tildes
        local nn = ustrregexra("`nn'", "[^a-z0-9]+", "_")     // no alfanum -> _
        local nn = ustrregexra("`nn'", "^_+|_+$", "")         // recorta _
        if "`nn'" == "" local nn "col"
        if regexm("`nn'", "^[0-9]") local nn "v_`nn'"
        local nn = substr("`nn'", 1, 32)
        * desambiguar
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

    * -------- 3. LIMPIAR STRINGS ---------------------------------------
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

    * -------- 4. ELIMINAR FILAS 100% VACIAS ----------------------------
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

    * -------- 5. COERCION A NUMERICO -----------------------------------
    * Si >=80% de los valores no-vacios de una var string parsean a numero,
    * la reemplazamos por su version numerica.
    quietly ds, has(type string)
    foreach v in `r(varlist)' {
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

    * -------- 6. DUPLICADOS EXACTOS ------------------------------------
    quietly duplicates drop
    local N1 = _N
    di as txt "  filas raw/limpias: " as res "`N0' -> `N1'" ///
        as txt "  (duplicados/vacias removidas: " `N0' - `N1' ")"

    * -------- 7. DETECTAR LLAVES CANDIDATAS ----------------------------
    local keyvars ""
    quietly ds
    foreach v in `r(varlist)' {
        foreach h in cui codigo_unico codigo_snip codigo_idea ///
                     codigo_inversion codigo_local cod_local ///
                     codigo_modular cod_modular cod_mod {
            if strpos("`v'", "`h'") > 0 {
                local keyvars "`keyvars' `v'"
                continue, break
            }
        }
    }
    if "`keyvars'" == "" {
        di as txt "  llaves candidatas: (ninguna detectada)"
    }
    else {
        di as txt "  llaves candidatas:"
        foreach k of local keyvars {
            tempvar tag
            quietly duplicates tag `k', gen(`tag')
            capture confirm string variable `k'
            if !_rc {
                quietly count if `tag' > 0 & `k' != ""
            }
            else {
                quietly count if `tag' > 0 & !missing(`k')
            }
            di as txt "    - " as res "`k'" as txt ///
                ": " r(N) " obs. con valor duplicado"
            drop `tag'
        }
    }

    * -------- 8. GUARDAR -----------------------------------------------
    save "dta/`prefix'.dta", replace
    di as txt "  -> " as res "dta/`prefix'.dta"
end


*===========================================================================
* Ejecutar para cada (archivo, hoja, fila_encabezado_1based, prefijo)
*===========================================================================
* Nota: row() es la fila del encabezado en Excel contando desde 1.

* PRONIED - UGEO
clean_one, file("UGEO.xlsx") sheet("UGEO") row(3) prefix("PRONIED_UGEO")

* PRONIED - UGRD
clean_one, file("UGRD.xlsx") sheet("PIRCC") row(3) prefix("PRONIED_UGRD_PIRCC")
clean_one, file("UGRD.xlsx") sheet("MBR")   row(3) prefix("PRONIED_UGRD_MBR")
clean_one, file("UGRD.xlsx") sheet("ME")    row(3) prefix("PRONIED_UGRD_ME")

* PEIP
clean_one, file("PEIP.xlsx") sheet("IMPLEMENTADOS")  row(3) prefix("PEIP_IMPLEMENTADOS")
clean_one, file("PEIP.xlsx") sheet("CONTINGENCIA")   row(3) prefix("PEIP_CONTINGENCIA")
clean_one, file("PEIP.xlsx") sheet("MANTENIMIENTO")  row(3) prefix("PEIP_MANTENIMIENTO")

* UE118
clean_one, file("UE118.xlsx") sheet("PMESUT") row(2) prefix("UE118_PMESUT")
clean_one, file("UE118.xlsx") sheet("PMESTP") row(2) prefix("UE118_PMESTP")

* ANIN
clean_one, file("ANIN.xlsx") sheet("Anexo 1") row(3) prefix("ANIN_Anexo1")

* FONCODES
clean_one, file("FONCODES.xlsx") sheet("LE_INTERVENIDOS_2017-2025") row(2) prefix("FONCODES_LE_INTERVENIDOS")
clean_one, file("FONCODES.xlsx") sheet("REPORTE_MANT_ACOND_2025")   row(2) prefix("FONCODES_MANT_2025")
clean_one, file("FONCODES.xlsx") sheet("REPORTE_MANT_ACOND_2026")   row(2) prefix("FONCODES_MANT_2026")

* MEF Banco de Inversiones (auxiliar)
clean_one, file("2026.04.13 Base de Inversiones.xlsx") sheet("Data") row(5) prefix("MEF_Base_Inversiones")

* Tabla auxiliar
clean_one, file("CUI_cartera_GN.xlsx") sheet("Hoja1") row(1) prefix("CUI_cartera_GN")


di _newline(2) as res "Listo. Los .dta estan en la carpeta ./dta/"
di as txt "Entidades PRONIED pendientes (cuando lleguen los Excel):"
di as txt "  UGSC, UGME, UGM, Uzonal -> agregar sus 'clean_one' arriba."

* --------------------------------------------------------------------------
* Sugerencias de llaves compuestas (segun el analisis inicial en Python):
*   PRONIED_UGRD_ME         : cui + codigo_local + componente
*   PRONIED_UGRD_PIRCC      : cui + codigo_local + tipo_intervencion
*   PRONIED_UGEO            : cui + codigo_local
*   PEIP_CONTINGENCIA       : cui + codigo_local + tipo_sistema_modular
* Verificarlas en Stata con:
*   use "dta/PRONIED_UGRD_ME.dta", clear
*   duplicates report cui codigo_local componente
* --------------------------------------------------------------------------
