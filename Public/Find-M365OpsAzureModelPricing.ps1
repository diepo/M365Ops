function Find-M365OpsAzureModelPricing {
    <#
    .SYNOPSIS
        Tenta di dedurre automaticamente il prezzo (per milione di token) di un deployment
        Azure OpenAI/Foundry interrogando la Azure Retail Prices API pubblica
        (prices.azure.com - nessuna autenticazione richiesta, verificato dal vivo il
        31/08/2026). Richiesto esplicitamente dall'utente: "per il costo... appoggiarsi a
        una base dati del fornitore che comunque credo sia possibile ottenere pubblicamente
        - cerca un modo per dedurla dal tenant e se non fattibile lascia modo alla persona
        di configurarla".

        LIMITE REALE, verificato dal vivo prima di scrivere questa funzione (non
        un'assunzione): il nome di un deployment Azure OpenAI e' un ALIAS scelto liberamente
        dall'utente al momento della creazione (es. "gpt-chat-latest") - non identifica da
        solo quale modello reale ci sia dietro, e l'API dei prezzi non offre nessun modo di
        interrogare "dammi il prezzo di QUESTO specifico deployment". La deduzione qui e'
        quindi un tentativo di corrispondenza per NOME (funziona per deployment il cui nome
        richiama davvero il modello sottostante, es. "gpt-5.4-mini" - verificato dal vivo,
        trova la riga giusta) - se il nome non contiene nulla di riconoscibile (come
        "gpt-chat-latest"), restituisce nessun candidato: e' onestamente meglio ammettere il
        limite e lasciare la configurazione manuale (vedi Set-M365OpsAiPricingConfig) che
        indovinare un prezzo sbagliato spacciandolo per rilevato.

        Preferisce la regione REALE della risorsa (dedotta dall'header di risposta
        x-ms-region di qualunque chiamata riuscita, vedi $Region qui sotto) - se quella
        regione specifica non ha un prezzo per il modello trovato (verificato dal vivo:
        capita, molti modelli hanno prezzo "Data Zone" solo in un sottoinsieme di regioni),
        ripiega sulla tariffa "Global" (suffisso "Gl" nel meterName Azure) quando disponibile,
        segnalandolo chiaramente nel risultato.
    .PARAMETER DeploymentName
        Nome del deployment configurato (es. "gpt-5.4-mini") - usato come termine di ricerca
        contro meterName, non un identificatore diretto.
    .PARAMETER Region
        Nome regione ARM (es. "italynorth") - opzionale, se noto migliora la precisione.
    #>
    param(
        [Parameter(Mandatory)] [string]$DeploymentName,
        [string]$Region
    )

    # Estrazione di un termine di ricerca plausibile dal nome deployment: numeri di versione
    # (5.4, 4.1, 4o...) e qualificatori dimensione (mini/nano/pro) sono cio' che compare nei
    # meterName Azure (es. "5.4 mini") - il resto del nome (prefissi tipo "gpt-", suffissi
    # tipo "-latest"/"-prod") e' rumore scelto dall'utente, mai presente nei meterName reali.
    $normalized = $DeploymentName.ToLower() -replace 'gpt-?', '' -replace '[_]', '-'
    $searchTerm = ($normalized -split '-' | Where-Object { $_ -match '^\d' -or $_ -in @('mini', 'nano', 'pro', 'codex') }) -join ' '
    $searchTerm = $searchTerm.Trim()
    if (-not $searchTerm) {
        return [pscustomobject]@{ Found = $false; Reason = "Nessun termine riconoscibile nel nome deployment '$DeploymentName' - non deducibile automaticamente, configurazione manuale necessaria." }
    }

    try {
        $filterParts = @("serviceName eq 'Foundry Models'", "contains(tolower(meterName), '$searchTerm')")
        $filter = $filterParts -join ' and '
        $uri = "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview&`$filter=$([uri]::EscapeDataString($filter))"
        $allItems = @()
        $pageCount = 0
        while ($uri -and $pageCount -lt 5) {
            $resp = Invoke-RestMethod -Method GET -Uri $uri -TimeoutSec 20 -ErrorAction Stop
            $allItems += @($resp.Items)
            $uri = $resp.NextPageLink
            $pageCount++
        }
    } catch {
        return [pscustomobject]@{ Found = $false; Reason = "Errore interrogando la Azure Retail Prices API: $($_.Exception.Message)" }
    }

    if ($allItems.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Reason = "Nessun prezzo trovato per '$searchTerm' - il deployment potrebbe usare un modello non ancora nel listino pubblico, o il nome non corrisponde a nessun modello riconoscibile." }
    }

    # Scarta le tariffe Batch (elaborazione asincrona differita, piu' economica ma non quella
    # che questa app usa - le chiamate sono sempre sincrone/interattive) e le varianti "pp"
    # (tier separato, provisioned/altro - non il Consumption pay-as-you-go standard che una
    # risorsa Azure OpenAI creata normalmente usa). Convenzione REALE dei meterName Foundry
    # Models, verificata dal vivo il 31/08/2026 (non a memoria, una prima stesura di questa
    # funzione indovinava "Cache"/"Out" e sbagliava sistematicamente): "Inp" = input
    # standard, "cd Inp" = input dalla cache ("cd" = cached, NON "Cache" per esteso), "Opt" =
    # output (NON "Out") - es. "5.4 mini Inp Gl 1M Tokens" / "5.4 mini cd Inp Gl 1M Tokens" /
    # "5.4 mini Opt Gl 1M Tokens".
    $syncItems = @($allItems | Where-Object { $_.meterName -notmatch 'Batch' -and $_.meterName -notmatch '\bpp\b' })
    if ($syncItems.Count -eq 0) { $syncItems = @($allItems | Where-Object { $_.meterName -notmatch 'Batch' }) }
    if ($syncItems.Count -eq 0) { $syncItems = $allItems }

    # "Dz" (Data Zone, prezzo specifico per regione/area geografica) preferito se la regione
    # reale della risorsa ha un prezzo Dz suo; altrimenti "Gl" (Global Standard) - che NON e'
    # un'approssimazione quando lo si usa: e' un prezzo REALMENTE uniforme in ogni regione per
    # costruzione (verificato dal vivo: stesso identico retailPrice in decine di regioni
    # diverse), quindi resta un dato accurato al 100% per un deployment che (come verificato
    # per questo tenant) risulta servito in una regione priva di prezzo Dz proprio.
    $dzItems = if ($Region) { @($syncItems | Where-Object { $_.armRegionName -eq $Region -and $_.meterName -match '\bDz\b' }) } else { @() }
    $glItems = @($syncItems | Where-Object { $_.meterName -match '\bGl\b' })
    $usedGlobalTier = $false
    if ($dzItems.Count -gt 0) {
        $regionItems = $dzItems
    } elseif ($glItems.Count -gt 0) {
        $regionItems = $glItems
        $usedGlobalTier = $true
    } else {
        # Ultima spiaggia: qualunque regione Data Zone disponibile, meglio di niente ma da
        # segnalare chiaramente come stima meno affidabile (prezzo di un'ALTRA area
        # geografica, potrebbe non corrispondere davvero a quello applicato).
        $regionItems = $syncItems
        $usedGlobalTier = $true
    }

    $inputEntry = $regionItems | Where-Object { $_.meterName -match 'Inp' -and $_.meterName -notmatch '\bcd\b' } | Select-Object -First 1
    $cachedEntry = $regionItems | Where-Object { $_.meterName -match '\bcd\b' -and $_.meterName -match 'Inp' } | Select-Object -First 1
    $outputEntry = $regionItems | Where-Object { $_.meterName -match 'Opt' } | Select-Object -First 1

    if (-not $inputEntry -and -not $outputEntry) {
        return [pscustomobject]@{ Found = $false; Reason = "Trovate $($allItems.Count) righe di prezzo per '$searchTerm' ma nessuna riconoscibile come tariffa di input/output standard - verificare manualmente su prices.azure.com." }
    }

    $confidence = if ($dzItems.Count -gt 0 -and $inputEntry -and $outputEntry) {
        'alta (Data Zone, prezzo specifico per questa regione)'
    } elseif ($usedGlobalTier -and $glItems.Count -gt 0 -and $inputEntry -and $outputEntry) {
        'alta (Global Standard - stesso prezzo in ogni regione per definizione)'
    } elseif ($inputEntry -and $outputEntry) {
        'bassa (nessun prezzo Data Zone o Global trovato per questa ricerca - prezzo di un''altra regione, potrebbe non corrispondere)'
    } else {
        'bassa (dati parziali - manca input o output)'
    }

    [pscustomobject]@{
        Found               = $true
        SearchTerm          = $searchTerm
        InputPer1M          = if ($inputEntry) { $inputEntry.retailPrice } else { $null }
        CachedInputPer1M    = if ($cachedEntry) { $cachedEntry.retailPrice } else { $null }
        OutputPer1M         = if ($outputEntry) { $outputEntry.retailPrice } else { $null }
        # Se e' la tariffa Global, il nome della PRIMA regione trovata sarebbe fuorviante (il
        # prezzo e' identico ovunque per definizione, non "quella regione in particolare") -
        # mostrato invece come "Global" esplicito.
        RegionUsed          = if ($dzItems.Count -gt 0) { $regionItems[0].armRegionName } elseif ($usedGlobalTier -and $glItems.Count -gt 0) { 'Global' } elseif ($regionItems.Count -gt 0) { $regionItems[0].armRegionName } else { $null }
        UsedGlobalTier      = $usedGlobalTier
        MatchedProductName  = if ($inputEntry) { $inputEntry.productName } elseif ($outputEntry) { $outputEntry.productName } else { $null }
        Confidence          = $confidence
    }
}
