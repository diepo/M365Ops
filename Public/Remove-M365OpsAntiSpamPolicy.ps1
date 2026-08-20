function Remove-M365OpsAntiSpamPolicy {
    <#
    .SYNOPSIS
        Elimina un criterio anti-spam. Non funziona sul criterio predefinito del sistema
        ("Default"), stesso limite di Remove-M365OpsQuarantinePolicy. Se una regola e' ancora
        collegata al criterio, rimuovi prima quella (Remove-M365OpsAntiSpamRule).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Remove-HostedContentFilterPolicy -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Criterio anti-spam rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
