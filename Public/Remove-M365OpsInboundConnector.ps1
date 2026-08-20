function Remove-M365OpsInboundConnector {
    <#
    .SYNOPSIS
        Elimina un connettore Inbound. Era Remove-M365OpsReceiveConnector (cmdlet
        on-premises-only, mai esistito in Exchange Online) - vedi nota strutturale in
        Get-M365OpsInboundConnector.ps1.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Remove-InboundConnector -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Connettore Inbound rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
