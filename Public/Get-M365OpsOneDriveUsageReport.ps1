function Get-M365OpsOneDriveUsageReport {
    <#
    .SYNOPSIS
        Elenca i OneDrive personali del tenant con proprietario, storage usato/quota e ultima
        attivita' - stesso principio di Get-M365OpsSharePointSites ma per i siti OneDrive
        (template SPSPERS), esclusi di default da quella cmdlet perche' concettualmente diversi
        da un "sito" per un admin.
    .NOTES
        Non ancora verificato dal vivo (permesso SharePoint mancante, vedi Get-M365OpsSharePointSites)
        - in particolare il parametro -IncludeOneDriveSites di Get-PnPTenantSite va riconfermato
        con un test reale appena il permesso e' disponibile, la sintassi puo' variare tra
        versioni del modulo PnP.PowerShell.
    #>
    Connect-M365OpsSharePoint
    Get-PnPTenantSite -IncludeOneDriveSites -Filter "Url -like '-my.sharepoint.com/personal/'" |
        Select-Object Url, Owner, Title, StorageUsageCurrent, StorageQuota, LastContentModifiedDate
}
