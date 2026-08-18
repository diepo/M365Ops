function Set-M365OpsDynamicDistributionGroup {
    <#
    .SYNOPSIS
        Modifica un gruppo di distribuzione dinamico esistente (nome o filtro membri - sintassi
        OPATH di Exchange, es: "(Department -eq 'Vendite')"). Passa solo i parametri da
        cambiare. -ExtraParams passa altri parametri nativi di Set-DynamicDistributionGroup
        (es. ManagedBy) - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "Set-DynamicDistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string]$DisplayName,
        [string]$RecipientFilter,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    if ($DisplayName) { $params.DisplayName = $DisplayName }
    if ($RecipientFilter) { $params.RecipientFilter = $RecipientFilter }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    # -ErrorAction Stop: senza, un errore nativo non terminante farebbe riportare successo
    # anche a scrittura fallita (bug reale trovato dal vivo il 18/08/2026 su un cmdlet gemello).
    Set-DynamicDistributionGroup @params -ErrorAction Stop
    Write-Host "Dynamic distribution group aggiornato: $Identity" -ForegroundColor Green
    Get-DynamicDistributionGroup -Identity $Identity | Select-Object DisplayName, PrimarySmtpAddress, RecipientFilter
}
