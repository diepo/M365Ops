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
                # TLS1.2/provider NuGet/-SkipPublisherCheck (22/08/2026): stesso irrobustimento
                # applicato a Connect-M365OpsTeams.ps1 dopo un blocco reale trovato dal vivo -
                # senza, Install-Module puo' restare in attesa per sempre di un prompt di
                # conferma mai mostrato in un processo server senza finestra visibile.
                Write-Host "Modulo PdfLexer non trovato, lo installo..." -ForegroundColor Yellow
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
                if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
                }
                Install-Module PdfLexer -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
            }
            Import-Module PdfLexer -ErrorAction Stop
            $doc = Open-PdfDocument -Path $FilePath
            try {
                # BUG trovato dal vivo il 20/08/2026 caricando la guida (52 pagine) nella KB
                # globale: Get-PdfText restituisce un ARRAY, un elemento di testo per PAGINA, non
                # una stringa unica. "return (Get-PdfText -Document $doc)" lo passava al chiamante
                # cosi' com'era: Add-M365OpsKnowledgeDocument legge poi $extractedText.Length
                # aspettandosi un conteggio di CARATTERI, ma su un array .Length e' il conteggio
                # di ELEMENTI (qui: 52, scambiato per "52 caratteri estratti" nel log, con testo
                # vero e reale scartato) - e passare l'array a Invoke-M365OpsAgent -Context (tipo
                # [string]) falliva con un errore di conversione di tipo, mai la vera causa del
                # fallimento. Join esplicito in un'unica stringa, con un separatore che preserva i
                # confini di pagina per la leggibilita' del testo estratto.
                return ((Get-PdfText -Document $doc) -join "`n`n")
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
        # TLS1.2/provider NuGet/-SkipPublisherCheck (22/08/2026): stesso irrobustimento
        # applicato a Connect-M365OpsTeams.ps1 dopo un blocco reale trovato dal vivo - senza,
        # Install-Module puo' restare in attesa per sempre di un prompt di conferma mai
        # mostrato in un processo server senza finestra visibile.
        Write-Host "Modulo ImportExcel non trovato, lo installo..." -ForegroundColor Yellow
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Install-Module ImportExcel -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
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
