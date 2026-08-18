function Get-M365OpsSharePointSites {
    <#
    .SYNOPSIS
        Elenca i siti SharePoint del tenant con storage usato/quota e stato di condivisione
        esterna (SharingCapability) - copre in una sola chiamata sia il classico report
        "quali siti hanno la condivisione esterna attiva" sia l'utilizzo storage per sito.
    .NOTES
        Get-PnPTenantSite non include di default i siti OneDrive personali (template SPSPERS) -
        per quelli vedi Get-M365OpsOneDriveUsageReport, un report separato perche' un OneDrive
        personale non e' concettualmente un "sito" per un admin che chiede "elenco siti".

        Verificato dal vivo sia su AppOnly (contoso-test) sia su Delegato (Fabrikam-Prod, 17/08/2026).
        Bug reale trovato sul secondo: su una connessione Delegata (-Interactive) PnP restituisce
        SharingCapability come intero grezzo (0-3), non come nome leggibile ("Disabled",
        "ExternalUserAndGuestSharing", ecc.) come invece fa su AppOnly - stessa proprieta',
        serializzazione diversa a seconda del tipo di connessione. Mappato esplicitamente qui
        cosi' il report e' leggibile in entrambi i casi, invece di mostrare "2" senza contesto.
    #>
    Connect-M365OpsSharePoint
    # Ordine numerico ufficiale Microsoft per questo enum (SPOSharingCapability) - usato solo
    # se la proprieta' arriva come intero grezzo (vedi NOTES), altrimenti si usa il nome che
    # PnP restituisce gia' com'e'.
    $sharingLabels = @('Disabled', 'ExternalUserSharingOnly', 'ExternalUserAndGuestSharing', 'ExistingExternalUserSharingOnly')
    Get-PnPTenantSite | ForEach-Object {
        $sharing = $_.SharingCapability
        $sharingLabel = if ($sharing -is [int] -and $sharing -ge 0 -and $sharing -lt $sharingLabels.Count) { $sharingLabels[$sharing] } else { [string]$sharing }
        $_ | Select-Object Url, Title, Owner, Template, StorageUsageCurrent, StorageQuota, LastContentModifiedDate, LockState, @{N = 'SharingCapability'; E = { $sharingLabel } }
    }
}
