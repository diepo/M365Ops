function Get-M365OpsSharePointSitePermissions {
    <#
    .SYNOPSIS
        Elenca chi ha accesso a un sito SharePoint: amministratori della raccolta siti +
        membri dei gruppi standard Proprietari/Membri/Visitatori. Non scende a livello di
        singolo file/cartella (permessi granulari) - e' il livello "chi amministra/usa questo
        sito", equivalente per SharePoint a cosa Get-M365OpsMailboxPermissions fa per Exchange.
    .PARAMETER SiteUrl
        URL completo del sito (es. da Get-M365OpsSharePointSites -> campo Url) - mai indovinato,
        va sempre preso da un elenco siti reale.
    .NOTES
        Non ancora verificato dal vivo (permesso SharePoint mancante, vedi Get-M365OpsSharePointSites).
    #>
    param([Parameter(Mandatory)] [string]$SiteUrl)

    Connect-M365OpsSharePoint -SiteUrl $SiteUrl

    $admins = @(Get-PnPSiteCollectionAdmin | Select-Object @{N = 'Ruolo'; E = { 'Amministratore raccolta siti' } }, Title, Email, LoginName)

    $groupMembers = foreach ($groupSuffix in @('Owners', 'Members', 'Visitors')) {
        $group = Get-PnPGroup | Where-Object { $_.Title -like "*$groupSuffix*" } | Select-Object -First 1
        if ($group) {
            Get-PnPGroupMember -Group $group.Title | Select-Object @{N = 'Ruolo'; E = { $group.Title } }, Title, Email, LoginName
        }
    }

    @($admins) + @($groupMembers)
}
