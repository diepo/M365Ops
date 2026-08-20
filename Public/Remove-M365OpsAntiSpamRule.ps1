function Remove-M365OpsAntiSpamRule {
    <#
    .SYNOPSIS
        Elimina una regola anti-spam (il criterio collegato NON viene toccato, resta ma
        smette di applicarsi a chiunque finche' non viene ricollegato a una nuova regola).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Remove-HostedContentFilterRule -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Regola anti-spam rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
