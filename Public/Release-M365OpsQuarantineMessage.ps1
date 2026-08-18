function Release-M365OpsQuarantineMessage {
    <#
    .SYNOPSIS
        Rilascia un messaggio dalla quarantena ai destinatari originali (Identity ottenuta da
        Get-M365OpsQuarantineMessages). -AllowSender aggiunge anche il mittente alla Tenant
        Allow List, cosi' i prossimi messaggi dello stesso mittente non finiscono piu' in
        quarantena.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [switch]$AllowSender
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity; ReleaseToAll = $true }
    if ($AllowSender) { $params.AllowSender = $true }
    Release-QuarantineMessage @params
    Write-Host "Messaggio rilasciato dalla quarantena: $Identity" -ForegroundColor Green
}
