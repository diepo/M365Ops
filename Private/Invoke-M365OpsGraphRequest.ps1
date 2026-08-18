function Invoke-M365OpsGraphRequest {
    <#
    .SYNOPSIS
        Wrapper unico per tutte le chiamate Graph del modulo: aggiunge il bearer token,
        sceglie v1.0 o beta, normalizza gli errori.
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
        return Invoke-RestMethod @params -ErrorAction Stop
    }
    catch {
        $detail = $_.ErrorDetails.Message
        throw "Graph request failed [$Method $Path]: $($_.Exception.Message)`n$detail"
    }
}
