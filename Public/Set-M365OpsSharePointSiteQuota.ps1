function Set-M365OpsSharePointSiteQuota {
    <#
    .SYNOPSIS
        Imposta la quota di storage di un sito SharePoint, in GB. Opera dal centro di
        amministrazione (Set-PnPTenantSite), non dal sito stesso.
    #>
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [int]$QuotaGB
    )
    Connect-M365OpsSharePoint

    $quotaMB = $QuotaGB * 1024
    Set-PnPTenantSite -Identity $SiteUrl -StorageMaximumLevel $quotaMB

    Write-Host "Quota di $SiteUrl impostata a $QuotaGB GB" -ForegroundColor Green
    [pscustomobject]@{ SiteUrl = $SiteUrl; QuotaGB = $QuotaGB }
}
