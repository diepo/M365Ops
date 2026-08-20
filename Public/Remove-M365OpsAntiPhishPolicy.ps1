function Remove-M365OpsAntiPhishPolicy {
    <#
    .SYNOPSIS
        Elimina un criterio anti-phishing. Non funziona sul criterio predefinito del sistema
        ("Office365 AntiPhish Default"). Se una regola e' ancora collegata al criterio,
        rimuovi prima quella (Remove-M365OpsAntiPhishRule).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Remove-AntiPhishPolicy -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Criterio anti-phishing rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
