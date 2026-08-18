function New-M365OpsTransportRule {
    <#
    .SYNOPSIS
        Crea una regola di trasporto (mail flow rule). Creata DISABILITATA per default -
        va attivata esplicitamente con Set-M365OpsTransportRuleState dopo verifica.
        Condizioni/azioni (es. From, SentTo, RedirectMessageTo) vanno passate in -ExtraParams,
        con la stessa sintassi nativa di New-TransportRule.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Comments,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; Enabled = $false }
    if ($Comments) { $params.Comments = $Comments }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $rule = New-TransportRule @params
    Write-Host "Regola di trasporto creata (disabilitata): $($rule.Name)" -ForegroundColor Green
    $rule | Select-Object Name, State, Priority
}
