# Visor de intervenciones — recomendacion y diseno

## Que recomiendo

**Power BI**. Razones:

1. Ya tienes un repo `powerbi/` → flujo natural.
2. Los requerimientos que recibes (cuantas intervenciones hay en Loreto,
   cuantos modulos, cuantas asistencias tecnicas, etc.) son **preguntas de
   segmentacion y conteo**. Power BI las responde en 1 click con slicers
   (cortadores) sin tocar Stata.
3. Los usuarios finales (directivos) pueden explorar solos: abrir el .pbix,
   filtrar por departamento y tener el numero al instante.
4. Puedes embeberlo en SharePoint / Teams.

**Alternativas** si Power BI te queda corto:

| Opcion | Cuando usar |
|--------|-------------|
| **Streamlit** (Python) | Si quieres un web app con URL publica para MINEDU |
| **Shiny** (R) | Si el area prefiere R |
| **Excel con Power Query + tablas dinamicas** | Si nadie tiene licencia Power BI Pro |
| **Metabase / Superset** | Para dashboard corporativo con multiples usuarios |

Para tu caso Power BI es lo mas practico.

## Fuente de datos para el visor

El `.do` genera **`BASE_PANORAMA.csv`** en `${Output}`. Es la tabla larga
(long format) con una fila por cada registro de intervencion + columnas
canonicas + datos enriquecidos del MEF Banco de Inversiones.

Columnas clave del panorama:

- `entidad`          → PRONIED / PEIP / UE118 / ANIN / FONCODES
- `unidad`           → UGEO / UGRD_MBR / UGME_MOBILIARIO / UGM_ACCESIBILIDAD_2024 / ...
- `cui`              → 7 digitos (llave cruce con BI del MEF)
- `codigo_local`     → 6 digitos
- `codigo_modular`   → 7 digitos
- `nombre_inversion` / `nombre_ie`
- `departamento`, `provincia`, `distrito`
- `sector`, `pliego`, `unidad_ejecutora`, `uf`, `uei`, `opmi`
- `estado`, `fase_obra`, `etapa_obra`, `situacion`, `estado_bi`
- `tipo_inversion`, `tipo_intervencion`, `tipo_mantenimiento`
- `monto_inversion`, `costo_actualizado_bi`, `devengado`, `pim`, `pia`
- `avance_fisico`, `avance_financiero`, `avance_fisico_bi`
- `fecha_inicio`, `fecha_culminacion`, `fecha_entrega`, `fecha_inicio_et`, `fecha_fin_et`
- `cartera_pmi`, `funcion`
- `_m_bi`  → 1 = solo panorama, 3 = match con BI (enriquecido)

## Diseno del dashboard (Power BI)

### Hoja 1: Panorama general

**Tarjetas (big numbers):**

- N intervenciones totales (CountRows)
- N CUI unicos (DistinctCount(cui))
- Monto total (Sum(monto_inversion) / 1000000)
- Devengado total (Sum(devengado) / 1000000)
- Avance fisico promedio (Average(avance_fisico))

**Cortadores (slicers) laterales:**

- Departamento, Provincia, Distrito (jerarquico)
- Entidad, Unidad
- Estado, Fase de obra
- Tipo de intervencion
- Ano (de `fecha_inicio`)
- Sector, Pliego

**Graficos:**

- Barras: # intervenciones por `entidad` (apilado por `unidad`)
- Mapa: # intervenciones por `departamento` (usar `ubigeo` o nombres)
- Barras horizontales: Top 15 distritos con mas intervenciones
- Line chart: # intervenciones por ano de inicio

### Hoja 2: Inversion y ejecucion

- Barras: monto_inversion por departamento
- Barras: devengado vs monto_inversion (stacked)
- Tabla: departamento x entidad → suma monto
- KPI: % avance fisico promedio por entidad

### Hoja 3: Detalle

- Tabla con todas las columnas, filtrable
- Exportar a Excel el subset que filtre el usuario

### Hoja 4: Cobertura de datos

- % de filas con CUI
- % de filas con departamento
- Barras: filas con match BI (`_m_bi==3`) vs solo panorama (`_m_bi==1`)
  → detecta donde falta llave para cruzar

## Como conectar

1. Abre **Power BI Desktop**.
2. Obtener datos → **Texto/CSV** → `${Output}/BASE_PANORAMA.csv`.
3. Opcion 1 mas rapida: cargar directo. Opcion 2 robusta: **Power Query**
   para parsear tipos (CUI como texto con ceros al frente, fechas como
   Date, montos como Decimal).
4. Publicar a Power BI Service → programar actualizacion cuando actualices
   los .xlsx y corras `limpieza_por_entidad.do`.

## Flujo recomendado

```
01_input/*.xlsx           (Excel crudos que te envian)
        |
        v
limpieza_por_entidad.do   (Stata: corrige codigos, fechas, nombres, dup)
        |
        v
03_output/BASE_PANORAMA.csv
        |
        v
dashboard.pbix            (Power BI conectado al CSV)
```

## Para requerimientos de informacion (parrafo automatico)

En paralelo tienes `reporte_consulta.do` que NO necesita Power BI:

```stata
do limpieza_por_entidad.do    // genera BASE_PANORAMA.dta
do reporte_consulta.do LORETO
```

Sale por pantalla un parrafo tipo:

> "En LORETO se han identificado 234 registros de intervencion asociados
> a 189 CUI unicos. La distribucion por entidad es: PRONIED (180),
> FONCODES (40), PEIP (8), UE118 (6). El monto total de inversion
> asciende a S/ 456.78 millones, con S/ 312.45 millones devengados y un
> avance fisico promedio de 67.3 %."

Que lo copias directo al oficio/correo de respuesta.

## Requerimientos frecuentes que el visor cubre

| Requerimiento | Como responder |
|---|---|
| "Cuantas intervenciones hay en Loreto" | Slicer departamento=Loreto → tarjeta N |
| "Cuantos modulos en Madre de Dios" | Slicer departamento + Slicer unidad=UGME_SISTEMAS_MODULARES |
| "Cuanto se ha devengado en Cusco" | Slicer + tarjeta Sum(devengado) |
| "Que asistencias tecnicas hay" | Slicer entidad=PRONIED + unidad=UGSC_ASITEC |
| "Cuantos acondicionamientos en 2025" | Slicer unidad=UGM_ACONDICIONAMIENTO + ano=2025 |
| "Cuantos mantenimientos 2025 vs 2026" | Dos tarjetas con filtros cruzados |
| "Ejecucion por pliego / sector" | Matriz pliego x Sum(devengado) |

## Datos sin match en BI

Las filas con `_m_bi == 1` son registros que **no tienen CUI en el MEF
Banco de Inversiones** — tipicamente:

- Asesoramientos de UZ (no son inversiones registradas)
- Inspecciones de UZ
- Acondicionamientos que son mantenimiento (no proyecto)
- Registros con CUI invalido

El visor debe tener un filtro **"Tiene CUI match con BI"** = Si/No para
que el usuario vea la diferencia al responder requerimientos.

## Actualizacion

Cuando llegue un xlsx nuevo:

1. Reemplaza el xlsx viejo en `${Input}`.
2. Corre `do limpieza_por_entidad.do` (regenera .dta + CSV).
3. En Power BI Desktop → Inicio → Actualizar → Publicar.

Si el xlsx tiene **columnas nuevas** que no estan en `canon_rename`,
aparecen con su nombre snake_case-ASCII (ej. `monto_fortalecimiento_2027`)
y Power BI las toma automaticamente.
