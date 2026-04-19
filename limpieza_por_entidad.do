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


* ----- to_lower_ascii -------------------------------------------------------
* Fuerza TODAS las variables a nombres en minusculas ASCII, sin tildes,
* sin espacios ni caracteres especiales. Se ejecuta al final, despues de
* canon_rename, para uniformar cualquier nombre que haya quedado con
* tildes/MAYUSCULAS/CamelCase.
capture program drop to_lower_ascii
program define to_lower_ascii
    quietly ds
    local oldvars `r(varlist)'
    local used ""
    foreach v of local oldvars {
        local nn = ustrlower(ustrnormalize("`v'", "nfd"))
        local nn = ustrregexra("`nn'", "\p{Mn}", "")
        local nn = ustrregexra("`nn'", "[^a-z0-9_]+", "_")
        local nn = ustrregexra("`nn'", "_+", "_")
        local nn = ustrregexra("`nn'", "^_+|_+$", "")
        if "`nn'" == "" local nn "col"
        if regexm("`nn'", "^[0-9]") local nn "v_`nn'"
        local nn = substr("`nn'", 1, 32)
        local base "`nn'"
        local i = 1
        while strpos(" `used' ", " `nn' ") > 0 {
            local suf = "_`i'"
            local nn = substr("`base'", 1, 32 - strlen("`suf'")) + "`suf'"
            local ++i
        }
        if "`nn'" != "`v'" capture rename `v' `nn'
        local used "`used' `nn'"
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
    ren_if CuentaconPlanoManualdeMantenimie cuenta_plan_mantenimiento
    ren_if AlcancedelPlanoManualMan       alcance_plan_mantenimiento
    ren_if AlcancedelPlanoManualMantenimien alcance_plan_mantenimiento
    ren_if ALCANCEActivosintervenidosequipa alcance_activos
    ren_if AñodelaentregadelPEIP          ano_entrega_peip
    ren_if Fechadeiniciodelmantenimien    fecha_inicio_mantenimiento
    ren_if Fechadeiniciodelmantenimientooes fecha_inicio_mantenimiento
    ren_if Fechadeculminacióndemantenim   fecha_culminacion_mantenimiento
    ren_if Fechadeculminacióndemantenimient fecha_culminacion_mantenimiento

    * PEIP / MANTENIMIENTO - montos duplicados: Stata 15 usa letra de col Excel
    * cuando la cabecera truncada colisiona. Otras versiones usan sufijo numerico.
    * Cubrimos ambas variantes con ren_if (solo se ejecuta si existe).
    * Rutinario
    ren_if Montoanualdemantenimientorecurre monto_rutinario_2025
    ren_if Montoanualdemantenimientorec    monto_rutinario_2025
    ren_if Montoanualdemantenimientorecur1 monto_rutinario_2026
    ren_if G                               monto_rutinario_2026
    ren_if Montoanualdemantenimientorecur2 monto_rutinario_2027
    ren_if H                               monto_rutinario_2027
    ren_if Montoanualdemantenimientorecur3 monto_rutinario_2028
    ren_if I                               monto_rutinario_2028
    * Preventivo
    ren_if Montoanualdemantenimientoprevent monto_preventivo_2025
    ren_if Montoanualdemantenimientopre    monto_preventivo_2025
    ren_if Montoanualdemantenimientopreve1 monto_preventivo_2026
    ren_if K                               monto_preventivo_2026
    ren_if Montoanualdemantenimientopreve2 monto_preventivo_2027
    ren_if L                               monto_preventivo_2027
    ren_if Montoanualdemantenimientopreve3 monto_preventivo_2028
    ren_if M                               monto_preventivo_2028
    * Correctivo
    ren_if Montoanualdemantenimientocorrect monto_correctivo_2025
    ren_if Montoanualdemantenimientocor    monto_correctivo_2025
    ren_if Montoanualdemantenimientocorre1 monto_correctivo_2026
    ren_if O                               monto_correctivo_2026
    ren_if Montoanualdemantenimientocorre2 monto_correctivo_2027
    ren_if P                               monto_correctivo_2027
    ren_if Montoanualdemantenimientocorre3 monto_correctivo_2028
    ren_if Q                               monto_correctivo_2028

    * Conservar codigos de columna unica que no son junk
    ren_if Programa                       programa
    ren_if PROGRAMA                       programa

    * --- ANIN (nuevas hojas IRI / MANTENIMIENTO) ---
    ren_if CUIIRI                         cui
    ren_if NombredelIRI                   nombre_inversion
    ren_if MontoDevengado                 devengado
    ren_if Montodelainversiónactualizado  monto_inversion
    ren_if Montodelaintervencióntotal     monto_inversion
    ren_if Montodelaintervencion2025      monto_intervencion_2025
    ren_if Montodelaintervencion2026      monto_intervencion_2026
    ren_if Montodelaintervencion2027      monto_intervencion_2027
    ren_if Montodelaintervencion2028      monto_intervencion_2028
    ren_if Montodelaintervención2025      monto_intervencion_2025
    ren_if Montodelaintervención2026      monto_intervencion_2026
    ren_if Montodelaintervención2027      monto_intervencion_2027
    ren_if Montodelaintervención2028      monto_intervencion_2028
    ren_if AñodelaentregadelaIRI          ano_entrega
    ren_if Activointervenidoequipamientoedu activo_intervenido
    ren_if Activointervenidoequipa        activo_intervenido
    ren_if Tipodemantenimientoaejecutardeac tipo_mantenimiento
    ren_if Tipodemantenimientoaeje        tipo_mantenimiento

    * --- Variables de UGSC / UGME / UGM / UZ ---------------------------------
    ren_if Cantidaddelocaleseducativos    cantidad_locales
    ren_if Cantidaddelocaleseducativ      cantidad_locales
    ren_if Periodoinicial                 periodo_inicial
    ren_if Periodofinalactual             periodo_final
    ren_if Fechadeaprobacióndelet         fecha_aprobacion_et
    ren_if FechadeaprobacióndelET         fecha_aprobacion_et
    ren_if FechadeaprobaciónET            fecha_aprobacion_et
    ren_if FechadecaducidaddelET          fecha_caducidad_et
    ren_if Fechadecaducidaddelet          fecha_caducidad_et

    * UGSC
    ren_if Cantidaddelocaleseducativosinter cantidad_locales
    ren_if EstadoAdmitidoContinuidadCulmina estado
    ren_if EtapaCostosCulminadoEspecialidad etapa_obra
    ren_if FechadeaprobacióndelExpedienteTé fecha_aprobacion_et
    ren_if FechadecaducidaddelET          fecha_caducidad_et
    ren_if Añodelaprimeratransferencia    ano_primera_transferencia
    ren_if Añodelaúltimatransferencia     ano_ultima_transferencia
    ren_if Documentodelatransferenciaagrega doc_transferencia
    ren_if EstadodelproyectodeinversiónPIen estado
    ren_if MontodeInversiónS              monto_inversion
    ren_if TransferenciatotalS            monto_transferido

    * UE118
    ren_if Códigodellocaleducativo        codigo_local
    ren_if CódigoÚnicodeInversionesCUI    cui
    ren_if NombrelargoPI                  nombre_inversion
    ren_if NombrecortoPI                  nombre_corto
    ren_if Estadodelaintervención         estado
    ren_if MontototaldeinversiónS         monto_inversion
    ren_if Riesgosoalertasidentificadas   riesgos
    ren_if Medidasdeacciónopropuestasdeinte medidas_accion
    ren_if Fechaestimada                  fecha_estimada

    * FONCODES
    ren_if CódigodelLocalEducativo        codigo_local
    ren_if CódigoÚnicodeInversionesCUI    cui
    ren_if NombredelProyecto              nombre_inversion
    ren_if TipodelaInversión              tipo_inversion
    ren_if EstadodelaInversión            estado
    ren_if MontodelaInversiónSoles        monto_inversion
    ren_if AvanceFísico                   avance_fisico
    ren_if FechadeIniciodeObra            fecha_inicio
    ren_if FechadeCulminacióndeObra       fecha_culminacion
    ren_if FechadeLiquidación             fecha_liquidacion
    ren_if FechadeRecepcióndeObra         fecha_recepcion
    ren_if CODIGOMODULAR                  codigo_modular
    ren_if CODMODULAR                     codigo_modular
    ren_if NOMBREIE                       nombre_ie
    ren_if TIPODEMANTENIMIENTO            tipo_mantenimiento
    ren_if MONTODELAINTERVENCIÓN2025      monto_inversion
    ren_if MONTODELAINTERVENCIÓN2026      monto_inversion
    ren_if ESTADOPROYECTO                 estado
    ren_if FECHADEINICIO                  fecha_inicio
    ren_if FECHADECULMINACIÓN             fecha_culminacion
    ren_if FECHADECULMINACIONESTIMADA     fecha_culminacion

    * UGME
    ren_if Códigomodular                  codigo_modular
    ren_if GrupoAulaDomoAulaModularEscuelaM grupo_bien
    ren_if GrupoMobiliarioEquipamiento    grupo_bien
    ren_if Grupo                          grupo_bien
    ren_if AulaDomoAulaMo                 grupo_bien
    ren_if Descripcióndelbien             descripcion_bien
    ren_if LOCALESEDUCATIVOS              nombre_ie
    ren_if LocalEscolar                   nombre_ie
    ren_if Fechadeentregaoestim           fecha_entrega
    ren_if Capacidadoperativasolo         capacidad_operativa
    ren_if MontocontractualS              monto_inversion
    ren_if Montocontractual               monto_inversion
    ren_if Totaldebienes                  total_bienes
    ren_if Fasedelproceso                 fase_obra
    ren_if Etapadelproceso                etapa_obra

    * UGME extras
    ren_if FechadeentregaoestimadaPECOSA  fecha_entrega
    ren_if EstadoInstaladoDonadoetc       estado
    ren_if EstadoNoiniciadoenprocesoculmina estado
    ren_if CapacidadoperativasoloEscuelaMod capacidad_operativa
    ren_if MontocontractualS              monto_inversion

    * UGM
    ren_if Año                            anio
    ren_if AÑODEINSTALACIÓN               ano_instalacion
    ren_if Tipodeintervenciónmantenimientoc tipo_intervencion
    ren_if Tipodeintervenciónman          tipo_intervencion
    ren_if Fechaestimadadeentrega         fecha_entrega
    ren_if MontoasignadoparamantenimientoS monto_asignado
    ren_if Montoasignadopara              monto_asignado
    ren_if MontoasignadototalS            monto_asignado_total
    ren_if Montoasignadototal             monto_asignado_total
    ren_if MontotransferidoS              monto_transferido
    ren_if Montotransferido               monto_transferido
    ren_if Montoasignadopararutassolidarias monto_rutas_acceso
    ren_if Montoasignadopararutas         monto_rutas_acceso
    ren_if EstadodelaFichadeAccionesdeMante estado_ficha
    ren_if EstadodelaFichadeAccionesdeAcond estado_ficha
    ren_if EstadodelaFichadeAcc           estado_ficha
    ren_if MontototaldelaFAM              monto_total_fam
    ren_if MontototaldelaFAA              monto_total_faa
    ren_if EstadodelaDeclaracióndeGastosDG estado_declaracion_gasto
    ren_if MontototaldelaDG               monto_total_dg
    ren_if Códigosmodularesdellocaleducativ codigos_modulares
    ren_if Códigosmodularesdelloc         codigos_modulares
    ren_if Codigosmodularesdelloc         codigos_modulares

    * UZ
    ren_if Códigolocal                    codigo_local
    ren_if NombredelaUnidadZonal          unidad_zonal
    ren_if NombreUnidadZonal              unidad_zonal
    ren_if Fechadeinspección              fecha_inspeccion
    ren_if Especialistaquerealiza         especialista
    ren_if SolicitudSGDCorreou            solicitud
    ren_if Númeroydenominacióndel         numero_denominacion
    ren_if Enlacedelinforme               enlace_informe
    ren_if UnidaduOficinadelPRON          unidad_pronied
    ren_if NiveldeGobiernoGobier          nivel_gobierno
    ren_if TipodeentidadGRMPMD            tipo_entidad
    ren_if Nombredeentidad                nombre_entidad
    ren_if Númerodeparticipantes          cantidad_participantes
    ren_if TemaFortalecimiento            tema
    ren_if Títulodelasesoramiento         titulo_asesoramiento
    ren_if Fecha                          fecha_evento

    * --- MEF / Banco de Inversiones: variables clave para cruce -------------
    ren_if CODIGO_INVERSION               codigo_inversion
    ren_if CODIGO_SNIP                    cui_snip
    ren_if CODIGO_UNICO                   cui
    ren_if CODIGO_IDEA                    cui_idea
    ren_if NOMBRE_INVERSION               nombre_inversion
    ren_if DES_TIPO_FORMATO               des_tipo_formato
    ren_if TIPO_IOARR                     tipo_ioarr
    ren_if ESTADO                         estado_bi
    ren_if SITUACION                      situacion
    ren_if MARCO                          marco
    ren_if DEPARTAMENTO_CUI               departamento
    ren_if DEPARTAMENTO_PROXY             departamento_proxy
    ren_if PROVINCIA_CUI                  provincia
    ren_if DISTRITO                       distrito
    ren_if NIVEL                          nivel_gobierno
    ren_if SECTOR                         sector
    ren_if COD_SECTOR                     cod_sector
    ren_if PLIEGO                         pliego
    ren_if COD_PLIEGO                     cod_pliego
    ren_if UEP_ULTIMA                     unidad_ejecutora
    ren_if UEP_PRINCIPAL                  unidad_ejecutora_principal
    ren_if COD_SEC_EJEC_UEP_ULT           cod_sec_ejec
    ren_if UF                             uf
    ren_if UEI                            uei
    ren_if OPMI                           opmi
    ren_if FUNCION                        funcion
    ren_if PROGRAMA                       programa
    ren_if SUB_PROGRAMA                   sub_programa
    ren_if FECHA_REGISTRO                 fecha_registro
    ren_if FECHA_VIABILIDAD               fecha_viabilidad
    ren_if MONTO_ALTE                     monto_alterno
    ren_if MONTO_LAUDO                    monto_laudo
    ren_if COSTO_ACTUALIZADO_BI           costo_actualizado_bi
    ren_if COSTO_INV_TOTAL_BI             monto_inversion
    ren_if COSTO_INV_TOTAL_PMI            costo_total_pmi
    ren_if TIENE_ET_DE                    tiene_et
    ren_if FECHA_ET_DE                    fecha_inicio_et
    ren_if ULT_MODIF_ET_DE                fecha_fin_et
    ren_if FEC_INI_F8                     fecha_inicio_f8
    ren_if FEC_FIN_F8                     fecha_fin_f8
    ren_if AVANCE_FISICO_F12B             avance_fisico_bi
    ren_if AVANCE_EJECUCION_F12B          avance_financiero_bi
    ren_if DEV_ACUM_ANO_ACTUAL            devengado
    ren_if PIM_SIAF                       pim
    ren_if PIA_SIAF                       pia
    ren_if MONTO_PIM_BI                   pim_bi
    ren_if MONTO_PIA_BI                   pia_bi
    ren_if CARTERA_PMI                    cartera_pmi
    ren_if CICLO_INVERSION_PMI            ciclo_inversion
    ren_if ORDEN_PRELACION_PMI            orden_prelacion
    ren_if DES_BRECHA                     brecha
    ren_if DES_SERVICIO                   servicio
    ren_if FECHA_ACTUALIZACION            fecha_actualizacion_bi
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

    * Minuscula ASCII para TODAS las variables que hayan quedado con tildes
    * o MAYUSCULAS despues del diccionario.
    to_lower_ascii

    * Orden canonico
    local front "cui cui_snip cui_idea codigo_local codigo_modular codigos_modulares nombre_ie nombre_inversion nombre_corto nombre_peip departamento provincia distrito ubigeo sector pliego unidad_ejecutora uf uei opmi estado estado_bi situacion fase_obra etapa_obra etapa_intervencion tipo_inversion tipo_intervencion tipo_mantenimiento tipo_sistema_modular monto_inversion costo_actualizado_bi devengado pim pia cartera_pmi avance_fisico avance_financiero avance_diseno avance_fisico_bi fecha_inicio fecha_culminacion fecha_recepcion fecha_entrega fecha_inauguracion fecha_liquidacion fecha_inicio_et fecha_fin_et comentario_general"
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

* ---------- ANIN / IRI (Inversiones en Rehabilitacion de Infraestructura) ----
import excel "${Input}/ANIN.xlsx", sheet("IRI") cellrange(A3) firstrow ///
    allstring clear

capture drop N
duplicates drop

canon_rename
post_clean
duplicates drop cui, force
save "${Output}/ANIN_IRI.dta", replace
di as res "ANIN_IRI: " _N " obs"


* ---------- ANIN / MANTENIMIENTO --------------------------------------------
capture {
    import excel "${Input}/ANIN.xlsx", sheet("MANTENIMIENTO") cellrange(A2) ///
        firstrow allstring clear
    capture drop N
    duplicates drop

    canon_rename
    post_clean
    save "${Output}/ANIN_MANTENIMIENTO.dta", replace
    di as res "ANIN_MANTENIMIENTO: " _N " obs"
}


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

* Los renames de montos duplicados estan en canon_rename (cubre tanto
* letra de columna como sufijo numerico segun version de Stata).
canon_rename
post_clean
destring monto_*, replace force
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


* ---------- UGSC / ASITEC-SIAT ----------------------------------------------
capture {
    import excel "${Input}/UGSC.xlsx", sheet("ASITEC-SIAT") cellrange(A3) ///
        firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGSC_ASITEC.dta", replace
    di as res "UGSC_ASITEC: " _N " obs"
}


* ---------- UGSC / SEGUIMIENTO PI FINANCIADOS -------------------------------
capture {
    import excel "${Input}/UGSC.xlsx", sheet("SEGUIMIENTO DE PI FINANCIADOS ") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGSC_SEGUIMIENTO.dta", replace
    di as res "UGSC_SEGUIMIENTO: " _N " obs"
}


* ---------- UGME / SISTEMAS MODULARES ---------------------------------------
capture {
    import excel "${Input}/UGME.xlsx", sheet("SISTEMAS MODULARES") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGME_SISTEMAS_MODULARES.dta", replace
    di as res "UGME_SISTEMAS_MODULARES: " _N " obs"
}


* ---------- UGME / MOBILIARIO Y EQUIPAMIENTO --------------------------------
capture {
    import excel "${Input}/UGME.xlsx", sheet("MOBILIARIO Y EQUIPAMIENTO") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGME_MOBILIARIO.dta", replace
    di as res "UGME_MOBILIARIO: " _N " obs"
}


* ---------- UGME / PLAN DE CONSERVACION MODULAR -----------------------------
capture {
    import excel "${Input}/UGME.xlsx", sheet("PLAN DE CONSERVACIÓN MODULAR") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGME_PLAN_CONSERVACION.dta", replace
    di as res "UGME_PLAN_CONSERVACION: " _N " obs"
}


* ---------- UGM / ACONDICIONAMIENTO -----------------------------------------
capture {
    import excel "${Input}/UGM.xlsx", sheet("ACONDICIONAMIENTO") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGM_ACONDICIONAMIENTO.dta", replace
    di as res "UGM_ACONDICIONAMIENTO: " _N " obs"
}


* ---------- UGM / MANTENIMIENTO 2025 ----------------------------------------
* OJO: header real esta en fila 4 porque fila 3 tiene agrupadores ("Detalle FAM").
capture {
    import excel "${Input}/UGM.xlsx", sheet("MANTENIMIENTO 2025") ///
        cellrange(A4) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGM_MANTENIMIENTO_2025.dta", replace
    di as res "UGM_MANTENIMIENTO_2025: " _N " obs"
}


* ---------- UGM / MANTENIMIENTO 2026 ----------------------------------------
capture {
    import excel "${Input}/UGM.xlsx", sheet("MANTENIMIENTO 2026") ///
        cellrange(A4) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UGM_MANTENIMIENTO_2026.dta", replace
    di as res "UGM_MANTENIMIENTO_2026: " _N " obs"
}


* ---------- UGM / ACCESIBILIDAD (10 hojas por ano de convocatoria) ----------
* Se procesan 2017-2 a 2026-2; header real en fila 4.
foreach anio in 2017 2018 2019 2020 2021 2022 2023 2024 2025 2026 {
    capture {
        import excel "${Input}/UGM.xlsx", sheet("ACCESIBILIDAD `anio'-2") ///
            cellrange(A4) firstrow allstring clear
        capture drop N
        duplicates drop
        canon_rename
        post_clean
        save "${Output}/UGM_ACCESIBILIDAD_`anio'.dta", replace
        di as res "UGM_ACCESIBILIDAD_`anio': " _N " obs"
    }
}


* ---------- UZ (Zonales) / INSPECCIONES -------------------------------------
capture {
    import excel "${Input}/2026.03.30 Zonales_UZ.xlsx" , sheet("INSPECCIONES") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UZ_INSPECCIONES.dta", replace
    di as res "UZ_INSPECCIONES: " _N " obs"
}


* ---------- UZ (Zonales) / ASESORAMIENTO ------------------------------------
capture {
    import excel "${Input}/2026.03.30 Zonales_UZ.xlsx", sheet("ASESORAMIENTO") ///
        cellrange(A3) firstrow allstring clear
    capture drop N
    duplicates drop
    canon_rename
    post_clean
    save "${Output}/UZ_ASESORAMIENTO.dta", replace
    di as res "UZ_ASESORAMIENTO: " _N " obs"
}


* ---------- UE118 / PMESUT --------------------------------------------------
import excel "${Input}/UE118.xlsx", sheet("PMESUT") cellrange(A2) firstrow ///
    allstring clear

* primera columna vacia (Stata la llama A, Unnamed0, o col)
foreach x in A Unnamed0 col {
    capture drop `x'
}

canon_rename
post_clean
duplicates drop
save "${Output}/UE118_PMESUT.dta", replace
di as res "UE118_PMESUT: " _N " obs"


* ---------- UE118 / PMESTP --------------------------------------------------
import excel "${Input}/UE118.xlsx", sheet("PMESTP") cellrange(A2) firstrow ///
    allstring clear

foreach x in A Unnamed0 col {
    capture drop `x'
}

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
* Si ya existe la .dta, la abre directamente (mucho mas rapido que importar
* el Excel de 136 columnas cada vez). Solo importa de Excel la primera vez.
capture {
    capture confirm file "${Output}/MEF_Base_Inversiones.dta"
    if _rc {
        * Primera vez: importar desde Excel y limpiar
        import excel "${Input}/2026.04.13 Base de Inversiones.xlsx", sheet("Data") ///
            cellrange(A5) firstrow allstring clear
        canon_rename
        post_clean
        duplicates drop
        save "${Output}/MEF_Base_Inversiones.dta", replace
        di as res "MEF_Base_Inversiones: importado de Excel -> " _N " obs"
    }
    else {
        use "${Output}/MEF_Base_Inversiones.dta", clear
        di as res "MEF_Base_Inversiones: cargado de .dta -> " _N " obs"
    }
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

* --- PRONIED (UGEO + UGRD + UGSC + UGME + UGM + UZ) ------------------------
capture {
    local prnd_files UGEO UGRD_PIRCC UGRD_MBR UGRD_ME ///
        UGSC_ASITEC UGSC_SEGUIMIENTO ///
        UGME_SISTEMAS_MODULARES UGME_MOBILIARIO UGME_PLAN_CONSERVACION ///
        UGM_ACONDICIONAMIENTO UGM_MANTENIMIENTO_2025 UGM_MANTENIMIENTO_2026 ///
        UGM_ACCESIBILIDAD_2017 UGM_ACCESIBILIDAD_2018 UGM_ACCESIBILIDAD_2019 ///
        UGM_ACCESIBILIDAD_2020 UGM_ACCESIBILIDAD_2021 UGM_ACCESIBILIDAD_2022 ///
        UGM_ACCESIBILIDAD_2023 UGM_ACCESIBILIDAD_2024 UGM_ACCESIBILIDAD_2025 ///
        UGM_ACCESIBILIDAD_2026 ///
        UZ_INSPECCIONES UZ_ASESORAMIENTO

    clear
    tempfile acc
    save `acc', emptyok
    foreach f of local prnd_files {
        capture use "${Output}/`f'.dta", clear
        if _rc continue
        gen unidad = "`f'"
        append using `acc'
        save `acc', replace
    }
    use `acc', clear
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


*============================================================================
* PASO 3 - BASE_PANORAMA: consolidada a nivel de intervencion/local.
*   - De cada .dta limpia extrae solo las variables canonicas clave.
*   - Append con etiquetas (entidad, unidad).
*   - Merge con MEF Banco de Inversiones para enriquecer geografia
*     (departamento, provincia, distrito), unidad ejecutora, UF/OPMI,
*     costo actualizado, devengado, PIM, PIA, fechas del ET, situacion,
*     cartera PMI, funcion, sector, pliego.
*   - Guarda una .dta de panorama con pocas columnas pero consistentes.
*============================================================================

* Variables canonicas que se conservan en el panorama (si existen en la base).
* Si no existe en esa base, la crea como missing para que el append no explote.
capture program drop prep_panorama
program define prep_panorama
    * Llaves
    foreach v in cui codigo_local codigo_modular codigos_modulares {
        capture confirm variable `v'
        if _rc gen `v' = ""
        capture confirm string variable `v'
        if _rc tostring `v', replace force
    }
    * Identificacion
    foreach v in nombre_ie nombre_inversion nombre_corto {
        capture confirm variable `v'
        if _rc gen `v' = ""
        capture confirm string variable `v'
        if _rc tostring `v', replace force
    }
    * Geografia (desde la base original; se complementa luego con BI)
    foreach v in departamento provincia distrito ubigeo {
        capture confirm variable `v'
        if _rc gen `v' = ""
        capture confirm string variable `v'
        if _rc tostring `v', replace force
    }
    * Categoricas
    foreach v in estado fase_obra etapa_obra situacion ///
                 tipo_inversion tipo_intervencion tipo_mantenimiento ///
                 tipo_sistema_modular unidad_zonal comentario_general {
        capture confirm variable `v'
        if _rc gen `v' = ""
        capture confirm string variable `v'
        if _rc tostring `v', replace force
    }
    * Numericas (montos y avances)
    foreach v in monto_inversion monto_asignado_total monto_transferido ///
                 monto_total_fam monto_total_faa monto_total_dg ///
                 devengado pim pia costo_actualizado_bi ///
                 avance_fisico avance_financiero ///
                 cantidad_modulos_pronied cantidad_modulos_peip ///
                 total_bienes capacidad_operativa {
        capture confirm variable `v'
        if _rc gen double `v' = .
        capture confirm numeric variable `v'
        if _rc destring `v', replace force
    }
    * Fechas
    foreach v in fecha_inicio fecha_culminacion fecha_entrega ///
                 fecha_recepcion fecha_inauguracion fecha_liquidacion ///
                 fecha_inicio_et fecha_fin_et fecha_inspeccion fecha_evento {
        capture confirm variable `v'
        if _rc gen `v' = .
        capture confirm numeric variable `v'
        if _rc {
            capture gen double __tmp = daily(`v', "YMD") if `v' != ""
            capture replace __tmp = daily(`v', "DMY") if missing(__tmp) & `v' != ""
            drop `v'
            rename __tmp `v'
        }
        format `v' %td
    }

    * Quedate solo con las vars canonicas + entidad/unidad
    keep cui codigo_local codigo_modular codigos_modulares ///
         nombre_ie nombre_inversion nombre_corto ///
         departamento provincia distrito ubigeo ///
         estado fase_obra etapa_obra situacion ///
         tipo_inversion tipo_intervencion tipo_mantenimiento ///
         tipo_sistema_modular unidad_zonal ///
         monto_inversion monto_asignado_total monto_transferido ///
         monto_total_fam monto_total_faa monto_total_dg ///
         devengado pim pia costo_actualizado_bi ///
         avance_fisico avance_financiero ///
         cantidad_modulos_pronied cantidad_modulos_peip ///
         total_bienes capacidad_operativa ///
         fecha_inicio fecha_culminacion fecha_entrega ///
         fecha_recepcion fecha_inauguracion fecha_liquidacion ///
         fecha_inicio_et fecha_fin_et fecha_inspeccion fecha_evento ///
         comentario_general
end


clear
tempfile panorama
save `panorama', emptyok replace

* Mapa entidad -> lista de archivos
local M_PRONIED   UGEO UGRD_PIRCC UGRD_MBR UGRD_ME ///
                  UGSC_ASITEC UGSC_SEGUIMIENTO ///
                  UGME_SISTEMAS_MODULARES UGME_MOBILIARIO UGME_PLAN_CONSERVACION ///
                  UGM_ACONDICIONAMIENTO UGM_MANTENIMIENTO_2025 UGM_MANTENIMIENTO_2026 ///
                  UGM_ACCESIBILIDAD_2017 UGM_ACCESIBILIDAD_2018 UGM_ACCESIBILIDAD_2019 ///
                  UGM_ACCESIBILIDAD_2020 UGM_ACCESIBILIDAD_2021 UGM_ACCESIBILIDAD_2022 ///
                  UGM_ACCESIBILIDAD_2023 UGM_ACCESIBILIDAD_2024 UGM_ACCESIBILIDAD_2025 ///
                  UGM_ACCESIBILIDAD_2026 ///
                  UZ_INSPECCIONES UZ_ASESORAMIENTO
local M_PEIP      PEIP_IMPLEMENTADOS PEIP_CONTINGENCIA PEIP_MANTENIMIENTO
local M_UE118     UE118_PMESUT UE118_PMESTP
local M_ANIN      ANIN_IRI ANIN_MANTENIMIENTO
local M_FONCODES  FONCODES_LE_INTERVENIDOS FONCODES_MANT_2025 FONCODES_MANT_2026

foreach ent in PRONIED PEIP UE118 ANIN FONCODES {
    foreach f of local M_`ent' {
        capture use "${Output}/`f'.dta", clear
        if _rc {
            di as txt "  (saltando `f' - no existe)"
            continue
        }
        prep_panorama
        gen entidad = "`ent'"
        gen unidad  = "`f'"
        append using `panorama'
        save `panorama', replace
        di as txt "  + `f': " _N " acumulados"
    }
}

use `panorama', clear

* --- Merge con MEF Banco de Inversiones para enriquecer -----------------
capture confirm file "${Output}/MEF_Base_Inversiones.dta"
if !_rc {
    preserve
    use "${Output}/MEF_Base_Inversiones.dta", clear
    * Solo quedarnos con las vars que necesitamos para enriquecer
    capture keep cui departamento provincia distrito sector pliego ///
         unidad_ejecutora uf uei opmi ///
         costo_actualizado_bi devengado pim pia ///
         avance_fisico_bi avance_financiero_bi ///
         fecha_inicio_et fecha_fin_et ///
         situacion estado_bi cartera_pmi funcion nombre_inversion
    * Si el keep falla porque alguna var no existe, keep solo lo que haya
    if _rc {
        capture keep cui departamento provincia distrito uf opmi ///
            unidad_ejecutora pliego sector nombre_inversion
    }
    duplicates drop cui, force
    tempfile mef_bi
    save `mef_bi'
    restore

    * Renombrar del master para que el merge no pelee por vars iguales
    foreach v in departamento provincia distrito nombre_inversion ///
                 devengado pim pia situacion {
        capture rename `v' `v'_base
    }

    merge m:1 cui using `mef_bi', keep(master match) generate(_m_bi)

    label define m_bi 1 "solo_panorama" 3 "match_BI"
    label values _m_bi m_bi

    * Consolidar: si la base original tenia el dato, conservar; si no, usar BI
    foreach v in departamento provincia distrito nombre_inversion ///
                 devengado pim pia situacion {
        capture confirm variable `v'_base
        if _rc continue
        capture confirm variable `v'
        if _rc {
            rename `v'_base `v'
            continue
        }
        * Si la del base esta vacia o missing, usar la del BI
        capture confirm string variable `v'
        if !_rc {
            replace `v' = `v'_base if (`v' == "" | missing(`v')) & `v'_base != ""
        }
        else {
            replace `v' = `v'_base if missing(`v') & !missing(`v'_base)
        }
        drop `v'_base
    }
}

* Orden canonico
to_lower_ascii
capture order entidad unidad cui codigo_local codigo_modular ///
      nombre_ie nombre_inversion departamento provincia distrito ///
      estado situacion tipo_inversion tipo_intervencion tipo_mantenimiento ///
      monto_inversion devengado pim pia costo_actualizado_bi ///
      avance_fisico avance_financiero ///
      fecha_inicio fecha_culminacion fecha_entrega ///
      fecha_inicio_et fecha_fin_et ///
      unidad_ejecutora uf opmi sector pliego funcion

save "${Output}/BASE_PANORAMA.dta", replace
di as res _newline(1) "BASE_PANORAMA: " _N " obs, " c(k) " vars"

* Export a CSV para Power BI / Excel
export delimited using "${Output}/BASE_PANORAMA.csv", ///
    delimiter(",") quote replace
di as res "BASE_PANORAMA.csv exportado"


*============================================================================
* Resumen final por entidad
*============================================================================
capture use "${Output}/BASE_PANORAMA.dta", clear
if !_rc {
    di _newline(1) as txt "===== CONTEO POR ENTIDAD/UNIDAD ====="
    tab entidad unidad, missing
}

di _newline(2) as res "===== LISTO ====="
di as txt "Bases .dta en: ${Output}"
di as txt "BASE_PANORAMA.dta + BASE_PANORAMA.csv listos para el visor (Power BI)."
