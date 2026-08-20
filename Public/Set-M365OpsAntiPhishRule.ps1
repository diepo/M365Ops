function Set-M365OpsAntiPhishRule {
    <#
    .SYNOPSIS
        Modifica una regola anti-phishing esistente (es. RecipientDomainIs, Priority) via
        -ExtraParams - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "Set-AntiPhishRule". Per abilitare/disabilitare usa invece
        Enable-M365OpsAntiPhishRule/Disable-M365OpsAntiPhishRule: verificato dal vivo il
        21/08/2026 (stesso caso di Set-HostedContentFilterRule) che Set-AntiPhishRule NON
        ha un parametro -Enabled.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-AntiPhishRule @params -ErrorAction Stop
    Write-Host "Regola anti-phishing aggiornata: $Identity" -ForegroundColor Green
}
