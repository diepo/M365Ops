function Set-M365OpsSendConnector {
    <#
    .SYNOPSIS
        Modifica un connettore Send esistente. Passa i parametri da cambiare via
        -ExtraParams (es. SmartHosts, Enabled, AddressSpaces) - se non sei sicuro del nome
        esatto, consulta prima lookup_ms_docs "Set-SendConnector".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-SendConnector @params -ErrorAction Stop
    Write-Host "Connettore Send aggiornato: $Identity" -ForegroundColor Green
}
