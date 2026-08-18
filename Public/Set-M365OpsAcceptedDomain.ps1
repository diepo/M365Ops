function Set-M365OpsAcceptedDomain {
    <#
    .SYNOPSIS
        Modifica un dominio accettato esistente (es. MakeDefault per impostarlo come
        dominio predefinito del tenant). Passa i parametri da cambiare via -ExtraParams -
        se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "Set-AcceptedDomain".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-AcceptedDomain @params -ErrorAction Stop
    Write-Host "Dominio accettato aggiornato: $Identity" -ForegroundColor Green
}
