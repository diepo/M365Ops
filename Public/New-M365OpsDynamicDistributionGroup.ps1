function New-M365OpsDynamicDistributionGroup {
    <#
    .SYNOPSIS
        Crea un gruppo di distribuzione dinamico. Il filtro va passato in sintassi
        OPATH di Exchange, es: "(Department -eq 'Vendite')". -ExtraParams passa altri
        parametri nativi di New-DynamicDistributionGroup (es. ManagedBy, RecipientContainer)
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "New-DynamicDistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [Parameter(Mandatory)] [string]$RecipientFilter,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; RecipientFilter = $RecipientFilter }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $grp = New-DynamicDistributionGroup @params
    Write-Host "Dynamic distribution group creato: $($grp.DisplayName)" -ForegroundColor Green
    $grp | Select-Object DisplayName, PrimarySmtpAddress, RecipientFilter
}
