# Reporte de limpieza y conversion Excel -> DTA

| Dataset | Archivo | Hoja | Filas raw | Filas limpias | Dup. eliminados | Llaves (dup. encontrados) | Salida |
|---|---|---|---:|---:|---:|---|---|
| PRONIED_UGEO | UGEO.xlsx | UGEO | 57 | 57 | 0 | `cui`(7), `codigo_local`(7) | dta/PRONIED_UGEO.dta |
| PRONIED_UGRD_PIRCC | UGRD.xlsx | PIRCC | 180 | 180 | 0 | `codigo_local`(18), `cui`(19) | dta/PRONIED_UGRD_PIRCC.dta |
| PRONIED_UGRD_MBR | UGRD.xlsx | MBR | 60 | 60 | 0 | `cui`(0), `codigo_local`(0) | dta/PRONIED_UGRD_MBR.dta |
| PRONIED_UGRD_ME | UGRD.xlsx | ME | 517 | 517 | 0 | `cui`(361), `codigo_local`(250) | dta/PRONIED_UGRD_ME.dta |
| PEIP_IMPLEMENTADOS | PEIP.xlsx | IMPLEMENTADOS | 92 | 92 | 0 | `cui`(0), `codigo_local`(0) | dta/PEIP_IMPLEMENTADOS.dta |
| PEIP_CONTINGENCIA | PEIP.xlsx | CONTINGENCIA | 119 | 119 | 0 | `cui`(34), `codigo_local`(33) | dta/PEIP_CONTINGENCIA.dta |
| PEIP_MANTENIMIENTO | PEIP.xlsx | MANTENIMIENTO | 27 | 27 | 0 | `codigo_local`(1) | dta/PEIP_MANTENIMIENTO.dta |
| ANIN_Anexo1 | ANIN.xlsx | Anexo 1 | 76 | 76 | 0 | `cui_idea`(0) | dta/ANIN_Anexo1.dta |
| CUI_cartera_GN | CUI_cartera_GN.xlsx | Hoja1 | 1232 | 1232 | 0 | `cui`(0) | dta/CUI_cartera_GN.dta |

## Notas
- Llaves detectadas automaticamente por coincidencia con pistas: `cui`, `codigo_unico`, `codigo_snip`, `codigo_idea`, `codigo_inversion`, `codigo_local`, `cod_local`, `codigo_modular`, `cod_modular`, `cod_mod`.
- Los numeros entre parentesis al lado de cada llave son **valores duplicados** (no filas duplicadas) en esa columna. Si son > 0, la llave por si sola no es unica -> considerar una llave compuesta.
- Valores tratados como missing: `-`, `--`, `---`, `----`, `-----`, `------`, `-------`, `-.`, `.`, `.-`, `..`, `n.a.`, `n/a`, `na`, `nan`, `none`, `null`, `s/d`, `s/i`.
- Formato .dta: version 118 (Stata 14+), soporta Unicode y variables <=32 chars.

## Entidades pendientes de PRONIED
Falta entregar las bases de UGSC, UGME, UGM y Uzonal para consolidar PRONIED como una sola base por entidad.