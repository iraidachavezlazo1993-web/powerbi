********************************************************************************
* merge_carteras.do
* Consolidación de bases PEIP, ANIN, UGRD, UGEO contra CUI_cartera_GN.
*
* Flujo:
*   1) Importa cada hoja de Excel y la guarda como .dta en ${Output}.
*   2) Con los .dta ya guardados, deduplica dentro de cada fuente, une todas
*      las fuentes, deduplica entre ellas concatenando etiquetas.
*   3) Cruza con CUI_cartera_GN y conserva sólo los CUIs que NO estaban,
*      agregándolos con su procedencia en la columna cartera_gn.
*   4) Exporta CUI_cartera_GN_consolidado.xlsx (hojas Consolidado,
*      Solo_Nuevos, Todas_las_Fuentes).
********************************************************************************

version 15
clear all
set more off

* === Rutas ===
global Input  "C:/ruta/a/los/excels"
global Output "C:/ruta/a/los/dta"

cap mkdir "${Output}"

********************************************************************************
* PASO 1 — Importar cada Excel y guardarlo como .dta
********************************************************************************

* ---------- ANIN / Anexo 1 ----------
import excel "${Input}/ANIN.xlsx", sheet("Anexo 1") cellrange(A3) firstrow ///
    allstring clear
rename CUIIDEA CUI
keep CUI
gen cartera_gn = "ANIN"
save "${Output}/ANIN.dta", replace

* ---------- PEIP / IMPLEMENTADOS ----------
import excel "${Input}/PEIP.xlsx", sheet("IMPLEMENTADOS") cellrange(A3) firstrow ///
    allstring clear
keep CUI
gen cartera_gn = "PEIP - IMPLEMENTADOS"
save "${Output}/PEIP_IMPLEMENTADOS.dta", replace

* ---------- PEIP / CONTINGENCIA ----------
import excel "${Input}/PEIP.xlsx", sheet("CONTINGENCIA") cellrange(A3) firstrow ///
    allstring clear
keep CUI
gen cartera_gn = "PEIP - CONTINGENCIA"
save "${Output}/PEIP_CONTINGENCIA.dta", replace

* ---------- UGRD / PIRCC ----------
import excel "${Input}/UGRD.xlsx", sheet("PIRCC") cellrange(A3) firstrow ///
    allstring clear
keep CUI
gen cartera_gn = "UGRD - PIRCC"
save "${Output}/UGRD_PIRCC.dta", replace

* ---------- UGRD / MBR ----------
import excel "${Input}/UGRD.xlsx", sheet("MBR") cellrange(A3) firstrow ///
    allstring clear
keep CUI
gen cartera_gn = "UGRD - MBR"
save "${Output}/UGRD_MBR.dta", replace

* ---------- UGRD / ME ----------
import excel "${Input}/UGRD.xlsx", sheet("ME") cellrange(A3) firstrow ///
    allstring clear
keep CUI
gen cartera_gn = "UGRD - ME"
save "${Output}/UGRD_ME.dta", replace

* ---------- UGEO / UGEO ----------
import excel "${Input}/UGEO.xlsx", sheet("UGEO") cellrange(A3) firstrow ///
    allstring clear
keep CUI
gen cartera_gn = "UGEO - Obra Pública"
save "${Output}/UGEO.dta", replace

* ---------- CUI_cartera_GN (base existente) ----------
import excel "${Input}/CUI_cartera_GN.xlsx", sheet("Hoja1") firstrow ///
    allstring clear
save "${Output}/CUI_cartera_GN.dta", replace


********************************************************************************
* PASO 2 — Limpieza y deduplicación dentro de cada .dta
********************************************************************************

foreach f in ANIN PEIP_IMPLEMENTADOS PEIP_CONTINGENCIA ///
             UGRD_PIRCC UGRD_MBR UGRD_ME UGEO CUI_cartera_GN {

    use "${Output}/`f'.dta", clear
    replace CUI = strtrim(CUI)
    * Si viene como "2503451.0" nos quedamos con la parte entera
    replace CUI = substr(CUI, 1, strpos(CUI, ".")-1) if strpos(CUI, ".")>0
    drop if missing(CUI) | inlist(CUI, "-", "—", ".", "nan", "NaN")
    duplicates drop CUI, force
    save "${Output}/`f'.dta", replace
    display as result "  `f'.dta -> " _N " CUIs únicos"
}


********************************************************************************
* PASO 3 — Unir todas las fuentes y deduplicar entre ellas
*   (si un CUI aparece en varias hojas, concatenamos etiquetas con " | ")
********************************************************************************

use "${Output}/ANIN.dta", clear
append using "${Output}/PEIP_IMPLEMENTADOS.dta"
append using "${Output}/PEIP_CONTINGENCIA.dta"
append using "${Output}/UGRD_PIRCC.dta"
append using "${Output}/UGRD_MBR.dta"
append using "${Output}/UGRD_ME.dta"
append using "${Output}/UGEO.dta"

duplicates drop CUI cartera_gn, force

bysort CUI (cartera_gn): gen _etq = cartera_gn
bysort CUI (cartera_gn): replace _etq = _etq[_n-1] + " | " + cartera_gn if _n>1
bysort CUI (cartera_gn): keep if _n == _N
drop cartera_gn
rename _etq cartera_gn

save "${Output}/Todas_las_Fuentes.dta", replace
display as result _n "Total CUIs únicos aportados por las fuentes: " _N


********************************************************************************
* PASO 4 — Cruce con CUI_cartera_GN: quedarnos sólo con los CUIs NUEVOS
********************************************************************************

merge 1:1 CUI using "${Output}/CUI_cartera_GN.dta", keepusing(CUI) generate(_existe)
keep if _existe == 1         // 1 = sólo en fuentes (no estaba en la base)
drop _existe
save "${Output}/Solo_Nuevos.dta", replace
display as result "CUIs nuevos a agregar: " _N


********************************************************************************
* PASO 5 — Consolidado final = base original + nuevos
********************************************************************************

use "${Output}/CUI_cartera_GN.dta", clear
append using "${Output}/Solo_Nuevos.dta"
duplicates drop CUI, force
order CUI cartera_gn
save "${Output}/CUI_cartera_GN_consolidado.dta", replace
display as result _n "Total final en Consolidado: " _N " CUIs"


********************************************************************************
* PASO 6 — Exportar a Excel (3 hojas)
********************************************************************************

use "${Output}/CUI_cartera_GN_consolidado.dta", clear
export excel using "${Output}/CUI_cartera_GN_consolidado.xlsx", ///
    sheet("Consolidado") sheetreplace firstrow(variables)

use "${Output}/Solo_Nuevos.dta", clear
order CUI cartera_gn
export excel using "${Output}/CUI_cartera_GN_consolidado.xlsx", ///
    sheet("Solo_Nuevos") sheetreplace firstrow(variables)

use "${Output}/Todas_las_Fuentes.dta", clear
order CUI cartera_gn
export excel using "${Output}/CUI_cartera_GN_consolidado.xlsx", ///
    sheet("Todas_las_Fuentes") sheetreplace firstrow(variables)

display as result _n "Archivo generado: ${Output}/CUI_cartera_GN_consolidado.xlsx"
