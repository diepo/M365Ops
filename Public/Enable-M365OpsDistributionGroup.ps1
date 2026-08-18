function Enable-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        Riabilita la posta su un gruppo esistente gia' mail-disabled (operazione rara,
        soprattutto per scenari ibridi con Active Directory on-premise sincronizzato -
        su un gruppo cloud-only normalmente non serve mai). -ExtraParams passa altri
        parametri nativi di Enable-DistributionGroup - se non sei sicuro del nome esatto,
        consulta prima lookup_ms_docs "Enable-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in Set-M365OpsDistributionGroup.ps1 (bug reale 18/08/2026).
    Enable-DistributionGroup @params -ErrorAction Stop
    Write-Host "Gruppo riabilitato alla posta: $Identity" -ForegroundColor Green
}
