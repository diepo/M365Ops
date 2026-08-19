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
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026), qui sul modulo PnP.PowerShell.
    Set-PnPTenantSite -Identity $SiteUrl -StorageMaximumLevel $quotaMB -ErrorAction Stop

    Write-Host "Quota di $SiteUrl impostata a $QuotaGB GB" -ForegroundColor Green
    [pscustomobject]@{ SiteUrl = $SiteUrl; QuotaGB = $QuotaGB }
}
