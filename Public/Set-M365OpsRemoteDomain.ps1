function Set-M365OpsRemoteDomain {
    <#
    .SYNOPSIS
        Modifica una voce di dominio remoto esistente ("Default" per l'impostazione
        generale del tenant, o il nome di una voce specifica). Passa i parametri da
        cambiare via -ExtraParams (es. AutoForwardEnabled, AutoReplyEnabled,
        AllowedOOFType) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "Set-RemoteDomain".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-RemoteDomain @params -ErrorAction Stop
    Write-Host "Dominio remoto aggiornato: $Identity" -ForegroundColor Green
}
