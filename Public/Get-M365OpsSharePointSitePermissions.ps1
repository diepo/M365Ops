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

    # Ogni area (admin raccolta siti + i tre gruppi standard) nel proprio try/catch (26/08/2026,
    # bug reale trovato durante lo stress-test mirato al pattern "un passo fallito blocca i passi
    # fratelli indipendenti" - stesso schema gia' corretto 3 volte in questa maratona). PRIMA di
    # questo fix, sia Get-PnPSiteCollectionAdmin sia il ciclo sui tre gruppi vivevano senza
    # protezione: un fallimento su UNO dei quattro controlli (es. il gruppo "Visitors" con troppi
    # membri che va in timeout, o un permesso mancante su un solo gruppo) lanciava un'eccezione
    # che usciva dall'intera funzione, perdendo anche i risultati degli altri controlli GIA'
    # raggiunti con successo (es. Owners e Members letti correttamente prima che Visitors
    # fallisse) - il chiamante non riceveva alcun risultato invece di un elenco parziale con una
    # nota chiara su cosa non e' stato possibile leggere.
    $results = @()
    try {
        $results += @(Get-PnPSiteCollectionAdmin -ErrorAction Stop | Select-Object @{N = 'Ruolo'; E = { 'Amministratore raccolta siti' } }, Title, Email, LoginName)
    }
    catch {
        $results += [pscustomobject]@{ Ruolo = 'Amministratore raccolta siti'; Title = $null; Email = $null; LoginName = "Lettura fallita: $($_.Exception.Message)" }
    }

    foreach ($groupSuffix in @('Owners', 'Members', 'Visitors')) {
        try {
            $group = Get-PnPGroup -ErrorAction Stop | Where-Object { $_.Title -like "*$groupSuffix*" } | Select-Object -First 1
            if ($group) {
                $results += @(Get-PnPGroupMember -Group $group.Title -ErrorAction Stop | Select-Object @{N = 'Ruolo'; E = { $group.Title } }, Title, Email, LoginName)
            }
        }
        catch {
            $results += [pscustomobject]@{ Ruolo = $groupSuffix; Title = $null; Email = $null; LoginName = "Lettura fallita: $($_.Exception.Message)" }
        }
    }

    $results
}
