function Remove-M365OpsAntiPhishRule {
    <#
    .SYNOPSIS
        Elimina una regola anti-phishing (il criterio collegato NON viene toccato, resta ma
        smette di applicarsi a chiunque finche' non viene ricollegato a una nuova regola).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Remove-AntiPhishRule -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Regola anti-phishing rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
