function Set-M365OpsReceiveConnector {
    <#
    .SYNOPSIS
        Modifica un connettore Receive esistente. Passa i parametri da cambiare via
        -ExtraParams (es. RemoteIPRanges, Enabled, AuthMechanism) - se non sei sicuro del
        nome esatto, consulta prima lookup_ms_docs "Set-ReceiveConnector".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-ReceiveConnector @params -ErrorAction Stop
    Write-Host "Connettore Receive aggiornato: $Identity" -ForegroundColor Green
}
