function Remove-M365OpsReceiveConnector {
    <#
    .SYNOPSIS
        Elimina un connettore Receive.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Remove-ReceiveConnector -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Connettore Receive rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
