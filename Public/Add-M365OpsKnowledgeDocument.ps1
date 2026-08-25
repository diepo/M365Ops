function Add-M365OpsKnowledgeDocument {
    <#
    .SYNOPSIS
        Aggiunge un documento (.txt/.md/.docx/.xlsx/.xls/.pdf) alla Knowledge Base del tenant
        indicato: estrae il testo, chiama l'AI UNA SOLA VOLTA per catalogarlo (titolo, argomenti,
        riassunto), salva file + testo estratto + voce di catalogo - tutto sotto una cartella/
        file DEDICATI a questo tenant, mai condivisi con altri.
    .PARAMETER TenantName
        Nome del profilo tenant (es. 'contoso-test') - determina ESCLUSIVAMENTE dove viene
        salvato tutto: Uploads\kb\<TenantName>\ e Config\KnowledgeBase-<TenantName>.json,
        stesso schema gia' usato per lo storico chat (Get-M365OpsChatHistory) - nessun dato
        di un tenant e' mai raggiungibile leggendo/scrivendo con un altro TenantName.
    .OUTPUTS
        La voce di catalogo appena creata (senza il testo completo, solo i metadati).
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$OriginalFileName,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    # Chiave di storage risolta per TENANT REALE, non per profilo (25/08/2026, vedi
    # Get-M365OpsKnowledgeBasePaths) - due profili sullo stesso tenant condividono la stessa
    # Knowledge Base. La funzione crea gia' da sola sia Config\ sia Uploads\kb\<chiave>\ se
    # mancanti (bug storico del 20/08/2026 su un'installazione vergine, vedi la funzione stessa).
    $paths = Get-M365OpsKnowledgeBasePaths -TenantName $TenantName
    $kbDir = $paths.KbDir
    New-Item -ItemType Directory -Force -Path $kbDir | Out-Null
    $catalogPath = $paths.CatalogPath

    $safeFileName = Split-Path -Leaf $OriginalFileName
    $destPath = Join-Path $kbDir $safeFileName
    Copy-Item -Path $FilePath -Destination $destPath -Force

    $extractedText = $null
    $extractionError = $null
    try {
        $extractedText = Get-M365OpsExtractedFileText -FilePath $destPath
    }
    catch {
        $extractionError = $_.Exception.Message
    }

    $textPath = "$destPath.extracted.txt"
    if ($extractedText) {
        Set-Content -Path $textPath -Value $extractedText -Encoding UTF8
    }

    $charCount = if ($extractedText) { $extractedText.Length } else { 0 }
    $isEmpty = $charCount -lt 20

    if ($isEmpty) {
        $title = $safeFileName
        $topics = @()
        $summary = if ($extractionError) {
            "Estrazione testo fallita: $extractionError"
        } else {
            "Il file non contiene testo estraibile (es. PDF scansionato come immagine, senza livello di testo) - non catalogato dall'AI."
        }
    }
    else {
        # Troncato a 15000 caratteri per la sola catalogazione (costo/contesto AI) - il testo
        # COMPLETO resta comunque salvato in *.extracted.txt e disponibile per intero quando
        # l'AI lo richiede davvero tramite Get-M365OpsKnowledgeDocumentText.
        $catalogText = if ($extractedText.Length -gt 15000) { $extractedText.Substring(0, 15000) + "`n[...troncato per la catalogazione, il testo completo resta disponibile...]" } else { $extractedText }
        $prompt = @"
Catalogare questo documento per una Knowledge Base aziendale specifica di UN cliente/tenant Microsoft 365. Rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo, in questo formato esatto:
{
  "title": "titolo breve e descrittivo del documento (max 80 caratteri)",
  "topics": ["argomento1", "argomento2", "..."],
  "summary": "riassunto in 2-4 frasi di cosa contiene, pensato per capire SE questo documento e' rilevante per una domanda, senza dover leggere il contenuto completo"
}
Nome file originale: $safeFileName
"@
        try {
            $raw = Invoke-M365OpsAgent -Prompt $prompt -Context $catalogText -Provider $Provider -MaxTokens 800
            $jsonMatch = [regex]::Match($raw, '\{[\s\S]*\}')
            if (-not $jsonMatch.Success) { throw "Nessun JSON nella risposta AI." }
            $parsed = $jsonMatch.Value | ConvertFrom-Json
            $title = if ($parsed.title) { $parsed.title } else { $safeFileName }
            $topics = @($parsed.topics)
            $summary = if ($parsed.summary) { $parsed.summary } else { "(nessun riassunto prodotto)" }
        }
        catch {
            $title = $safeFileName
            $topics = @()
            $summary = "Catalogazione AI fallita ($($_.Exception.Message)) - documento comunque salvato e ricercabile per intero."
        }
    }

    $catalog = @()
    if (Test-Path $catalogPath) {
        try { $catalog = @(Get-Content $catalogPath -Raw | ConvertFrom-Json) } catch { $catalog = @() }
    }
    # Ricarica dello stesso nome file = sostituzione della voce precedente, non duplicato.
    $catalog = @($catalog | Where-Object { $_.FileName -ne $safeFileName })

    $entry = [pscustomobject]@{
        FileName   = $safeFileName
        Title      = $title
        Topics     = $topics
        Summary    = $summary
        UploadedAt = (Get-Date -Format 'o')
        CharCount  = $charCount
    }
    $catalog += $entry
    # -InputObject, MAI in pipeline (bug reale trovato dal vivo il 18/08/2026, stessa classe
    # gia' vista altrove in questo progetto - GET /api/tenants, GET /api/chat/history):
    # "$catalog | ConvertTo-Json" appiattisce un array a un solo elemento in un oggetto NUDO
    # (niente `[...]`), e con un array VUOTO la pipeline non emette nulla, quindi Set-Content
    # a valle non viene mai eseguito - il file resta quello vecchio senza errori.
    ConvertTo-Json -InputObject $catalog -Depth 6 | Set-Content -Path $catalogPath -Encoding UTF8

    Write-Host "Documento '$safeFileName' aggiunto alla Knowledge Base di '$TenantName' ($charCount caratteri estratti)." -ForegroundColor Green
    $entry
}
