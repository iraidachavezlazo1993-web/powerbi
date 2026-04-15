# Diccionario comun de variables (post-limpieza)

Todas las bases generadas por `clean_excel_to_dta.do` usan estos nombres canonicos
cuando la variable existe. Cualquier sinonimo que aparezca en el Excel original se
renombra automaticamente al nombre canonico por la subrutina `apply_dictionary`.

## Llaves

| Variable canonica       | Tipo   | Formato / largo           | Sinonimos en Excel original |
|------------------------|--------|---------------------------|-----------------------------|
| `cui`                   | string | 7 digitos con ceros delante | CUI, CUI / IDEA, Codigo Unico de Inversiones (CUI), Codigo Unico, Codigo de la Inversion |
| `cui_snip`              | string | 7 digitos                 | Codigo SNIP |
| `cui_idea`              | string | 7 digitos                 | Codigo IDEA |
| `codigo_local`          | string | 6 digitos                 | Codigo Local, Cod. Local, Codigo del Local Educativo |
| `codigo_modular`        | string | 7 digitos                 | Codigo Modular, Cod. Modular, Cod. Mod. |
| `codigos_modulares`     | string | 7 digitos / 7 digitos ... | Codigos modulares intervenidos |
| `codigo_institucion`    | string | 8 digitos                 | Codigo de la institucion |

**Reglas de limpieza de codigos** (helper `clean_code`):

- Elimina espacios, corchetes `[]`, parentesis, llaves `{}`.
- Unifica separadores `;` `,` `\` `|` → `/`.
- Elimina sufijos tipo `-1`, `-A`, `-B2` (dash seguido de letra/numero).
- Elimina prefijos tipo `A-`, `AB-`.
- Descarta cualquier caracter no numerico (excepto `/`).
- Pad con ceros a la izquierda hasta el largo esperado.
- Ejemplos:
    - `"[123456]"`              → `"123456"`
    - `"123456-1"`               → `"123456"`
    - `"A-123456"`               → `"123456"`
    - `"123456 / 7890"`          → `"123456/0007890"` (si digits=6)
    - `"123456;7890"`            → `"123456/0007890"`

## Identificacion / descripcion

| Variable canonica   | Tipo   | Sinonimos |
|--------------------|--------|-----------|
| `nombre_ie`         | string | Nombre de la I.E., I.E. |
| `nombre_inversion`  | string | Nombre de la inversion, Nombre del proyecto, Nombre largo PI, Nombre del PEIP |
| `nombre_corto`      | string | Nombre corto, Nombre corto PI |
| `tipo_inversion`    | string | Tipo de inversion (PI Regular, IOARR), Tipo de la Inversion |
| `tipo_intervencion` | string | Tipo de intervencion (MBR o ME) |
| `tipo_mantenimiento`| string | Tipo de mantenimiento |
| `tipo_sistema_modular` | string | Tipo de sistema modular |

## Ubicacion

| Variable canonica | Sinonimos |
|-------------------|-----------|
| `departamento`     | Departamento, Departamento CUI, Departamento Proxy |
| `provincia`        | Provincia, Provincia CUI |
| `distrito`         | Distrito |

## Estado / avance

| Variable canonica    | Tipo    | Formato | Sinonimos |
|---------------------|---------|---------|-----------|
| `estado`             | string  | -       | Estado, Estado de la inversion, Estado de la intervencion, Estado proyecto |
| `fase_obra`          | string  | -       | Fase de la obra, Fase del componente |
| `etapa_obra`         | string  | -       | Etapa de la obra, Etapa del componente |
| `etapa_intervencion` | string  | -       | Etapa de la intervencion (Idea, Formulacion, ...) |
| `avance_fisico`      | numerico| %6.4f   | Avance fisico (%), % de avance fisico de obra, Avance |
| `avance_financiero`  | numerico| %6.4f   | Avance financiero (%) |
| `avance_diseno`      | numerico| %6.4f   | % de avance diseno |

## Montos

| Variable canonica | Tipo    | Formato   | Sinonimos |
|-------------------|---------|-----------|-----------|
| `monto_inversion`  | numerico| %15.2fc  | Monto de inversion (S/), Monto total de inversion (S/), Monto de la inversion (Soles), Monto de la intervencion 2025/2026, Costo actualizado |
| `devengado`        | numerico| %15.2fc  | Devengado acumulado |

## Fechas (formato Stata `%td`)

| Variable canonica    | Sinonimos |
|---------------------|-----------|
| `fecha_inicio`       | Fecha de inicio de la obra (o estimada), Fecha de inicio de obra, Fecha de inicio |
| `fecha_culminacion`  | Fecha de culminacion de obra (o estimada), Culminados/Entregados Fecha |
| `fecha_recepcion`    | Fecha de recepcion (o estimada), Fecha de recepcion de obra |
| `fecha_entrega`      | Fecha de entrega (o estimada), Fecha de entrega de obra |
| `fecha_inauguracion` | Fecha de inauguracion (o estimada) |

Las fechas se parsean probando en orden: `YMD hms`, `YMD`, `DMY`, `MDY`.
Solo se convierte la variable si >=80% de los valores no vacios parsean.

## Comentarios

| Variable canonica     | Sinonimos |
|----------------------|-----------|
| `comentario_general`  | Comentarios, Comentario, Comentarios (- Otras variables que quiera reportar...), "DETALLE + COMENTARIO" concatenados con ` \| ` |

## Variables especiales por entidad

Algunas bases tienen variables propias que no aparecen en otras:

- PEIP_CONTINGENCIA: `cantidad_de_modulos_pronied`, `cantidad_de_modulos_peip`, `ano_de_instalacion_de_los_modulo`.
- MEF_Base_Inversiones (Banco de Inversiones MEF): muchas columnas propias (PIM, PIA, devengado mensual, etc.) — se mantienen con su nombre normalizado.
- CUI_cartera_GN: solo `cui` + `cartera_gn`.

## Convenciones

- Strings: `strtrim(stritrim(.))` + reemplazo de tokens `-`, `---`, `N/A`, `s/d`, etc. por vacio.
- Strings a numerico: si `>=80%` de valores no vacios parsean con `real()`, se convierten.
- Strings a fecha: prueba YMD, DMY, MDY; convierte si `>=80%` parsea.
- Duplicados exactos: `duplicates drop` en cada base.
- Orden canonico: las variables clave (cui, codigo_local, nombre, estado, montos, fechas, comentario) se ponen adelante con `order`.

## Bases generadas

Por hoja (una por unidad/reporte):

- `PRONIED_UGEO.dta`, `PRONIED_UGRD_PIRCC.dta`, `PRONIED_UGRD_MBR.dta`, `PRONIED_UGRD_ME.dta`
- `PEIP_IMPLEMENTADOS.dta`, `PEIP_CONTINGENCIA.dta`, `PEIP_MANTENIMIENTO.dta`
- `UE118_PMESUT.dta`, `UE118_PMESTP.dta`
- `ANIN.dta`
- `FONCODES_LE_INTERVENIDOS.dta`, `FONCODES_MANT_2025.dta`, `FONCODES_MANT_2026.dta`
- `MEF_Base_Inversiones.dta`, `CUI_cartera_GN.dta`

Consolidadas por entidad (append con variable de origen):

- `PRONIED.dta` (con variable `unidad`: UGEO / UGRD_PIRCC / UGRD_MBR / UGRD_ME)
- `PEIP.dta` (con variable `tipo_reporte`: IMPLEMENTADOS / CONTINGENCIA / MANTENIMIENTO)
- `UE118.dta` (con variable `programa`: PMESUT / PMESTP)
- `FONCODES.dta` (con variable `tipo_reporte`)

## Pendientes

Faltan bases de PRONIED:

- UGSC (Unidad Gerencial de Sistemas de Contratacion)
- UGME (Unidad Gerencial de Mantenimiento)
- UGM (Unidad Gerencial de Mantenimiento / variantes)
- Uzonal (Unidades zonales)

Cuando lleguen los Excel correspondientes, agregar una linea `clean_one, file(...) sheet(...) row(...) prefix(...)` en el .do.
