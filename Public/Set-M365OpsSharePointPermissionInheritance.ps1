function Set-M365OpsSharePointPermissionInheritance {
    <#
    .SYNOPSIS
        Interrompe (permessi unici da qui in poi) o ripristina (torna a ereditare dal sito
        padre) l'ereditarieta' dei permessi sulla web root di un sito SharePoint.
    .NOTES
        Bug reale trovato dal vivo il 18/08/2026: Set-PnPWeb -BreakRoleInheritance/
        -ResetRoleInheritance NON esistono in PnP.PowerShell 3.1.0 (rimossi rispetto a versioni
        precedenti della libreria) - falliscono con "A parameter cannot be found that matches
        parameter name". L'unica via rimasta e' la REST API diretta via Invoke-PnPSPRestMethod,
        che pero' richiede un URL ASSOLUTO: un percorso relativo (es. "_api/web/...") produce
        "invalid request URI" invece del vero errore SharePoint, mascherandolo.

        Scoperto nello stesso test: senza un body esplicito, "breakroleinheritance" fallisce con
        "Cannot handle the data at position 0" (SharePoint prova a interpretare il body assente
        come JSON) invece del vero errore di validazione - risolto passando "{}" come -Content.
        "resetroleinheritance" invece non richiede body.

        Scoperto anche: SharePoint rifiuta SEMPRE questa operazione sulla WEB ROOT di un sito
        ("Cannot change permissions of root web") - e' un vincolo reale della piattaforma, non un
        bug di M365Ops: la web root e' sempre a permessi unici per definizione (non ha un genitore
        da cui ereditare), quindi break/reset non hanno senso li'. L'operazione si applica solo a
        sotto-siti o a liste/raccolte specifiche - non ancora supportati da questo cmdlet, quindi
        l'errore viene tradotto in una spiegazione chiara invece di un messaggio SharePoint criptico.
    #>
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [ValidateSet('Break', 'Reset')] [string]$Action
    )
    Connect-M365OpsSharePoint -SiteUrl $SiteUrl

    $restPath = if ($Action -eq 'Break') { '_api/web/breakroleinheritance(copyRoleAssignments=true,clearSubscopes=false)' } else { '_api/web/resetroleinheritance' }
    $absoluteUrl = "$($SiteUrl.TrimEnd('/'))/$restPath"

    try {
        Invoke-PnPSPRestMethod -Method Post -Url $absoluteUrl -Content "{}" | Out-Null
    }
    catch {
        if ($_.Exception.Message -match 'root web') {
            throw "SharePoint non permette di modificare l'ereditarieta' dei permessi sulla WEB ROOT di un sito (e' sempre a permessi unici per definizione, non ha un genitore da cui ereditare) - questa operazione si applica solo a sotto-siti o a liste/raccolte specifiche all'interno del sito, non ancora supportati da questo cmdlet."
        }
        throw
    }

    $verb = if ($Action -eq 'Break') { 'interrotta (permessi unici, copiati dal padre come punto di partenza)' } else { 'ripristinata (torna a ereditare dal sito padre)' }
    Write-Host "Ereditarieta' permessi $verb su $SiteUrl" -ForegroundColor Green
    [pscustomobject]@{ SiteUrl = $SiteUrl; Action = $Action }
}
