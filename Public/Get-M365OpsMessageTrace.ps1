function Get-M365OpsMessageTrace {
    <#
    .SYNOPSIS
        Traccia i messaggi transitati in un periodo (dati fino a 90 giorni indietro),
        opzionalmente filtrati per mittente/destinatario. Nessun limite di 10 giorni lato
        chiamante: un intervallo piu' lungo viene incatenato automaticamente in piu' query
        (vedi NOTES) e i risultati tornano uniti come se fosse stata una sola chiamata.
    .NOTES
        Usa Get-MessageTraceV2, non il vecchio Get-MessageTrace: verificato su Microsoft Learn
        il 15/08/2026 che il Message Trace classico e' in dismissione a livello mondiale dal
        1/09/2025 - continuare a chiamare la cmdlet vecchia rischiava di rompersi in silenzio
        proprio mentre serviva di piu'. -ResultSize sostituisce -PageSize (non esiste piu' su
        V2). https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-messagetracev2

        Chunking automatico (17/08/2026): Get-MessageTraceV2 accetta al massimo 10 giorni per
        singola chiamata (limite del servizio, non nostro) - richiesto dall'utente un modo per
        coprire periodi piu' lunghi (es. "ultimi 30 giorni") senza doverlo fare a mano una
        query alla volta. Qui si spezza l'intervallo totale in finestre da 10 giorni, si
        interroga ciascuna e si concatenano i risultati. Ogni finestra fallita singolarmente
        (es. errore temporaneo del servizio) viene segnalata in $script:M365OpsLastReportWarnings
        invece di far fallire l'intera raccolta - meglio un risultato parziale con avviso che
        nessun risultato.

        Tetto righe + campi ridotti (17/08/2026, bug reale): una query di 30 giorni SENZA filtro
        mittente/destinatario su questo tenant ha restituito 3000 righe con OGNI proprieta'
        nativa (MessageTraceId, IP, ecc.) per un JSON di 1.3MB (~330mila token stimati) - una
        SOLA chiamata dell'AI ha superato da sola il limite di contesto del modello (272mila
        token), facendo fallire l'intera risposta con un errore poco chiaro invece di un dato
        anche solo parziale. Rimuovere il tetto di 10 giorni (sopra) senza aggiungere anche un
        tetto sul RISULTATO avrebbe reso il problema peggiore, non risolto. Due contromisure:
        (1) restituisce solo i campi utili per un report (non l'oggetto nativo intero), (2) si
        ferma a $maxTotalRows righe totali con un avviso esplicito invece di continuare a
        incatenare finestre e produrre un payload sempre piu' grande - l'avviso indica
        esplicitamente di restringere il periodo o aggiungere un filtro mittente/destinatario,
        che nel caso reale (query per UNA casella specifica) riduce il volume di un ordine di
        grandezza (55 righe invece di 3000 sullo stesso periodo).

        -MaxTotalRows (17/08/2026): il tetto di 1000 sopra protegge la conversazione con l'IA
        (exo_query passa il risultato COME TESTO nel contesto del modello), ma non e' un limite
        del dato reale - per un export diretto su Excel che i dati grezzi non li fa mai vedere
        all'IA (vedi generate_raw_export in Invoke-M365OpsAgentTools), ha senso poter alzare
        questo tetto. Parametro interno, non esposto nello schema di exo_query.
    #>
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-1),
        [datetime]$EndDate = (Get-Date),
        [string]$SenderAddress,
        [string]$RecipientAddress,
        [int]$MaxTotalRows = 1000
    )
    Connect-M365OpsExchange

    $script:M365OpsLastReportWarnings = $null
    $maxWindowDays = 10
    $maxTotalRows = $MaxTotalRows
    $warnings = @()
    $allResults = @()
    $truncated = $false

    $windowStart = $StartDate
    while ($windowStart -lt $EndDate -and $allResults.Count -lt $maxTotalRows) {
        $windowEnd = $windowStart.AddDays($maxWindowDays)
        if ($windowEnd -gt $EndDate) { $windowEnd = $EndDate }

        $params = @{ StartDate = $windowStart; EndDate = $windowEnd; ResultSize = 1000 }
        if ($SenderAddress) { $params.SenderAddress = $SenderAddress }
        if ($RecipientAddress) { $params.RecipientAddress = $RecipientAddress }

        try {
            $windowResults = @(Get-MessageTraceV2 @params)
            if ($windowResults.Count -ge 1000) { $truncated = $true }
            $allResults += $windowResults
        }
        catch {
            $warnings += "Finestra $($windowStart.ToString('dd/MM/yyyy'))-$($windowEnd.ToString('dd/MM/yyyy')): $($_.Exception.Message)"
        }

        $windowStart = $windowEnd
    }

    if ($allResults.Count -gt $maxTotalRows) { $allResults = $allResults[0..($maxTotalRows - 1)]; $truncated = $true }
    if ($windowStart -lt $EndDate -and $allResults.Count -ge $maxTotalRows) { $truncated = $true }
    if ($truncated) {
        $warnings += "Risultato troncato a $maxTotalRows righe (o a una singola finestra da 1000, limite del servizio): il periodo/filtro scelto ha piu' messaggi di quelli mostrati. Restringi il periodo o aggiungi -SenderAddress/-RecipientAddress per un dato completo."
    }
    if ($warnings.Count -gt 0) { $script:M365OpsLastReportWarnings = $warnings }

    return $allResults | Select-Object MessageTraceId, Received, SenderAddress, RecipientAddress, Subject, Status, Size
}
