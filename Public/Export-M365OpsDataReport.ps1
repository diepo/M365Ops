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
    # Nome file collision-resistant (26/08/2026, bug reale trovato dal vivo durante la maratona
    # di stress-test): la cartella Reports\ e' CONDIVISA da tutti i tenant, e prima d'ora il nome
    # file dipendeva SOLO dal Title/FileSlug e da un timestamp al secondo - due tenant diversi (o
    # lo stesso tenant due volte in rapida successione, plausibile perche' la generazione di un
    # report su un dataset piccolo puo' completarsi in ben meno di un secondo) che generano un
    # report con lo stesso Title nello stesso secondo si sovrascrivevano a vicenda in silenzio,
    # nel ramo xlsx via un Remove-Item incondizionato in Export-M365OpsReport, senza alcun
    # controllo di proprieta'. Aggiunto (1) il tenant attivo nel nome file, sanificato con LO
    # STESSO pattern gia' usato per lo storage per-tenant di Knowledge Base/diagramma
    # (Get-M365OpsTenantStorageKey.ps1: `-replace '[^\w\-]', '_'`) invece di inventarne uno nuovo,
    # e (2) un suffisso esadecimale casuale (da un GUID) accanto al timestamp, cosi' anche lo
    # STESSO tenant con lo STESSO Title nello STESSO secondo non collide piu'.
    $tenantRaw = if ($script:M365OpsContext -and $script:M365OpsContext.Name) { $script:M365OpsContext.Name } else { 'no-tenant' }
    $tenantSlug = ($tenantRaw -replace '[^\w\-]', '_')
    $reportsDir = Join-Path $script:M365OpsModuleRoot 'Reports'
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $uniq = [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $warnings = @()

    # --- Excel: un foglio per sezione ---
    $xlsxPath = $null
    if ('xlsx' -in $Formats) {
        $candidatePath = Join-Path $reportsDir "$tenantSlug-$slug-$stamp-$uniq.xlsx"
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
      # try/catch attorno all'INTERO blocco PDF, non solo alla chiamata Export-M365OpsReport
      # sotto (23/08/2026, bug reale trovato dal vivo, riprodotto - bug-hunt di 16 ore):
      # Group-Object -Property $field poco sotto lancia un'eccezione TERMINANTE
      # ("Cannot compare... because the objects are not the same type or the object does not
      # implement IComparable") quando $field e' una colonna con un valore OGGETTO NIDIFICATO
      # singolo (non un array - quelli sono gia' appiattiti da ConvertTo-M365OpsFlatRows, ma un
      # singolo oggetto come signInActivity/assignedPlan/manager passa attraverso invariato) -
      # comune sui campi Graph reali. Questo blocco di costruzione di $pdfSections viveva PRIMA
      # e FUORI dal try/catch che il commento sotto descrive (aggiunto il 17/08/2026 per un bug
      # simile ma piu' ristretto, solo sulla chiamata di scrittura PDF vera e propria) - se
      # Group-Object falliva qui, l'eccezione risaliva FUORI dall'intera funzione, facendo
      # perdere anche $xlsxPath gia' generato con successo poco sopra (il chiamante non riceve
      # mai il pscustomobject di ritorno, quindi nessun modo di sapere che l'xlsx esiste
      # comunque su disco) - esattamente il bug che il commento sotto dice gia' risolto, ma per
      # una causa diversa mai coperta. Ora l'intero blocco (costruzione contenuto PDF INCLUSA)
      # e' nello stesso try, cosi' un fallimento qui degrada sempre a un avviso, mai a
      # un'eccezione che si porta via anche l'xlsx.
      try {
        # Ogni sezione costruita nel proprio try/catch (26/08/2026, bug reale trovato durante
        # lo stress-test mirato al pattern "un passo fallito blocca i passi fratelli
        # indipendenti" - lo stesso schema gia' corretto 3 volte in questa maratona, v0.10.1/
        # v0.10.2/v0.10.6): PRIMA di questo fix, l'intero foreach qui sotto viveva senza
        # protezione per-sezione - una singola sezione (es. un campo con dati imprevisti che fa
        # fallire Group-Object o New-M365OpsSvgChart) faceva risalire l'eccezione al try esterno,
        # che la trasforma in un semplice avviso "PDF non generato" MA a costo di perdere anche
        # le sezioni PRECEDENTI gia' costruite con successo nello stesso ciclo - un report con 5
        # sezioni valide + 1 malformata prima produceva ZERO sezioni nel PDF invece di 5 sezioni
        # + una nota d'errore sulla sesta. Il percorso xlsx (Export-M365OpsReport, ramo 'xlsx')
        # ha gia' questo isolamento per-foglio dal 17/08/2026 - qui mancava l'equivalente.
        $pdfSections = foreach ($s in $Sections) {
            try {
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
            catch {
                $warnings += "Sezione PDF '$($s.Name)' non generata: $($_.Exception.Message)"
                $heading = "<h2>$([System.Security.SecurityElement]::Escape([string]$s.Name))</h2>"
                "$heading<p><em>Sezione non generata a causa di un errore: $([System.Security.SecurityElement]::Escape($_.Exception.Message))</em></p>"
            }
        }
        $htmlBody = "<h1>$Title</h1>$($pdfSections -join '')"
        $candidatePdfPath = Join-Path $reportsDir "$tenantSlug-$slug-$stamp-$uniq.pdf"
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
      catch {
        # Copre la costruzione di $pdfSections sopra (Group-Object su un campo con oggetti
        # nidificati, o qualunque altro errore imprevisto nel montaggio dell'HTML) - stessa
        # filosofia dell'altro catch: un fallimento qui non deve MAI far perdere l'xlsx.
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
