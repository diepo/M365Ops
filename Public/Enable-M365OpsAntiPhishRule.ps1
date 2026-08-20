function Enable-M365OpsAntiPhishRule {
    <#
    .SYNOPSIS
        Abilita una regola anti-phishing disattivata. Cmdlet dedicato, NON un parametro di
        Set-AntiPhishRule (verificato dal vivo il 21/08/2026: quel cmdlet non ha un
        parametro -Enabled).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Enable-AntiPhishRule -Identity $Identity -ErrorAction Stop
    Write-Host "Regola anti-phishing abilitata: $Identity" -ForegroundColor Green
}
