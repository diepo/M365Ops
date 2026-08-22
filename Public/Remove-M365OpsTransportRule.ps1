function Remove-M365OpsTransportRule {
    <#
    .SYNOPSIS
        Elimina una regola di trasporto. -ExtraParams passa altri parametri nativi di
        Remove-TransportRule - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "Remove-TransportRule".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Identity = $Identity; Confirm = $false; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Remove-TransportRule @params
    Write-Host "Regola di trasporto rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
