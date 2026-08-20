function Set-M365OpsOutboundConnector {
    <#
    .SYNOPSIS
        Modifica un connettore Outbound esistente. Passa i parametri da cambiare via
        -ExtraParams (es. SmartHosts, Enabled, RecipientDomains) - se non sei sicuro del
        nome esatto, consulta prima lookup_ms_docs "Set-OutboundConnector". Era
        Set-M365OpsSendConnector (cmdlet on-premises-only, mai esistito in Exchange Online) -
        vedi nota strutturale in Get-M365OpsInboundConnector.ps1.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-OutboundConnector @params -ErrorAction Stop
    Write-Host "Connettore Outbound aggiornato: $Identity" -ForegroundColor Green
}
