function Install-M365OpsUpdate {
    <#
    .SYNOPSIS
        Scarica ed applica l'ultima Release GitHub disponibile sul canale scelto
        (Get-M365OpsUpdateChannel), sovrascrivendo i file dell'installazione corrente.
        SOLO uso GUI (pulsante "Aggiorna" nel tab Manutenzione) - mai esposta all'AI: e'
        un'azione che modifica l'app stessa e richiede un riavvio, non qualcosa che una
        richiesta in chat deve poter innescare.

        Sicurezza strutturale, non convenzionale: l'archivio scaricato da GitHub e'
        ESATTAMENTE l'albero tracciato da git a quel tag - Config\, Logs\, Uploads\,
        Reports\, Testing\ non ci sono mai dentro (escluse da .gitignore, mai committate),
        quindi questa funzione non puo' fisicamente toccarle anche solo volendo: non le
        esclude "a mano", semplicemente non esistono nel materiale che sovrascrive. La
        stessa garanzia richiesta a suo tempo per la Knowledge Base (isolamento per
        struttura, non per promessa) vale qui per i dati operativi del tenant.

        Limite noto (accettabile per una v0.x): un file rimosso in una versione piu'
        recente non viene ripulito qui, solo aggiunte/modifiche vengono applicate - una
        reinstallazione pulita (cancellare la cartella e riclonare) resta il percorso
        garantito al 100% se serve ripulire anche le rimozioni.
    .NOTES
        Mode: Write
    #>
    param(
        [string]$Channel = (Get-M365OpsUpdateChannel)
    )

    $release = Get-M365OpsGitHubRelease -Channel $Channel
    if (-not $release) { throw "Nessuna Release trovata sul canale '$Channel'." }

    $manifestPath = Join-Path $script:M365OpsModuleRoot 'M365Ops.psd1'
    $currentVersion = (Import-PowerShellDataFile -Path $manifestPath).ModuleVersion
    try {
        if ([version]$release.Version -le [version]$currentVersion) {
            return [pscustomobject]@{ Applied = $false; Reason = "Gia' alla versione piu' recente ($currentVersion) sul canale '$Channel'."; Version = $currentVersion }
        }
    } catch {}

    $stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $tempZip = Join-Path $env:TEMP "m365ops-update-$stamp.zip"
    $tempExtractDir = Join-Path $env:TEMP "m365ops-update-$stamp"

    try {
        Invoke-WebRequest -Uri $release.ZipballUrl -OutFile $tempZip -UseBasicParsing
        Expand-Archive -Path $tempZip -DestinationPath $tempExtractDir -Force

        # Lo zipball GitHub contiene sempre UNA sola cartella di primo livello
        # (es. "diepo-M365Ops-a1b2c3d") - il vero contenuto e' dentro quella.
        $sourceRoot = Get-ChildItem -Path $tempExtractDir -Directory | Select-Object -First 1
        if (-not $sourceRoot) { throw "Archivio scaricato vuoto o malformato." }

        # Lista difensiva: anche se questi nomi non possono strutturalmente comparire
        # nell'archivio (vedi .SYNOPSIS), un controllo esplicito qui costa nulla e blocca
        # a monte qualunque scenario imprevisto (es. un futuro contributor che le committa
        # per errore in un fork), invece di fidarsi solo dell'assenza per costruzione.
        $neverTouch = @('Config', 'Logs', 'Uploads', 'Reports', 'Testing', '.git')

        $copiedItems = @()
        Get-ChildItem -Path $sourceRoot.FullName -Force | ForEach-Object {
            if ($_.Name -in $neverTouch) { return }
            $dest = Join-Path $script:M365OpsModuleRoot $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
            $copiedItems += $_.Name
        }

        Write-M365OpsLog "Install-M365OpsUpdate: aggiornato da $currentVersion a $($release.Version) (canale $Channel, tag $($release.Tag))."

        [pscustomobject]@{
            Applied        = $true
            FromVersion    = $currentVersion
            ToVersion      = $release.Version
            Tag            = $release.Tag
            Channel        = $Channel
            ItemsUpdated   = $copiedItems
        }
    }
    finally {
        Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
