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

        ALIAS "MOBILI" (31/08/2026, generalizzazione della scoperta fatta dal vivo per
        "gpt-chat-latest"): un deployment il cui nome NON richiama alcun modello (nessun
        numero di versione/mini/nano/pro/codex) non e' per forza indeducibile - puo' essere
        un alias che Azure fa puntare a un modello reale, scopribile dal vivo con una singola
        chiamata di chat minima: la risposta include l'header 'x-ms-served-model' (es.
        "gpt-chat-latest-2026-08-06" - il nome vero, con la data dello snapshot servito in
        quel momento). Verificato dal vivo che quel nome, ripulito del prefisso "gpt-" e
        della data finale, e' esattamente il termine che compare nei meterName Azure (es.
        "chat-latest 08062026 Inp Gl 1M Tokens" - la data riformattata MMGGAAAA senza
        separatori, non AAAA-MM-GG). $ServedModelHint (opzionale, chi chiama lo passa se ha
        gia' fatto quella chiamata) attiva questo secondo tentativo di ricerca, PRIMA di
        quello basato sul nome deployment - se non porta a nessun risultato (es. lo snapshot
        con quella data specifica non e' piu'/non e' ancora nel listino pubblico), si
        ripiega sullo stesso termine SENZA il vincolo di data, poi sul nome deployment come
        gia' prima. Ogni tentativo e' riportato in $MatchStrategy nel risultato, per
        trasparenza su quale euristica ha funzionato.
    .PARAMETER DeploymentName
        Nome del deployment configurato (es. "gpt-5.4-mini") - usato come termine di ricerca
        contro meterName, non un identificatore diretto.
    .PARAMETER Region
        Nome regione ARM (es. "italynorth") - opzionale, se noto migliora la precisione.
    .PARAMETER ServedModelHint
        Valore dell'header 'x-ms-served-model' di una chiamata live riuscita verso il
        deployment (es. "gpt-chat-latest-2026-08-06") - opzionale, se noto permette di
        risolvere alias che il solo nome deployment non rivelerebbe (vedi SYNOPSIS).
    #>
    param(
        [Parameter(Mandatory)] [string]$DeploymentName,
        [string]$Region,
        [string]$ServedModelHint
    )

    # Costruisce la lista ORDINATA di tentativi di ricerca da provare, dal piu' preciso al
    # piu' generico - il primo che restituisce almeno una riga di prezzo vince (vedi ciclo
    # sotto). Ogni tentativo e' {Term, RequireAll (altri termini che DEVONO comparire nello
    # stesso meterName, es. la data dello snapshot), Strategy (etichetta per trasparenza)}.
    $attempts = @()

    if ($ServedModelHint) {
        $hint = $ServedModelHint.ToLower().Trim()
        if ($hint -match '^(?<base>.+?)-(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})$') {
            $base = $Matches.base -replace '^gpt-?', ''
            $dateToken = "$($Matches.m)$($Matches.d)$($Matches.y)"
            if ($base) {
                $attempts += [pscustomobject]@{ Term = $base; RequireAll = @($dateToken); Strategy = 'modello reale rilevato dal vivo (snapshot esatto)' }
                $attempts += [pscustomobject]@{ Term = $base; RequireAll = @(); Strategy = 'modello reale rilevato dal vivo (famiglia, snapshot non nel listino)' }
            }
        } else {
            $base = $hint -replace '^gpt-?', ''
            if ($base) { $attempts += [pscustomobject]@{ Term = $base; RequireAll = @(); Strategy = 'modello reale rilevato dal vivo' } }
        }
    }

    # Estrazione di un termine di ricerca plausibile dal nome deployment: numeri di versione
    # (5.4, 4.1, 4o...) e qualificatori dimensione (mini/nano/pro) sono cio' che compare nei
    # meterName Azure (es. "5.4 mini") - il resto del nome (prefissi tipo "gpt-", suffissi
    # tipo "-latest"/"-prod") e' rumore scelto dall'utente, mai presente nei meterName reali.
    $normalized = $DeploymentName.ToLower() -replace 'gpt-?', '' -replace '[_]', '-'
    $deploymentTerm = ($normalized -split '-' | Where-Object { $_ -match '^\d' -or $_ -in @('mini', 'nano', 'pro', 'codex') }) -join ' '
    $deploymentTerm = $deploymentTerm.Trim()
    if ($deploymentTerm) { $attempts += [pscustomobject]@{ Term = $deploymentTerm; RequireAll = @(); Strategy = 'nome deployment' } }

    if ($attempts.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Reason = "Nessun termine riconoscibile ne' nel nome deployment '$DeploymentName' ne' nel modello rilevato dal vivo - non deducibile automaticamente, configurazione manuale necessaria." }
    }

    $allItems = @()
    $searchTerm = $null
    $matchStrategy = $null
    $lastError = $null
    foreach ($attempt in $attempts) {
        try {
            $filterParts = @("serviceName eq 'Foundry Models'", "contains(tolower(meterName), '$($attempt.Term)')")
            foreach ($req in $attempt.RequireAll) { $filterParts += "contains(meterName, '$req')" }
            $filter = $filterParts -join ' and '
            $uri = "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview&`$filter=$([uri]::EscapeDataString($filter))"
            $items = @()
            $pageCount = 0
            while ($uri -and $pageCount -lt 5) {
                $resp = Invoke-RestMethod -Method GET -Uri $uri -TimeoutSec 20 -ErrorAction Stop
                $items += @($resp.Items)
                $uri = $resp.NextPageLink
                $pageCount++
            }
        } catch {
            $lastError = $_.Exception.Message
            continue
        }
        if ($items.Count -gt 0) {
            $allItems = $items
            $searchTerm = $attempt.Term
            $matchStrategy = $attempt.Strategy
            break
        }
    }

    if ($lastError -and $allItems.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Reason = "Errore interrogando la Azure Retail Prices API: $lastError" }
    }

    if ($allItems.Count -eq 0) {
        $triedTerms = ($attempts | ForEach-Object { $_.Term } | Select-Object -Unique) -join ', '
        return [pscustomobject]@{ Found = $false; Reason = "Nessun prezzo trovato (termini provati: $triedTerms) - il deployment potrebbe usare un modello non ancora nel listino pubblico, o il nome non corrisponde a nessun modello riconoscibile." }
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
        return [pscustomobject]@{ Found = $false; Reason = "Trovate $($allItems.Count) righe di prezzo per '$searchTerm' (strategia: $matchStrategy) ma nessuna riconoscibile come tariffa di input/output standard - verificare manualmente su prices.azure.com." }
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
        MatchStrategy       = $matchStrategy
        ServedModel         = $ServedModelHint
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
