function Export-M365OpsDataReport {
    <#
    .SYNOPSIS
        Genera un report (Excel e/o PDF con grafici) da dati GIA' raccolti altrove (tipicamente
        dall'AI via graph_api_call/exo_query in Invoke-M365OpsAgentTools) - deliberatamente
        generico rispetto all'argomento (licenze, mailbox, permessi, dispositivi, qualunque
        cosa) invece di avere un cmdlet dedicato per ogni possibile report: chi raccoglie i
        dati decide cosa contano, questa funzione si limita a produrre i file. I grafici sono
        SVG auto-generati (vedi New-M365OpsSvgChart) - nessuna libreria esterna, nessuna
        dipendenza da internet in fase di stampa PDF, stessa filosofia gia' usata per
        Export-M365OpsReport (Edge headless locale).

        Supporta piu' sezioni/tab (17/08/2026): un report puo' combinare piu' argomenti
        diversi (es. mailbox utente + mailbox condivise + permessi + gruppi di distribuzione)
        in un unico file, ciascuno nel proprio foglio Excel e nella propria sezione titolata
        nel PDF, invece di forzare tutto in un'unica tabella indistinta.

    .PARAMETER Sections
        Array di sezioni, una per tab/argomento: @{ Name=...; Data=...; ChartFields=... }.
        Un report con un solo argomento ha comunque UNA sola sezione qui. Ogni Data e' l'elenco
        COMPLETO di righe per quella sezione (mai un riassunto pre-aggregato). ChartFields e'
        opzionale, per sezione: ogni voce @{ Field=...; Label=...; Type='Bar'|'Pie' } viene
        aggregata qui col codice (Group-Object), MAI chiedendo il conteggio all'AI. Una sezione
        con Data vuoto non fa fallire il report: compare con una nota "nessun dato disponibile".

    .PARAMETER Formats
        Quali file generare: 'xlsx', 'pdf', o entrambi @('xlsx','pdf'). Default 'xlsx' soltanto
        (17/08/2026, richiesta esplicita dell'utente: se il formato non e' specificato, si
        assume xlsx - e' anche il formato che non dipende da Edge headless, quindi non puo'
        fallire per un problema di rendering/stampa esterno al dato stesso).

    .OUTPUTS
        pscustomobject con XlsxPath (o $null se non richiesto/fallito), PdfPath (idem),
        RowCount (totale), Sections (dettaglio per sezione: Name/RowCount), Warnings (fogli
        Excel falliti singolarmente o generazione PDF fallita - un fallimento PDF non fa perdere
        un xlsx gia' generato con successo, e viceversa: i due formati sono indipendenti).
    #>
    param(
        [Parameter(Mandatory)] [object[]]$Sections,
        [Parameter(Mandatory)] [string]$Title,
        [string]$FileSlug,
        [ValidateSet('xlsx', 'pdf')] [string[]]$Formats = @('xlsx')
    )

    if ($Sections.Count -eq 0) { throw "Serve almeno una sezione." }
    # Tetto deliberato: un report con decine di tab sarebbe comunque inutilizzabile da aprire
    # e potrebbe indicare che l'AI sta accorpando richieste che andrebbero invece proposte
    # come report separati - meglio un errore chiaro subito che un file da 40 fogli.
    if ($Sections.Count -gt 15) { throw "Troppe sezioni ($($Sections.Count), massimo 15) - dividi in piu' report separati." }
    foreach ($s in $Sections) {
        if ([string]::IsNullOrWhiteSpace([string]$s.Name)) { throw "Ogni sezione deve avere un Name non vuoto." }
    }

    $slug = if ($FileSlug) { $FileSlug } else { ($Title -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLower() }
    if (-not $slug) { $slug = "report" }
    $reportsDir = Join-Path $script:M365OpsModuleRoot 'Reports'
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $warnings = @()

    # --- Excel: un foglio per sezione ---
    $xlsxPath = $null
    if ('xlsx' -in $Formats) {
        $candidatePath = Join-Path $reportsDir "$slug-$stamp.xlsx"
        $xlsxSheets = @($Sections | ForEach-Object { @{ Name = $_.Name; Data = @($_.Data) } })
        try {
            Export-M365OpsReport -Sheets $xlsxSheets -Format xlsx -Path $candidatePath -Title $Title | Out-Null
            $xlsxPath = (Resolve-Path $candidatePath).Path
            if ($script:M365OpsLastReportWarnings) { $warnings += $script:M365OpsLastReportWarnings }
        }
        catch {
            $warnings += "Excel non generato: $($_.Exception.Message)"
        }
    }

    # --- PDF: una sezione titolata per argomento, con eventuali grafici prima della tabella ---
    $pdfPath = $null
    if ('pdf' -in $Formats) {
        $pdfSections = foreach ($s in $Sections) {
            # Appiattito PRIMA di raggruppare per i grafici e di costruire la tabella: un campo
            # con valore ARRAY (es. ManagedBy di un gruppo) raggrupperebbe tutte le righe insieme
            # sotto la stessa etichetta inutile "System.Object[]" invece che per valore reale, e
            # la tabella mostrerebbe lo stesso testo al posto del contenuto (bug reale 18/08/2026).
            $sectionData = @(ConvertTo-M365OpsFlatRows -Rows @($s.Data))
            $chartsHtml = if ($sectionData.Count -gt 0) {
                $availableFields = @($sectionData[0].PSObject.Properties.Name)
                foreach ($cf in @($s.ChartFields)) {
                    $field = $cf.Field
                    if (-not $field -or $field -notin $availableFields) { continue }
                    $grouped = $sectionData | Group-Object -Property $field | Sort-Object Count -Descending
                    if ($grouped.Count -eq 0) { continue }
                    $labels = @($grouped | ForEach-Object { if ($_.Name) { $_.Name } else { '(vuoto)' } })
                    $values = @($grouped | ForEach-Object { $_.Count })
                    $chartTitle = if ($cf.Label) { $cf.Label } else { $field }
                    $chartType = if ($cf.Type -eq 'Pie') { 'Pie' } else { 'Bar' }
                    $svg = New-M365OpsSvgChart -Labels $labels -Values $values -Type $chartType
                    "<div class='chart-block'><h2>$([System.Security.SecurityElement]::Escape($chartTitle))</h2>$svg</div>"
                }
            } else { @() }

            $tableHtml = if ($sectionData.Count -gt 0) { $sectionData | ConvertTo-Html -Fragment } else { "<p><em>Nessun dato disponibile.</em></p>" }
            $heading = "<h2>$([System.Security.SecurityElement]::Escape([string]$s.Name)) ($($sectionData.Count) righe)</h2>"
            $chartsBlock = if ($chartsHtml) { "<div class='charts'>$($chartsHtml -join '')</div>" } else { "" }
            "$heading$chartsBlock$tableHtml"
        }
        $htmlBody = "<h1>$Title</h1>$($pdfSections -join '')"
        $candidatePdfPath = Join-Path $reportsDir "$slug-$stamp.pdf"
        try {
            # Bug reale (17/08/2026): un fallimento qui (es. "Edge non ha prodotto il file")
            # faceva perdere anche l'xlsx GIA' generato con successo poco sopra, perche' prima
            # l'eccezione veniva lasciata propagare senza cattura locale - i due formati sono
            # generati in modo indipendente da qui in poi, un fallimento dell'uno non tocca l'altro.
            Export-M365OpsReport -HtmlBody $htmlBody -Format pdf -Path $candidatePdfPath -Title $Title | Out-Null
            $pdfPath = (Resolve-Path $candidatePdfPath).Path
        }
        catch {
            $warnings += "PDF non generato: $($_.Exception.Message)"
        }
    }

    if (-not $xlsxPath -and -not $pdfPath) { throw "Nessun file generato: $($warnings -join '; ')" }

    $sectionSummary = @($Sections | ForEach-Object { [pscustomobject]@{ Name = $_.Name; RowCount = @($_.Data).Count } })
    [pscustomobject]@{
        XlsxPath = $xlsxPath
        PdfPath  = $pdfPath
        RowCount = ($sectionSummary | Measure-Object -Property RowCount -Sum).Sum
        Sections = $sectionSummary
        Warnings = if ($warnings.Count -gt 0) { $warnings } else { $null }
    }
}
