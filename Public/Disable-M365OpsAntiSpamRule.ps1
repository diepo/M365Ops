function Disable-M365OpsAntiSpamRule {
    <#
    .SYNOPSIS
        Disabilita una regola anti-spam (il criterio collegato resta configurato ma smette
        di applicarsi finche' la regola non viene riabilitata). Cmdlet dedicato, NON un
        parametro di Set-HostedContentFilterRule (verificato dal vivo il 21/08/2026: quel
        cmdlet non ha un parametro -Enabled).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Disable-HostedContentFilterRule -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Regola anti-spam disabilitata: $Identity" -ForegroundColor Green
}
