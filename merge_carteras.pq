// ============================================================================
// Power Query M — Consolidación PEIP, ANIN, UGRD, UGEO contra CUI_cartera_GN
// ============================================================================
// Pega cada bloque en un nuevo "Query en blanco" del Editor de Power Query,
// con el nombre indicado. Ajusta la ruta RUTA_BASE según donde tengas los xlsx.
//
// IMPORTANTE: los encabezados reales están en la fila 3 (saltamos 2 filas).
// ============================================================================

// ------ 1) Parámetro con la ruta ------ Nombre del Query: RUTA_BASE
"C:\ruta\a\los\archivos\"   // <- cámbialo


// ------ 2) Función utilitaria ------ Nombre del Query: fnLeerCUI
// Parámetros: archivo, hoja, nombreColCUI, etiqueta
(archivo as text, hoja as text, nombreColCUI as text, etiqueta as text) as table =>
let
    Origen     = Excel.Workbook(File.Contents(RUTA_BASE & archivo), null, true),
    Hoja       = Origen{[Item=hoja, Kind="Sheet"]}[Data],
    // Saltamos las 2 primeras filas (títulos) y promovemos la 3ra a encabezado
    SinTitulos = Table.Skip(Hoja, 2),
    ConHeader  = Table.PromoteHeaders(SinTitulos, [PromoteAllScalars=true]),
    // Nos quedamos con la columna CUI y la renombramos a "CUI"
    SoloCUI    = Table.SelectColumns(ConHeader, {nombreColCUI}),
    Renombrada = Table.RenameColumns(SoloCUI, {{nombreColCUI, "CUI"}}),
    // Limpieza: vacíos, texto a número cuando se pueda
    LimpiaNull = Table.SelectRows(Renombrada, each [CUI] <> null and [CUI] <> "" and [CUI] <> "-"),
    ACadena    = Table.TransformColumns(LimpiaNull, {{"CUI", each Text.From(_), type text}}),
    // Deduplicación dentro de la fuente
    SinDup     = Table.Distinct(ACadena, {"CUI"}),
    ConEtiq    = Table.AddColumn(SinDup, "cartera_gn", each etiqueta, type text)
in
    ConEtiq


// ------ 3) Cada fuente como query propio (usan fnLeerCUI) ------
// Query: ANIN
fnLeerCUI("ANIN.xlsx", "Anexo 1", "CUI / ÍDEA", "ANIN")

// Query: PEIP_IMPLEMENTADOS
fnLeerCUI("PEIP.xlsx", "IMPLEMENTADOS", "CUI", "PEIP - IMPLEMENTADOS")

// Query: PEIP_CONTINGENCIA
fnLeerCUI("PEIP.xlsx", "CONTINGENCIA", "CUI", "PEIP - CONTINGENCIA")

// Query: UGRD_PIRCC
fnLeerCUI("UGRD.xlsx", "PIRCC", "CUI", "UGRD - PIRCC")

// Query: UGRD_MBR
fnLeerCUI("UGRD.xlsx", "MBR", "CUI", "UGRD - MBR")

// Query: UGRD_ME
fnLeerCUI("UGRD.xlsx", "ME", "CUI", "UGRD - ME")

// Query: UGEO
fnLeerCUI("UGEO.xlsx", "UGEO", "CUI", "UGEO - Obra Pública")


// ------ 4) Base existente ------ Query: CUI_cartera_GN
let
    Origen     = Excel.Workbook(File.Contents(RUTA_BASE & "CUI_cartera_GN.xlsx"), null, true),
    Hoja       = Origen{[Item="Hoja1", Kind="Sheet"]}[Data],
    Promovida  = Table.PromoteHeaders(Hoja, [PromoteAllScalars=true]),
    ACadena    = Table.TransformColumns(Promovida, {{"CUI", each Text.From(_), type text}}),
    SinVacios  = Table.SelectRows(ACadena, each [CUI] <> null and [CUI] <> ""),
    SinDup     = Table.Distinct(SinVacios, {"CUI"})
in
    SinDup


// ------ 5) Consolidación final ------ Query: CUI_cartera_GN_consolidado
let
    // Unimos todas las fuentes nuevas
    Unidas = Table.Combine({
        ANIN,
        PEIP_IMPLEMENTADOS,
        PEIP_CONTINGENCIA,
        UGRD_PIRCC,
        UGRD_MBR,
        UGRD_ME,
        UGEO
    }),

    // Agrupamos por CUI para deduplicar entre fuentes:
    // si un CUI está en varias hojas, concatenamos sus etiquetas con " | "
    Agrupadas = Table.Group(
        Unidas, {"CUI"},
        {{"cartera_gn",
            each Text.Combine(List.Sort(List.Distinct([cartera_gn])), " | "),
            type text}}
    ),

    // Dejamos sólo los CUIs que NO existen en la base original
    ExistentesSet = List.Buffer(CUI_cartera_GN[CUI]),
    SoloNuevos    = Table.SelectRows(Agrupadas, each not List.Contains(ExistentesSet, [CUI])),

    // Concatenamos base original + nuevos
    Consolidado   = Table.Combine({CUI_cartera_GN, SoloNuevos}),

    // Deduplicación final por si acaso
    Final         = Table.Distinct(Consolidado, {"CUI"})
in
    Final
