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
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026) - questo file era sfuggito a una prima
    # scansione sistematica del progetto perche' usa i verbi nativi "Release"/"Delete", non
    # coperti dal filtro di quella scansione (limitato a New/Set/Remove/Add/Enable/Disable/
    # Grant/Revoke/Update).
    $params = @{ Identity = $Identity; ReleaseToAll = $true; ErrorAction = 'Stop' }
    if ($AllowSender) { $params.AllowSender = $true }
    Release-QuarantineMessage @params
    Write-Host "Messaggio rilasciato dalla quarantena: $Identity" -ForegroundColor Green
}
