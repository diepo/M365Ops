function Get-M365OpsExtractedFileText {
    <#
    .SYNOPSIS
        Estrae il testo semplice da un file .txt/.docx/.xlsx/.pdf, in base all'estensione -
        helper interno per la Knowledge Base per tenant (Add-M365OpsKnowledgeDocument).
    .NOTES
        .doc (formato binario OLE legacy, non .docx) NON e' supportato - non esiste una via
        affidabile per estrarlo senza una libreria dedicata; meglio dirlo chiaramente che
        produrre testo corrotto. Chiedi di salvare come .docx prima di caricarlo.
        .xls (formato binario legacy, non .xlsx) e' invece supportato: ImportExcel legge
        entrambi i formati.
        .pdf usa il modulo PdfLexer (installato automaticamente al primo uso se assente) -
        estrae solo testo selezionabile, non OCR: un PDF scansionato come immagine produce
        testo vuoto/quasi vuoto, segnalato al chiamante invece di fallire in silenzio.
    #>
    param([Parameter(Mandatory)] [string]$FilePath)

    if (-not (Test-Path $FilePath)) { throw "File non trovato: $FilePath" }
    $ext = [IO.Path]::GetExtension($FilePath).ToLower()

    switch ($ext) {
        '.txt' {
            return (Get-Content -Path $FilePath -Raw -ErrorAction Stop)
        }
        '.md' {
            return (Get-Content -Path $FilePath -Raw -ErrorAction Stop)
        }
        '.docx' {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
            try {
                $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
                if (-not $entry) { throw "word/document.xml non trovato - file .docx non valido o corrotto." }
                $reader = New-Object IO.StreamReader($entry.Open())
                $xml = $reader.ReadToEnd()
                $reader.Close()
                # Estrazione testo grezza: ogni <w:t>...</w:t> e' un frammento di testo Word -
                # sufficiente per catalogazione/ricerca, non serve preservare formattazione.
                $matches = [regex]::Matches($xml, '<w:t[^>]*>(.*?)</w:t>')
                $text = ($matches | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) }) -join ' '
                return $text
            }
            finally { $zip.Dispose() }
        }
        '.doc' {
            throw "Formato .doc (binario legacy) non supportato - salva il file come .docx da Word e ricaricalo."
        }
        '.xlsx' {
            Get-M365OpsExtractedExcelText -FilePath $FilePath
        }
        '.xls' {
            Get-M365OpsExtractedExcelText -FilePath $FilePath
        }
        '.pdf' {
            if (-not (Get-Module -ListAvailable -Name PdfLexer)) {
                Write-Host "Modulo PdfLexer non trovato, lo installo..." -ForegroundColor Yellow
                Install-Module PdfLexer -Scope CurrentUser -Force -AllowClobber
            }
            Import-Module PdfLexer -ErrorAction Stop
            $doc = Open-PdfDocument -Path $FilePath
            try {
                return (Get-PdfText -Document $doc)
            }
            finally {
                Close-PdfDocuments
            }
        }
        default {
            throw "Formato file '$ext' non supportato per la Knowledge Base - formati accettati: .txt, .md, .docx, .xlsx, .xls, .pdf"
        }
    }
}

function Get-M365OpsExtractedExcelText {
    param([Parameter(Mandatory)] [string]$FilePath)
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host "Modulo ImportExcel non trovato, lo installo..." -ForegroundColor Yellow
        Install-Module ImportExcel -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module ImportExcel -ErrorAction Stop
    $sheetNames = Get-ExcelSheetInfo -Path $FilePath | Select-Object -ExpandProperty Name
    $parts = foreach ($sheetName in $sheetNames) {
        $rows = @(Import-Excel -Path $FilePath -WorksheetName $sheetName -ErrorAction SilentlyContinue)
        if ($rows.Count -eq 0) { continue }
        $lines = foreach ($row in $rows) {
            ($row.PSObject.Properties | ForEach-Object { "$($_.Name): $($_.Value)" }) -join ' | '
        }
        "=== Foglio: $sheetName ===`n" + ($lines -join "`n")
    }
    return ($parts -join "`n`n")
}
