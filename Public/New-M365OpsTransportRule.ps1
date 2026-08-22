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
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Name = $Name; Enabled = $false; ErrorAction = 'Stop' }
    if ($Comments) { $params.Comments = $Comments }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $rule = New-TransportRule @params
    Write-Host "Regola di trasporto creata (disabilitata): $($rule.Name)" -ForegroundColor Green
    $rule | Select-Object Name, State, Priority
}
