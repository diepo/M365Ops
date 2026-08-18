function Remove-M365OpsDynamicDistributionGroup {
    <#
    .SYNOPSIS
        Elimina un gruppo di distribuzione dinamico. -ExtraParams passa altri parametri
        nativi di Remove-DynamicDistributionGroup - se non sei sicuro del nome esatto,
        consulta prima lookup_ms_docs "Remove-DynamicDistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity; Confirm = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in Set-M365OpsDistributionGroup.ps1 (bug reale 18/08/2026).
    Remove-DynamicDistributionGroup @params -ErrorAction Stop
    Write-Host "Dynamic distribution group rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
