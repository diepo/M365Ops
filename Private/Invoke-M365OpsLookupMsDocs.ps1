<#
    Consultazione LIVE della documentazione Microsoft Learn - principio permanente di
    questo progetto: l'AI (sia nel loop interattivo che nella diagnosi/correzione errori)
    non deve mai affidarsi alla propria conoscenza mnemonica, spesso incompleta o non
    aggiornata, dei parametri di una cmdlet Exchange o di un endpoint Graph. Deve invece
    consultare la pagina reale ogni volta che propone un parametro poco comune o che le
    viene chiesto "quali altre opzioni ci sono". Vedi Invoke-M365OpsAgentTools (tool
    'lookup_ms_docs') e Invoke-M365OpsErrorTriage (usata automaticamente per ogni fix
    proposto su uno script che chiama cmdlet Exchange/Graph).
#>

function Format-M365OpsDocsPage {
    param(
        [Parameter(Mandatory)] [string]$Html,
        [Parameter(Mandatory)] [string]$Url,
        [string]$Title
    )
    $text = $Html -replace '<script[\s\S]*?</script>', ' ' -replace '<style[\s\S]*?</style>', ' ' `
        -replace '<[^>]+>', ' ' -replace '&gt;', '>' -replace '&lt;', '<' -replace '&quot;', '"' `
        -replace '&#39;', "'" -replace '&amp;', '&' -replace '[ \t]+', ' ' -replace '(\r?\n\s*){2,}', "`n"

    # Le pagine di riferimento cmdlet hanno sempre una sezione "Syntax" con l'elenco
    # completo firmato dei parametri (tipo incluso) - la piu' densa di informazioni utili.
    $syntaxIdx = $text.IndexOf('Syntax')
    $body = if ($syntaxIdx -ge 0) {
        $text.Substring($syntaxIdx, [Math]::Min(4000, $text.Length - $syntaxIdx))
    } else {
        $descIdx = $text.IndexOf('In this article')
        $start = if ($descIdx -ge 0) { $descIdx } else { 0 }
        $text.Substring($start, [Math]::Min(3000, $text.Length - $start))
    }

    "FONTE: $Url`n$(if ($Title) { "TITOLO: $Title`n" })$body"
}

function Invoke-M365OpsLookupMsDocs {
    <#
    .SYNOPSIS
        Consulta la documentazione REALE e AGGIORNATA di una cmdlet Exchange Online
        PowerShell o di un argomento Microsoft Graph, direttamente da Microsoft Learn -
        mai dalla conoscenza pregressa del modello. Prova prima l'URL diretto della
        pagina di riferimento cmdlet (la piu' ricca, include la sintassi completa con
        ogni parametro e il suo tipo), poi in fallback la ricerca Microsoft Learn per
        argomenti senza una pagina cmdlet diretta (es. concetti Graph, best practice).
    #>
    param(
        [Parameter(Mandatory)] [string]$Topic
    )

    $slug = ($Topic.Trim() -replace '\s+', '-').ToLower()
    $directUrls = @(
        "https://learn.microsoft.com/en-us/powershell/module/exchange/$slug",
        "https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/$slug"
    )
    foreach ($url in $directUrls) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" } -TimeoutSec 15 -ErrorAction Stop
            return Format-M365OpsDocsPage -Html $resp.Content -Url $url
        }
        catch { }
    }

    try {
        $searchUrl = "https://learn.microsoft.com/api/search?search=$([uri]::EscapeDataString($Topic))&locale=en-us&`$top=3"
        $results = Invoke-RestMethod -Uri $searchUrl -Headers @{ "User-Agent" = "Mozilla/5.0" } -TimeoutSec 15 -ErrorAction Stop
        if (-not $results.results -or $results.results.Count -eq 0) {
            return "Nessun risultato su Microsoft Learn per '$Topic'."
        }
        $top = $results.results[0]
        $resp = Invoke-WebRequest -Uri $top.url -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" } -TimeoutSec 15 -ErrorAction Stop
        return Format-M365OpsDocsPage -Html $resp.Content -Url $top.url -Title $top.title
    }
    catch {
        return "Impossibile consultare Microsoft Learn per '$Topic' in questo momento: $($_.Exception.Message)"
    }
}
