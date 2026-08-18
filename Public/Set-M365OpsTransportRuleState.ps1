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
    $params = @{ Identity = $Identity; Confirm = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    if ($Enabled) { Enable-TransportRule @params }
    else { Disable-TransportRule @params }
    Write-Host "Regola $Identity impostata su Enabled=$Enabled" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Enabled = $Enabled }
}
