function Export-M365OpsReport {
    <#
    .SYNOPSIS
        Esporta dati in CSV, Excel (.xlsx) o PDF - con supporto multi-tab/multi-sezione per
        xlsx e pdf (17/08/2026).

        CSV: nativo PowerShell, nessuna dipendenza. UN solo dataset (-Data) - una tabella sola
             per natura, usa xlsx o pdf se servono piu' sezioni.
        XLSX: usa il modulo 'ImportExcel' (installato automaticamente al primo uso se assente).
              Con -Sheets, ogni voce diventa un foglio separato nello stesso file (verificato
              dal vivo che ImportExcel accoda fogli allo stesso file su chiamate successive con
              -WorksheetName diverso, non serve altro).
        PDF: costruisce un HTML e lo stampa in PDF con Microsoft Edge in modalita' headless.
             Con -Sheets, ogni voce diventa una sezione titolata separata nello stesso PDF.

    .PARAMETER Data
        UN SOLO dataset (usato per csv/xlsx/pdf a tabella singola). Alternativo a -Sheets.

    .PARAMETER Sheets
        Piu' dataset nominati, uno per tab/sezione: array di @{ Name=...; Data=... }. Solo per
        xlsx/pdf. Alternativo a -Data. Un foglio con dati vuoti non fa fallire l'intero report -
        viene scritto con una nota "Nessun dato disponibile" invece di essere saltato in
        silenzio o interrompere gli altri fogli. Se un singolo foglio fallisce (es. nome
        duplicato dopo la normalizzazione), gli altri vengono comunque scritti - i dettagli sono
        in $script:M365OpsLastReportWarnings dopo la chiamata.

    .PARAMETER HtmlBody
        Corpo HTML gia' pronto per un report pdf narrativo (es. l'analisi AI dei pattern).
        Se omesso e Format e' pdf, viene generata una tabella (o piu' sezioni) da -Data/-Sheets.

    .EXAMPLE
        Get-M365OpsManagedDevices | Export-M365OpsReport -Format csv -Path "C:\...\dispositivi.csv"
    .EXAMPLE
        Export-M365OpsReport -Format xlsx -Path "report.xlsx" -Title "Tenant" -Sheets @(
            @{ Name = "Mailbox Utente"; Data = $userMailboxes }
            @{ Name = "Mailbox Condivise"; Data = $sharedMailboxes }
        )
    #>
    param(
        [object[]]$Data,
        [object[]]$Sheets,
        [string]$HtmlBody,
        [Parameter(Mandatory)] [ValidateSet('csv', 'xlsx', 'pdf')] [string]$Format,
        [Parameter(Mandatory)] [string]$Path,
        [string]$Title = "Report M365Ops"
    )

    if ($Data -and $Sheets) { throw "Usa -Data OPPURE -Sheets, non entrambi." }
    if ($Sheets -and $Format -eq 'csv') { throw "Il formato CSV supporta un solo dataset (-Data) - e' una tabella sola per natura. Usa xlsx o pdf per piu' sezioni/tab." }

    $script:M365OpsLastReportWarnings = $null

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # Nome foglio Excel: max 31 caratteri, niente \ / ? * [ ] : - normalizzato una volta sola
    # qui invece che ripetuto ad ogni chiamante. Deduplica se due nomi collidono dopo la
    # normalizzazione (es. due sezioni che iniziano uguali e vengono troncate a 31 caratteri).
    $sanitizeSheetName = {
        param($rawName, [string[]]$usedNames)
        $clean = ([string]$rawName -replace '[\\/\?\*\[\]:]', ' ').Trim()
        if (-not $clean) { $clean = "Foglio" }
        if ($clean.Length -gt 31) { $clean = $clean.Substring(0, 31).Trim() }
        $final = $clean
        $suffix = 1
        while ($usedNames -contains $final) {
            $suffixText = " ($suffix)"
            $maxBase = 31 - $suffixText.Length
            $final = $clean.Substring(0, [Math]::Min($clean.Length, $maxBase)) + $suffixText
            $suffix++
        }
        return $final
    }

    switch ($Format) {
        'csv' {
            if (-not $Data) { throw "Serve -Data per un export CSV." }
            $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        }

        'xlsx' {
            if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                Install-Module ImportExcel -Scope CurrentUser -Force -AllowClobber
            }
            Import-Module ImportExcel -ErrorAction Stop

            $sheetList = if ($Sheets) { $Sheets } elseif ($Data) { @(@{ Name = "Report"; Data = $Data }) } else { throw "Serve -Data o -Sheets per un export Excel." }
            # Sempre da zero: con piu' chiamate a Export-Excel sullo stesso file (una per
            # foglio), un file residuo di un tentativo precedente con lo stesso nome
            # mescolerebbe fogli vecchi e nuovi invece di un report pulito.
            if (Test-Path $Path) { Remove-Item $Path -Force }

            $usedNames = @()
            $warnings = @()
            $sheetIndex = 0
            foreach ($sheet in $sheetList) {
                $sheetIndex++
                $sheetName = & $sanitizeSheetName $sheet.Name $usedNames
                $usedNames += $sheetName
                $sheetData = @($sheet.Data)
                if ($sheetData.Count -eq 0) { $sheetData = @([pscustomobject]@{ Nota = "Nessun dato disponibile" }) }
                # Appiattisce eventuali proprieta' con valore ARRAY (es. ManagedBy di un gruppo
                # di distribuzione, multi-valore) in una stringa leggibile - senza questo,
                # ImportExcel scrive il nome del tipo .NET ("System.Object[]") invece del
                # contenuto (bug reale segnalato dal vivo il 18/08/2026).
                $sheetData = @(ConvertTo-M365OpsFlatRows -Rows $sheetData)
                try {
                    # TableName derivato dall'indice, non dal nome foglio: i nomi tabella Excel
                    # devono essere univoci in TUTTO il workbook (non solo nel foglio) e validi
                    # (solo alfanumerico/underscore, non inizia con cifra) - un indice e' sempre
                    # valido e univoco per costruzione, invece di provare a ripulire ogni volta
                    # un nome utente arbitrario e rischiare comunque una collisione.
                    $sheetData | Export-Excel -Path $Path -AutoSize -TableName "Tabella$sheetIndex" -WorksheetName $sheetName -FreezeTopRow
                }
                catch {
                    $warnings += "Foglio '$sheetName': $($_.Exception.Message)"
                }
            }
            if ($warnings.Count -gt 0) { $script:M365OpsLastReportWarnings = $warnings }
            if (-not (Test-Path $Path)) { throw "Generazione Excel fallita per tutti i fogli: $($warnings -join '; ')" }
        }

        'pdf' {
            $edge = (Get-Command msedge.exe -ErrorAction SilentlyContinue).Source
            if (-not $edge) {
                $candidatePaths = @(
                    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
                )
                $edge = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            }
            if (-not $edge) { throw "Microsoft Edge non trovato - necessario per generare PDF." }

            $body = $HtmlBody
            if (-not $body -and $Sheets) {
                $sectionsHtml = foreach ($sheet in $Sheets) {
                    $sheetData = @(ConvertTo-M365OpsFlatRows -Rows @($sheet.Data))
                    $heading = "<h2>$([System.Security.SecurityElement]::Escape([string]$sheet.Name))</h2>"
                    $table = if ($sheetData.Count -gt 0) { $sheetData | ConvertTo-Html -Fragment } else { "<p><em>Nessun dato disponibile.</em></p>" }
                    "$heading$table"
                }
                $body = "<h1>$Title</h1>$($sectionsHtml -join '')"
            }
            if (-not $body -and $Data) {
                $rows = ConvertTo-M365OpsFlatRows -Rows @($Data) | ConvertTo-Html -Fragment
                $body = "<h1>$Title</h1>$rows"
            }
            if (-not $body) { throw "Serve -HtmlBody, -Data oppure -Sheets per un export PDF." }

            $html = @"
<!doctype html>
<html><head><meta charset="utf-8">
<style>
  body { font-family: 'Segoe UI', system-ui, sans-serif; font-size: 12px; color: #16222E; padding: 24px; }
  h1 { font-size: 18px; border-bottom: 2px solid #14618F; padding-bottom: 8px; }
  table { border-collapse: collapse; width: 100%; margin-top: 12px; }
  th, td { border: 1px solid #D9DFE5; padding: 6px 10px; text-align: left; font-size: 11px; }
  th { background: #EBEEF2; }
  .meta { color: #8494A3; font-size: 10.5px; margin-bottom: 16px; }
  .charts { display: flex; flex-wrap: wrap; gap: 20px; margin: 16px 0 24px; }
  .chart-block { flex: 1 1 380px; }
  .chart-block h2 { font-size: 13px; margin: 0 0 8px; }
  h2 { font-size: 14px; border-bottom: 1px solid #D9DFE5; padding-bottom: 4px; margin-top: 20px; }
</style></head>
<body>
<div class="meta">Generato il $(Get-Date -Format 'dd/MM/yyyy HH:mm')</div>
$body
</body></html>
"@
            $tmpHtml = [IO.Path]::ChangeExtension($Path, '.tmp.html')
            Set-Content -Path $tmpHtml -Value $html -Encoding UTF8

            & $edge --headless --disable-gpu "--print-to-pdf=$Path" "--print-to-pdf-no-header" (Resolve-Path $tmpHtml).Path | Out-Null
            # Poll invece di un fisso Start-Sleep -Seconds 2 (26/08/2026, bug reale trovato dal
            # vivo tramite il server di test reale: "genera un report PDF" sui Team del tenant
            # ha risposto "Edge non ha prodotto il file", ma il file .pdf ERA presente su disco
            # subito dopo, con la dimensione corretta - falso negativo verificato confrontando il
            # timestamp del file con l'ora della richiesta). Causa: il processo msedge.exe
            # avviato con `&` non garantisce che al ritorno del comando il file sia gia' scritto
            # su disco - su questa macchina, con altri processi Edge/Chromium gia' in esecuzione
            # (es. automazione browser di altre sessioni), la nuova invocazione headless puo'
            # cedere il lavoro reale di stampa a un processo esistente e restituire il controllo
            # PRIMA che quel processo abbia finito di scrivere, rendendo 2 secondi fissi
            # insufficienti in modo intermittente - stesso principio gia' applicato al polling di
            # riavvio del server in questa stessa maratona ("allow 15-20+ seconds, multiple poll
            # attempts") invece di un'attesa fissa indovinata. Ora si attende fino a 20 secondi,
            # controllando ogni 250ms se il file esiste E non e' piu' in scrittura (dimensione
            # stabile tra due controlli consecutivi), invece di sperare che 2 secondi bastino
            # sempre.
            $deadline = (Get-Date).AddSeconds(20)
            $lastSize = -1
            $stableChecks = 0
            while ((Get-Date) -lt $deadline) {
                if (Test-Path $Path) {
                    $currentSize = (Get-Item $Path).Length
                    if ($currentSize -gt 0 -and $currentSize -eq $lastSize) {
                        $stableChecks++
                        if ($stableChecks -ge 2) { break }
                    } else {
                        $stableChecks = 0
                    }
                    $lastSize = $currentSize
                }
                Start-Sleep -Milliseconds 250
            }
            Remove-Item $tmpHtml -Force -ErrorAction SilentlyContinue

            if (-not (Test-Path $Path)) { throw "Generazione PDF fallita (Edge non ha prodotto il file entro 20 secondi)." }
        }
    }

    return (Resolve-Path $Path).Path
}
