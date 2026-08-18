function New-M365OpsQuarantinePolicy {
    <#
    .SYNOPSIS
        Crea una policy di quarantena personalizzata (di default TUTTI i permessi utente
        sono false - specifica esplicitamente quelli concessi). -ExtraParams passa altri
        parametri nativi di New-QuarantinePolicy (es. CustomDisclaimer,
        AdminNotificationsEnabled) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "New-QuarantinePolicy". Sintassi verificata contro la documentazione
        ufficiale Microsoft (non a memoria) il 18/08/2026.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [switch]$AllowRelease,
        [switch]$AllowRequestRelease,
        [switch]$AllowDelete,
        [switch]$AllowPreview,
        [switch]$AllowDownload,
        [switch]$AllowViewHeader,
        [switch]$AllowAllowSender,
        [switch]$AllowBlockSender,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $permParams = @{
        PermissionToRelease        = [bool]$AllowRelease
        PermissionToRequestRelease = [bool]$AllowRequestRelease
        PermissionToDelete         = [bool]$AllowDelete
        PermissionToPreview        = [bool]$AllowPreview
        PermissionToDownload       = [bool]$AllowDownload
        PermissionToViewHeader     = [bool]$AllowViewHeader
        PermissionToAllowSender    = [bool]$AllowAllowSender
        PermissionToBlockSender    = [bool]$AllowBlockSender
    }
    # -ErrorAction Stop su entrambe: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1
    # (bug reale 18/08/2026, stessa classe - un errore nativo non terminante farebbe
    # riportare successo anche a scrittura fallita).
    $endUserPermissions = New-QuarantinePermissions @permParams -ErrorAction Stop

    $params = @{ Name = $Name; EndUserQuarantinePermissions = $endUserPermissions }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $policy = New-QuarantinePolicy @params -ErrorAction Stop
    Write-Host "Policy di quarantena creata: $Name" -ForegroundColor Green
    $policy | Select-Object Name, QuarantinePolicyType
}
