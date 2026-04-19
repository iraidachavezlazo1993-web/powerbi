# Diccionario de variables — BASE_PANORAMA.dta

Generado por `limpieza_por_entidad.do`. BASE_PANORAMA consolida todas las
entidades (PRONIED, PEIP, UE118, ANIN, FONCODES) en una sola .dta, enriquecida
con datos del MEF Banco de Inversiones, Vinculaciones y Locales Educativos.

## Etiquetas de origen

| Variable | Descripcion |
|---|---|
| `entidad` | PRONIED, PEIP, UE118, ANIN, FONCODES |
| `unidad` | Hoja/reporte de origen (UGEO, UGRD_MBR, PEIP_IMPLEMENTADOS, etc.) |
| `tipo_intervencion_gral` | Clasificacion general: PROYECTO, MANTENIMIENTO, ACONDICIONAMIENTO, ACCESIBILIDAD, MODULOS, MOBILIARIO/EQUIPAMIENTO, ASISTENCIA TECNICA, INSPECCION, ASESORAMIENTO |

## Llaves

| Variable | Tipo | Largo | Fuente |
|---|---|---|---|
| `cui` | string | 7 digitos | Codigo Unico de Inversiones (MEF) |
| `codigo_local` | string | 6 digitos | Codigo del local educativo (MINEDU) |
| `codigo_modular` | string | 7 digitos | Codigo modular de la IE |
| `codigos_modulares` | string | 7 dig / 7 dig ... | Multiples codigos modulares separados por "/" |

## Identificacion

| Variable | Tipo | Fuente |
|---|---|---|
| `nombre_ie` | string | Nombre de la IE (de la base o de Vinculaciones) |
| `nombre_inversion` | string | Nombre del proyecto/inversion (de la base o del MEF BI) |
| `nombre_corto` | string | Nombre corto del PI |
| `nombre_iiee_local` | string | Nombre concatenado de las IIEE del local (de Locales Educativos) |
| `nivel_modalidad` | string | Nivel o modalidad de la IE (de Vinculaciones: Inicial, Primaria, Secundaria, etc.) |

## Geografia

| Variable | Tipo | Fuente |
|---|---|---|
| `departamento` | string | Region/departamento. Se enriquece: base -> MEF BI -> Locales Educativos |
| `provincia` | string | Idem |
| `distrito` | string | Idem |
| `ubigeo` | string | Codigo de ubigeo (6 digitos, de Locales Educativos) |
| `centro_poblado` | string | Centro poblado (de Locales Educativos) |
| `dre` | string | Direccion Regional de Educacion |
| `ugel` | string | Unidad de Gestion Educativa Local |
| `area_censal` | string | Urbano / Rural (de Locales Educativos) |
| `latitud` | numeric | Coordenada (de Locales Educativos) |
| `longitud` | numeric | Coordenada (de Locales Educativos) |

## Estado y clasificacion

| Variable | Tipo | Fuente |
|---|---|---|
| `estado` | string | Estado de la intervencion (de la base) |
| `estado_ie` | string | Estado de la IE: Activo/Inactivo (de Vinculaciones) |
| `estado_bi` | string | Estado en el MEF Banco de Inversiones |
| `situacion` | string | Situacion en BI (Viable, Aprobado, etc.) |
| `fase_obra` | string | Fase de la obra (Preinversion, Ejecucion, Culminada) |
| `etapa_obra` | string | Etapa dentro de la fase |
| `tipo_inversion` | string | PI Regular / IOARR / OxI |
| `tipo_intervencion` | string | MBR / ME / mantenimiento correctivo, etc. |
| `tipo_mantenimiento` | string | Preventivo, Correctivo, etc. |
| `tipo_sistema_modular` | string | Prefabricado, etc. |
| `unidad_zonal` | string | Nombre de la unidad zonal PRONIED |

## Montos y ejecucion (numerico, formato %15.2fc)

| Variable | Fuente |
|---|---|
| `monto_inversion` | Monto de inversion de la base original |
| `monto_asignado_total` | Monto asignado total (UGM mantenimiento/accesibilidad) |
| `monto_transferido` | Monto transferido (UGM / UGSC) |
| `monto_total_fam` | Monto total FAM - Ficha de Acciones de Mantenimiento |
| `monto_total_faa` | Monto total FAA - Ficha de Acciones de Accesibilidad |
| `monto_total_dg` | Monto total Declaracion de Gastos |
| `devengado` | Devengado acumulado (de la base o del MEF BI) |
| `pim` | Presupuesto Institucional Modificado (del MEF BI) |
| `pia` | Presupuesto Institucional de Apertura (del MEF BI) |
| `costo_actualizado_bi` | Costo actualizado en el Banco de Inversiones |

## Avance (numerico, formato %6.4f)

| Variable | Fuente |
|---|---|
| `avance_fisico` | Avance fisico (%) de la base |
| `avance_financiero` | Avance financiero (%) de la base |

## Conteos

| Variable | Fuente |
|---|---|
| `cantidad_modulos_pronied` | Cantidad de modulos PRONIED (PEIP Contingencia) |
| `cantidad_modulos_peip` | Cantidad de modulos PEIP (PEIP Contingencia) |
| `total_bienes` | Total de bienes (UGME) |
| `capacidad_operativa` | Capacidad operativa en estudiantes |
| `matricula` | Matricula de la IE (de Locales Educativos) |

## Fechas (formato %td)

| Variable | Fuente |
|---|---|
| `fecha_inicio` | Fecha de inicio de la obra |
| `fecha_culminacion` | Fecha de culminacion |
| `fecha_entrega` | Fecha de entrega |
| `fecha_recepcion` | Fecha de recepcion |
| `fecha_inauguracion` | Fecha de inauguracion |
| `fecha_liquidacion` | Fecha de liquidacion |
| `fecha_inicio_et` | Fecha de inicio del Expediente Tecnico (MEF BI) |
| `fecha_fin_et` | Fecha de fin/modificacion del ET (MEF BI) |
| `fecha_inspeccion` | Fecha de inspeccion (UZ) |
| `fecha_evento` | Fecha del evento/asesoramiento (UZ) |

## Institucional (del MEF Banco de Inversiones)

| Variable | Fuente |
|---|---|
| `unidad_ejecutora` | Unidad Ejecutora del Pliego (UEP) |
| `uf` | Unidad Formuladora |
| `uei` | Unidad Ejecutora de Inversiones |
| `opmi` | Oficina de Programacion Multianual de Inversiones |
| `sector` | Sector (Educacion, etc.) |
| `pliego` | Pliego presupuestal |
| `funcion` | Funcion presupuestal (Educacion, etc.) |
| `cartera_pmi` | En cartera PMI (Si/No) |

## Servicios basicos (de Locales Educativos)

| Variable | Valores |
|---|---|
| `agua_acceso` | SI / NO |
| `saneamiento_acceso` | SI / NO |
| `energia_acceso` | SI / NO |
| `internet_acceso` | SI / NO |

## Variables de control del merge

| Variable | Valores |
|---|---|
| `_m_bi` | 1 = sin match en MEF BI, 3 = enriquecido con BI |
| `_m_vinc` | 1 = sin match en Vinculaciones, 3 = enriquecido |
| `_m_le` | 1 = sin match en Locales Educativos, 3 = enriquecido |

## Fuentes de datos

| Archivo | Hojas | Nivel |
|---|---|---|
| UGEO.xlsx | UGEO | CUI + codigo_local |
| UGRD.xlsx | PIRCC, MBR, ME | CUI + codigo_local |
| UGSC.xlsx | ASITEC-SIAT, SEGUIMIENTO PI | CUI |
| UGME.xlsx | SISTEMAS MODULARES, MOBILIARIO, CONSERVACION | codigo_local + codigo_modular |
| UGM.xlsx | ACONDICIONAMIENTO, MANT 2025/2026, ACCESIBILIDAD 2017-2026 | codigo_local |
| Zonales_UZ.xlsx | INSPECCIONES, ASESORAMIENTO | codigo_local |
| PEIP.xlsx | IMPLEMENTADOS, CONTINGENCIA, MANTENIMIENTO | CUI + codigo_local |
| UE118.xlsx | PMESUT, PMESTP | CUI |
| ANIN.xlsx | IRI, MANTENIMIENTO | CUI + codigo_local |
| FONCODES.xlsx | LE_INTERVENIDOS, MANT 2025/2026 | CUI o codigo_modular |
| Vinculaciones_compartido.xlsx | Vinculaciones | CUI -> codigo_local/modular |
| Locales educativos - Servicios basicos.xlsx | BaseLE | codigo_local |
| 2026.04.13 Base de Inversiones.xlsx | Data | CUI |
| CUI_cartera_GN.xlsx | Hoja1 | CUI |

## Tipo de intervencion general (clasificacion)

| Valor | Unidades incluidas |
|---|---|
| PROYECTO | UGEO, UGRD_MBR, UGRD_ME, UGRD_PIRCC, UGSC_SEGUIMIENTO, ANIN_IRI, PEIP_IMPLEMENTADOS, UE118_PMESUT, UE118_PMESTP, FONCODES_LE_INTERVENIDOS |
| MANTENIMIENTO | UGM_MANTENIMIENTO_2025/2026, PEIP_MANTENIMIENTO, ANIN_MANTENIMIENTO, FONCODES_MANT_2025/2026 |
| ACONDICIONAMIENTO | UGM_ACONDICIONAMIENTO |
| ACCESIBILIDAD | UGM_ACCESIBILIDAD_2017 a 2026 |
| MODULOS | UGME_SISTEMAS_MODULARES, UGME_PLAN_CONSERVACION, PEIP_CONTINGENCIA |
| MOBILIARIO/EQUIPAMIENTO | UGME_MOBILIARIO |
| ASISTENCIA TECNICA | UGSC_ASITEC |
| INSPECCION | UZ_INSPECCIONES |
| ASESORAMIENTO | UZ_ASESORAMIENTO |
