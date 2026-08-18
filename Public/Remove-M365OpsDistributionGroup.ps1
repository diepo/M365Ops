function Remove-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        Elimina una distribution list o mail-enabled security group. -ExtraParams passa
        altri parametri nativi di Remove-DistributionGroup (es. IgnoreDefaultScope,
        BypassSecurityGroupManagerCheck) - se non sei sicuro del nome esatto, consulta
        prima lookup_ms_docs "Remove-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity; Confirm = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Remove-DistributionGroup @params
    Write-Host "Gruppo rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
