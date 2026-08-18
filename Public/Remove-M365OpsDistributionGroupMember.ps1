function Remove-M365OpsDistributionGroupMember {
    <#
    .SYNOPSIS
        Rimuove un membro da una distribution list o mail-enabled security group.
        -ExtraParams passa altri parametri nativi di Remove-DistributionGroupMember - se
        non sei sicuro del nome esatto, consulta prima lookup_ms_docs "Remove-DistributionGroupMember".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$Member,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity; Member = $Member; Confirm = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Remove-DistributionGroupMember @params
    Write-Host "$Member rimosso da $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Member = $Member; Removed = $true }
}
