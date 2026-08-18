function Set-M365OpsSharePointSiteSharing {
    <#
    .SYNOPSIS
        Imposta la modalita' di condivisione esterna di UN sito (SharingCapability) - stesso
        valore letto da Get-M365OpsSharePointSites. Opera dal centro di amministrazione
        (Set-PnPTenantSite), non dal sito stesso.
    #>
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [ValidateSet('Disabled', 'ExternalUserSharingOnly', 'ExternalUserAndGuestSharing', 'ExistingExternalUserSharingOnly')] [string]$SharingCapability
    )
    Connect-M365OpsSharePoint

    Set-PnPTenantSite -Identity $SiteUrl -SharingCapability $SharingCapability

    Write-Host "SharingCapability di $SiteUrl impostata a $SharingCapability" -ForegroundColor Green
    [pscustomobject]@{ SiteUrl = $SiteUrl; SharingCapability = $SharingCapability }
}
