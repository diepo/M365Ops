function Get-M365OpsGitHubRelease {
    <#
    .SYNOPSIS
        Interroga le GitHub Releases pubbliche del repository di M365Ops per trovare
        l'ultima versione disponibile su un canale (Stable o Testing).

        Canale = meccanismo NATIVO di GitHub, non qualcosa di inventato qui: una Release
        normale e' Stable, una Release marcata "Set as a pre-release" (checkbox su GitHub
        al momento della pubblicazione) e' Testing. Nessun commit su main diventa mai un
        aggiornamento disponibile da solo - lo diventa solo quando qualcuno pubblica
        esplicitamente una Release con quel commit, decidendo li' anche se e' Stable o
        Testing. Questo e' il modo in cui "quando un aggiornamento puo' essere reso
        disponibile" viene deciso: un atto deliberato, mai automatico.

        - Stable: GET /releases/latest - GitHub restituisce da solo l'ultima release NON
          pre-release e non-draft, zero logica di filtro necessaria qui.
        - Testing: GET /releases (elenco, piu' recente per prima per default GitHub) - si
          prende la primissima voce, che sia marcata pre-release o no, cosi' chi sceglie
          questo canale vede sempre la build piu' recente disponibile in assoluto.
    .PARAMETER Channel
        'Stable' o 'Testing'.
    #>
    param(
        [ValidateSet('Stable', 'Testing')] [string]$Channel = 'Stable',
        [string]$RepoOwner = 'diepo',
        [string]$RepoName = 'M365Ops'
    )

    $headers = @{ 'User-Agent' = 'M365Ops-UpdateCheck'; 'Accept' = 'application/vnd.github+json' }

    try {
        if ($Channel -eq 'Stable') {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest" -Headers $headers -Method GET
        }
        else {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/releases" -Headers $headers -Method GET
            if (-not $releases -or $releases.Count -eq 0) { return $null }
            $release = $releases[0]
        }
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            # Nessuna Release pubblicata ancora (repo nuovo) - non e' un errore, semplicemente
            # non c'e' nessun aggiornamento da proporre finche' non ne esce una prima.
            return $null
        }
        throw "Impossibile contattare GitHub per verificare gli aggiornamenti: $($_.Exception.Message)"
    }

    if (-not $release) { return $null }

    [pscustomobject]@{
        Tag         = $release.tag_name
        Version     = ($release.tag_name -replace '^v', '')
        Name        = $release.name
        Notes       = $release.body
        IsPrerelease = [bool]$release.prerelease
        PublishedAt = $release.published_at
        HtmlUrl     = $release.html_url
        ZipballUrl  = $release.zipball_url
    }
}
