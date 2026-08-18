function Set-M365OpsQuarantinePolicy {
    <#
    .SYNOPSIS
        Modifica i permessi utente di una policy di quarantena esistente. Passa solo i
        permessi da cambiare esplicitamente a $true/$false via -ExtraParams (chiave
        EndUserQuarantinePermissions, valore da costruire con New-QuarantinePermissions) o
        altri parametri nativi di Set-QuarantinePolicy - se non sei sicuro del nome esatto,
        consulta prima lookup_ms_docs "Set-QuarantinePolicy". Sintassi verificata contro la
        documentazione ufficiale Microsoft (non a memoria) il 18/08/2026.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-QuarantinePolicy @params -ErrorAction Stop
    Write-Host "Policy di quarantena aggiornata: $Identity" -ForegroundColor Green
}
