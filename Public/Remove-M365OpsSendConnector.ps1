function Remove-M365OpsSendConnector {
    <#
    .SYNOPSIS
        Elimina un connettore Send.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Remove-SendConnector -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Connettore Send rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
