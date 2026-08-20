function Set-M365OpsAntiPhishPolicy {
    <#
    .SYNOPSIS
        Modifica un criterio anti-phishing esistente. Passa i parametri da cambiare via
        -ExtraParams (es. PhishThresholdLevel, EnableSpoofIntelligence) - se non sei sicuro
        del nome esatto, consulta prima lookup_ms_docs "Set-AntiPhishPolicy".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-AntiPhishPolicy @params -ErrorAction Stop
    Write-Host "Criterio anti-phishing aggiornato: $Identity" -ForegroundColor Green
}
