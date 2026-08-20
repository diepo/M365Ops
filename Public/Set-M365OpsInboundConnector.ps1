function Set-M365OpsInboundConnector {
    <#
    .SYNOPSIS
        Modifica un connettore Inbound esistente. Passa i parametri da cambiare via
        -ExtraParams (es. SenderDomains, Enabled, RequireTls) - se non sei sicuro del nome
        esatto, consulta prima lookup_ms_docs "Set-InboundConnector". Era
        Set-M365OpsReceiveConnector (cmdlet on-premises-only, mai esistito in Exchange
        Online) - vedi nota strutturale in Get-M365OpsInboundConnector.ps1.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-InboundConnector @params -ErrorAction Stop
    Write-Host "Connettore Inbound aggiornato: $Identity" -ForegroundColor Green
}
