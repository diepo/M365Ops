function Disable-M365OpsAntiPhishRule {
    <#
    .SYNOPSIS
        Disabilita una regola anti-phishing (il criterio collegato resta configurato ma
        smette di applicarsi finche' la regola non viene riabilitata). Cmdlet dedicato, NON
        un parametro di Set-AntiPhishRule (verificato dal vivo il 21/08/2026: quel cmdlet
        non ha un parametro -Enabled).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Disable-AntiPhishRule -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Regola anti-phishing disabilitata: $Identity" -ForegroundColor Green
}
