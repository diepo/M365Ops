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

    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026), qui sul modulo PnP.PowerShell.
    Set-PnPTenantSite -Identity $SiteUrl -SharingCapability $SharingCapability -ErrorAction Stop

    Write-Host "SharingCapability di $SiteUrl impostata a $SharingCapability" -ForegroundColor Green
    [pscustomobject]@{ SiteUrl = $SiteUrl; SharingCapability = $SharingCapability }
}
