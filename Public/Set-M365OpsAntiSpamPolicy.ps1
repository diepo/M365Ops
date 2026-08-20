function Set-M365OpsAntiSpamPolicy {
    <#
    .SYNOPSIS
        Modifica un criterio anti-spam esistente. Passa i parametri da cambiare via
        -ExtraParams (es. SpamAction, BulkThreshold, QuarantineRetentionPeriod) - se non sei
        sicuro del nome esatto, consulta prima lookup_ms_docs "Set-HostedContentFilterPolicy".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-HostedContentFilterPolicy @params -ErrorAction Stop
    Write-Host "Criterio anti-spam aggiornato: $Identity" -ForegroundColor Green
}
