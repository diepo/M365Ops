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
        Reports\, Testing\, Scripts\Custom\ non ci sono mai dentro con contenuto reale
        dell'utente (escluse da .gitignore o protette esplicitamente sotto), quindi questa
        funzione non puo' fisicamente toccarle anche solo volendo: non le esclude "a mano",
        semplicemente non esistono nel materiale che sovrascrive. La stessa garanzia
        richiesta a suo tempo per la Knowledge Base (isolamento per struttura, non per
        promessa) vale qui per i dati operativi del tenant.

        BUG STRUTTURALE GRAVE corretto il 22/08/2026, trovato dal vivo dall'utente dopo
        una serie di aggiornamenti apparentemente riusciti (0.9.33 -> ... -> 0.9.37, ognuno
        loggato come "aggiornato" senza errori) che pero' non avevano MAI applicato le
        modifiche reali al codice - confermato incollando il contenuto di
        Connect-M365OpsTeams.ps1 dalla sua macchina: era ancora la versione di settimane
        prima, nonostante il numero di versione in M365Ops.psd1 fosse salito correttamente
        ad ogni giro. Causa: "Copy-Item -Path sorgente\Public -Destination dest\Public
        -Recurse -Force" quando "dest\Public" ESISTE GIA' (sempre vero per un
        aggiornamento, mai per un'installazione nuova) non sovrascrive il CONTENUTO della
        cartella - copia l'intera cartella sorgente DENTRO quella di destinazione, creando
        "dest\Public\Public\..." invece di sovrascrivere "dest\Public\...". Nessun errore,
        nessun avviso: Copy-Item considera l'operazione riuscita, M365Ops.psd1 (un FILE, non
        una cartella - non soggetto a questo problema) si aggiornava correttamente ad ogni
        giro dando la falsa impressione che tutto funzionasse, mentre il codice VERO sotto
        Public\/Private\/Gui\/Tools\ restava quello del tutto primo download, mai toccato
        da nessun aggiornamento successivo. Riprodotto empiricamente prima di correggere:
        un file "nuovo" creato con lo stesso identico pattern finisce in
        "dest\Public\Public\NuovoFile.ps1", il file "vecchio" gia' presente in
        "dest\Public\VecchioFile.ps1" resta totalmente intatto. Corretto con una copia
        RICORSIVA file-per-file (mai una cartella intera passata a -Recurse verso una
        destinazione che potrebbe gia' esistere) - crea le cartelle di destinazione se
        mancanti, poi copia ogni singolo file con Copy-Item -Force, senza mai rischiare
        l'annidamento indipendentemente dalla profondita' della struttura.

        Limite noto (accettabile per una v0.x): un file rimosso in una versione piu'
        recente non viene ripulito qui, solo aggiunte/modifiche vengono applicate - una
        reinstallazione pulita (cancellare la cartella e riclonare) resta il percorso
        garantito al 100% se serve ripulire anche le rimozioni <strong>o se un'installazione
        precedente ha gia' accumulato cartelle annidate dal bug sopra</strong> - in
        quel caso una copia pulita e' l'unico modo sicuro di ripartire, questa funzione da
        sola non ripulisce l'annidamento gia' presente su disco da aggiornamenti passati.
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
        # Scripts\Custom aggiunta il 22/08/2026 (stesso giro del fix sotto): script
        # personalizzati creati dall'utente stesso, mai da sovrascrivere con quelli
        # dell'archivio (che contiene solo _TEMPLATE.ps1/README.md).
        $neverTouch = @('Config', 'Logs', 'Uploads', 'Reports', 'Testing', '.git', 'Scripts')

        # BUG STRUTTURALE (22/08/2026, vedi .SYNOPSIS per il dettaglio completo): mai passare
        # una CARTELLA a Copy-Item -Recurse verso una destinazione che potrebbe gia' esistere
        # (sempre vero per un aggiornamento) - annida invece di sovrascrivere, senza nessun
        # errore. Copia ricorsiva file-per-file: l'unico modo di garantire che ogni file
        # venga davvero sovrascritto al posto giusto, indipendentemente dalla profondita'
        # della struttura di cartelle.
        function Copy-M365OpsUpdateItem {
            param([string]$SourcePath, [string]$DestPath)
            if (Test-Path -Path $SourcePath -PathType Container) {
                if (-not (Test-Path $DestPath)) { New-Item -ItemType Directory -Force -Path $DestPath | Out-Null }
                Get-ChildItem -Path $SourcePath -Force | ForEach-Object {
                    Copy-M365OpsUpdateItem -SourcePath $_.FullName -DestPath (Join-Path $DestPath $_.Name)
                }
            } else {
                Copy-Item -Path $SourcePath -Destination $DestPath -Force
            }
        }

        $copiedItems = @()
        Get-ChildItem -Path $sourceRoot.FullName -Force | ForEach-Object {
            if ($_.Name -in $neverTouch) { return }
            $dest = Join-Path $script:M365OpsModuleRoot $_.Name
            Copy-M365OpsUpdateItem -SourcePath $_.FullName -DestPath $dest
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
