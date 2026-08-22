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
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; RecipientFilter = $RecipientFilter; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $grp = New-DynamicDistributionGroup @params
    Write-Host "Dynamic distribution group creato: $($grp.DisplayName)" -ForegroundColor Green
    $grp | Select-Object DisplayName, PrimarySmtpAddress, RecipientFilter
}
