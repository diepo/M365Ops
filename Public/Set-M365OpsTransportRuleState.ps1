function Set-M365OpsTransportRuleState {
    <#
    .SYNOPSIS
        Abilita o disabilita una regola di trasporto esistente. -ExtraParams passa altri
        parametri nativi di Enable-TransportRule/Disable-TransportRule - se non sei sicuro
        del nome esatto, consulta prima lookup_ms_docs "Set-TransportRule".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [bool]$Enabled,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Identity = $Identity; Confirm = $false; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    if ($Enabled) { Enable-TransportRule @params }
    else { Disable-TransportRule @params }
    Write-Host "Regola $Identity impostata su Enabled=$Enabled" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Enabled = $Enabled }
}
