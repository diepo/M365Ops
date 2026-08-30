function Invoke-M365OpsGraphRequest {
    <#
    .SYNOPSIS
        Wrapper unico per tutte le chiamate Graph del modulo: aggiunge il bearer token,
        sceglie v1.0 o beta, normalizza gli errori, e segue automaticamente la paginazione
        (@odata.nextLink) sulle GET che restituiscono una collezione.
    .NOTES
        Paginazione aggiunta il 31/08/2026 (bug SISTEMICO trovato dalla maratona di stress-test:
        nessuna delle funzioni Get-* di questo modulo che elencano dispositivi/policy/template/
        definizioni Intune gestiva @odata.nextLink - su un tenant con piu' di una pagina di
        risultati (es. il catalogo Get-M365OpsConfigurationSettingDefinitions, "decine di
        migliaia di voci" per sua stessa docstring), gli elementi oltre la prima pagina
        sparivano in silenzio, nessun errore, nessun avviso - una ricerca per parola chiave
        poteva mancare l'elemento corretto solo perche' non era nella prima pagina). Corretto UNA
        VOLTA sola qui, nel trasporto condiviso, invece che in ognuna delle ~9 funzioni chiamanti
        colpite - stesso principio "un solo posto per una regola condivisa" gia' seguito altrove
        in questo progetto.

        Segue nextLink SOLO per GET (le scritture non restituiscono mai una collezione paginata
        con questa semantica) e SOLO quando la risposta ha davvero una forma paginata (proprieta'
        'value', con o senza 'nextLink' - una GET su una singola risorsa, es. /users/{id}, non ha
        mai 'value' e passa quindi invariata, ZERO rischio di regressione per quel caso, che resta
        la maggioranza delle chiamate in questo modulo). Le pagine vengono unite in un unico
        array in '.value' sull'oggetto restituito, cosi' ogni chiamante che gia' legge '.value'
        continua a funzionare identico, solo con TUTTI gli elementi invece di una prima pagina
        parziale. Cap di sicurezza a 200 pagine (a 100 elementi/pagina tipici di Graph, oltre
        20.000 elementi) - se superato, lancia un errore chiaro invece di continuare
        all'infinito o troncare in silenzio, coerente col principio "mai un troncamento muto"
        gia' seguito per Get-M365OpsMessageTrace.ps1 in questo stesso progetto.
    #>
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        # Deliberatamente non tipizzato [hashtable]: i corpi costruiti a mano nel modulo sono
        # hashtable, ma il corpo di una scrittura proposta dall'AI (propose_graph_write) arriva
        # da JSON deserializzato (ConvertFrom-Json) ed e' un PSCustomObject, anche annidato
        # (es. passwordProfile) - un parametro tipizzato [hashtable] rifiuta il binding e fallisce
        # con un errore di legatura argomenti invece di eseguire la richiesta (bug reale, Server.ps1
        # ramo 'LokkaWrite' Delegated). ConvertTo-Json sotto funziona identicamente su entrambi i tipi.
        $Body,
        [switch]$Beta
    )

    $token = Get-M365OpsToken
    $base = if ($Beta) { "https://graph.microsoft.com/beta" } else { "https://graph.microsoft.com/v1.0" }
    $headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

    $params = @{
        Method  = $Method
        Uri     = "$base$Path"
        Headers = $headers
    }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 8) }

    try {
        $result = Invoke-RestMethod @params -ErrorAction Stop
    }
    catch {
        $detail = $_.ErrorDetails.Message
        throw "Graph request failed [$Method $Path]: $($_.Exception.Message)`n$detail"
    }

    if ($Method -ne 'GET' -or -not $result -or -not ($result.PSObject.Properties.Name -contains 'value')) {
        return $result
    }

    $allItems = [System.Collections.Generic.List[object]]::new()
    if ($result.value) { $allItems.AddRange(@($result.value)) }
    $nextLink = $result.'@odata.nextLink'
    $pageCount = 1
    while ($nextLink) {
        $pageCount++
        if ($pageCount -gt 200) {
            throw "Graph request [$Method $Path] ha superato 200 pagine di risultati (oltre ~20000 elementi tipici) senza esaurire @odata.nextLink - interrotto per sicurezza invece di continuare all'infinito. Se e' un caso legittimo di tenant molto grande, restringi la richiesta con `$filter/`$select o contatta chi mantiene il modulo per alzare il limite consapevolmente."
        }
        try {
            # nextLink e' gia' un URL assoluto completo restituito da Graph - mai ricomposto con
            # $base, che lo raddoppierebbe.
            $pageResult = Invoke-RestMethod -Method GET -Uri $nextLink -Headers $headers -ErrorAction Stop
        }
        catch {
            $detail = $_.ErrorDetails.Message
            throw "Graph request failed while paginating [$Method $Path], pagina $pageCount ($nextLink): $($_.Exception.Message)`n$detail"
        }
        if ($pageResult.value) { $allItems.AddRange(@($pageResult.value)) }
        $nextLink = $pageResult.'@odata.nextLink'
    }

    # '.value' sostituito con l'unione di tutte le pagine; ogni altra proprieta' del primo
    # risultato (es. '@odata.context') resta invariata - '@odata.nextLink' rimosso perche' e'
    # gia' stato interamente consumato qui, non deve piu' comparire come "ce n'e' ancora".
    $result | Add-Member -NotePropertyName value -NotePropertyValue $allItems.ToArray() -Force
    if ($result.PSObject.Properties.Name -contains '@odata.nextLink') {
        $result.PSObject.Properties.Remove('@odata.nextLink')
    }
    return $result
}
