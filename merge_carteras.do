********************************************************************************
* merge_carteras.do
* Consolidación de bases PEIP, ANIN, UGRD, UGEO contra CUI_cartera_GN en Stata.
*
* Lógica:
*   1) Lee los CUIs de cada hoja fuente (los encabezados están en la fila 3,
*      por eso usamos cellrange con "A3").
*   2) Deduplica CUIs dentro de cada fuente.
*   3) Concatena todas las fuentes y deduplica entre ellas; si un CUI aparece
*      en varias hojas, concatenamos las etiquetas con " | ".
*   4) Cruza con CUI_cartera_GN (CUI, cartera_gn): conserva los existentes con
*      su etiqueta original y agrega sólo los CUIs que NO estaban, con la
*      procedencia en la columna cartera_gn.
*   5) Exporta CUI_cartera_GN_consolidado.xlsx con las hojas Consolidado,
*      Solo_Nuevos y Todas_las_Fuentes.
********************************************************************************

version 15
clear all
set more off

* === Ajusta esta ruta a la carpeta donde están los archivos .xlsx ===
global RUTA "C:/ruta/a/los/archivos"
cd "$RUTA"

********************************************************************************
* Programa auxiliar: lee una hoja, toma la columna CUI indicada y etiqueta.
* Guarda un tempfile con variables: CUI (string) y cartera_gn (string).
* Uso: leer_cui, archivo("X.xlsx") hoja("H") colcui("CUI") etiqueta("...") ///
*               salida(tempname)
********************************************************************************
capture program drop leer_cui
program define leer_cui
    syntax , archivo(string) hoja(string) colcui(string) etiqueta(string) ///
             salida(string)

    clear
    * Los títulos ocupan las 2 primeras filas; encabezados reales en la 3.
    import excel using "`archivo'", sheet("`hoja'") cellrange(A3) firstrow ///
        allstring

    * Renombra la columna CUI (el nombre viene con caracteres raros a veces)
    capture confirm variable `colcui'
    if _rc {
        * Busca por etiqueta si el nombre no coincide textualmente
        ds, has(varlabel "`colcui'")
        local cvars `r(varlist)'
        local colcui : word 1 of `cvars'
    }
    rename `colcui' CUI

    * Limpieza: trim, quitar vacíos y basura
    replace CUI = strtrim(CUI)
    drop if missing(CUI) | inlist(CUI, "-", "—", ".", "nan", "NaN")

    * Si vienen como "2503451.0" (float) nos quedamos con la parte entera
    replace CUI = substr(CUI, 1, strpos(CUI, ".")-1) if strpos(CUI, ".")>0

    keep CUI
    gen cartera_gn = "`etiqueta'"

    * Deduplicación dentro de la fuente
    duplicates drop CUI, force

    display as text "  `archivo' / `hoja' -> " _N " CUIs únicos"
    save "`salida'", replace
end

********************************************************************************
* 1) Cargar cada fuente en un tempfile
********************************************************************************
tempfile t_anin t_peip_imp t_peip_con t_ugrd_pircc t_ugrd_mbr t_ugrd_me t_ugeo

display as result _n "Cargando fuentes:"
leer_cui, archivo("ANIN.xlsx") hoja("Anexo 1")       colcui("CUIIDEA") ///
          etiqueta("ANIN")                    salida("`t_anin'")
leer_cui, archivo("PEIP.xlsx") hoja("IMPLEMENTADOS") colcui("CUI") ///
          etiqueta("PEIP - IMPLEMENTADOS")   salida("`t_peip_imp'")
leer_cui, archivo("PEIP.xlsx") hoja("CONTINGENCIA")  colcui("CUI") ///
          etiqueta("PEIP - CONTINGENCIA")    salida("`t_peip_con'")
leer_cui, archivo("UGRD.xlsx") hoja("PIRCC")         colcui("CUI") ///
          etiqueta("UGRD - PIRCC")           salida("`t_ugrd_pircc'")
leer_cui, archivo("UGRD.xlsx") hoja("MBR")           colcui("CUI") ///
          etiqueta("UGRD - MBR")             salida("`t_ugrd_mbr'")
leer_cui, archivo("UGRD.xlsx") hoja("ME")            colcui("CUI") ///
          etiqueta("UGRD - ME")              salida("`t_ugrd_me'")
leer_cui, archivo("UGEO.xlsx") hoja("UGEO")          colcui("CUI") ///
          etiqueta("UGEO - Obra Pública")    salida("`t_ugeo'")

********************************************************************************
* 2) Unir todas las fuentes y deduplicar entre ellas
*    (si un CUI está en varias hojas, concatenamos etiquetas con " | ")
********************************************************************************
use "`t_anin'", clear
append using "`t_peip_imp'"
append using "`t_peip_con'"
append using "`t_ugrd_pircc'"
append using "`t_ugrd_mbr'"
append using "`t_ugrd_me'"
append using "`t_ugeo'"

* Eliminamos duplicados exactos CUI+etiqueta
duplicates drop CUI cartera_gn, force

* Concatenamos etiquetas por CUI
bysort CUI (cartera_gn): gen _etq = cartera_gn
bysort CUI (cartera_gn): replace _etq = _etq[_n-1] + " | " + cartera_gn if _n>1
bysort CUI (cartera_gn): keep if _n == _N
drop cartera_gn
rename _etq cartera_gn

tempfile t_fuentes
save "`t_fuentes'", replace
display as result _n "Total de CUIs únicos aportados por las fuentes: " _N

********************************************************************************
* 3) Leer CUI_cartera_GN y dejar sólo CUIs nuevos que NO están ahí
********************************************************************************
clear
import excel using "CUI_cartera_GN.xlsx", sheet("Hoja1") firstrow allstring
replace CUI = strtrim(CUI)
replace CUI = substr(CUI, 1, strpos(CUI, ".")-1) if strpos(CUI, ".")>0
drop if missing(CUI)
duplicates drop CUI, force
display as result "CUI_cartera_GN inicial: " _N " registros únicos"

tempfile t_base
save "`t_base'", replace

* Marcar cuáles de las fuentes ya existían
use "`t_fuentes'", clear
merge 1:1 CUI using "`t_base'", keepusing(CUI) generate(_existe)
keep if _existe == 1   // sólo en fuentes, no en base -> son los NUEVOS a agregar
drop _existe
tempfile t_nuevos
save "`t_nuevos'", replace
display as result "CUIs nuevos a agregar (no estaban en CUI_cartera_GN): " _N

********************************************************************************
* 4) Consolidado final = base original + nuevos
********************************************************************************
use "`t_base'", clear
append using "`t_nuevos'"
duplicates drop CUI, force
order CUI cartera_gn
display as result _n "Total final en Consolidado: " _N " CUIs"

* Exportar hoja Consolidado (sobrescribe el archivo si existe)
export excel using "CUI_cartera_GN_consolidado.xlsx", ///
    sheet("Consolidado") sheetreplace firstrow(variables)

* Exportar hoja Solo_Nuevos
use "`t_nuevos'", clear
order CUI cartera_gn
export excel using "CUI_cartera_GN_consolidado.xlsx", ///
    sheet("Solo_Nuevos") sheetreplace firstrow(variables)

* Exportar hoja Todas_las_Fuentes
use "`t_fuentes'", clear
order CUI cartera_gn
export excel using "CUI_cartera_GN_consolidado.xlsx", ///
    sheet("Todas_las_Fuentes") sheetreplace firstrow(variables)

display as result _n "Archivo generado: CUI_cartera_GN_consolidado.xlsx"
