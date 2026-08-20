function Enable-M365OpsAntiSpamRule {
    <#
    .SYNOPSIS
        Abilita una regola anti-spam disattivata. Cmdlet dedicato, NON un parametro di
        Set-HostedContentFilterRule (verificato dal vivo il 21/08/2026: quel cmdlet non ha
        un parametro -Enabled).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Enable-HostedContentFilterRule -Identity $Identity -ErrorAction Stop
    Write-Host "Regola anti-spam abilitata: $Identity" -ForegroundColor Green
}
