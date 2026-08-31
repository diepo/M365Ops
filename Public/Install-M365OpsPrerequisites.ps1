function Install-M365OpsPrerequisites {
    <#
    .SYNOPSIS
        Controlla i prerequisiti di sistema (Node.js, Microsoft Edge) e installa
        automaticamente quelli mancanti tramite winget - non si limita a segnalarli come fa
        Get-M365OpsSetupStatus (che da' solo istruzioni manuali). Richiesto esplicitamente
        dall'utente il 17/08/2026: "se non ci sono direttamente procede alla installazione".

        I moduli PowerShell (ExchangeOnlineManagement, ImportExcel, IntuneWin32App) SONO
        gestiti anche qui dal 22/08/2026 (corretto dopo un bug reale segnalato dal vivo su un
        PC davvero vergine: "ti avevo detto di implementare tutti i moduli come prerequisito" -
        installare ExchangeOnlineManagement solo "al primo uso dentro le rispettive cmdlet"
        si e' rivelato inconsistente in pratica, con almeno un percorso di codice
        (Complete-M365OpsExchangeDelegatedLogin.ps1) che non aveva NESSUN fallback di
        auto-installazione, facendo fallire un login delegato altrimenti riuscito con un
        errore criptico di modulo mancante. Installati qui, in anticipo, cosi' un login/report
        reale non e' mai il primo posto dove l'assenza del modulo viene scoperta. Il fallback
        lazy nelle singole cmdlet resta comunque presente per difesa in profondita', non
        rimosso.

        PowerShell 7 stesso NON e' gestito qui: se manca, questa funzione non puo' nemmeno
        girare (serve pwsh per eseguirla). Il controllo/installazione di PowerShell 7 vive in
        M365Ops.bat, PRIMA di invocare pwsh.exe - l'unico punto dove ha senso, essendo un file
        .bat eseguito da cmd.exe (sempre presente) invece che da PowerShell stesso.

        Dal 22/08/2026 M365Ops.bat mostra gia' una GUI dedicata (Show-M365OpsPrereqInstaller.ps1)
        che installa Node.js/Edge/PowerShell 7 PRIMA che il server parta, se manca qualcosa -
        questa funzione resta comunque come seconda passata idempotente qui in Launch-M365Ops.ps1
        (utile se l'app viene lanciata in un modo che salta il .bat, es. direttamente da
        Server.ps1 durante lo sviluppo) e come fallback manuale dal banner Impostazioni.
    .NOTES
        Installazione via winget, in modo silenzioso (nessun prompt) - coerente con la
        richiesta esplicita di procedere direttamente. Se winget non e' disponibile sul PC
        (raro su Windows 10/11 aggiornati, ma possibile su installazioni molto datate o
        Windows Server), la funzione lo segnala chiaramente invece di fallire in modo oscuro.

        Dopo un'installazione riuscita, il PATH di sistema viene ricaricato dal registro nel
        processo CORRENTE (non solo nei nuovi processi, comportamento di default di Windows) -
        altrimenti Get-Command continuerebbe a non trovare il programma appena installato
        finche' l'intero server non viene riavviato manualmente, un passaggio in piu' evitabile.
    #>
    $results = @()

    # TLS 1.2 + provider NuGet forzati QUI, una sola volta, prima di qualunque Install-Module
    # in questa funzione (winget-client piu' sotto E i moduli PowerShell veri e propri) - senza,
    # su un PC davvero vergine Install-Module puo' fallire silenziosamente su TLS piu' vecchio
    # negoziato di default, o restare in attesa di un prompt mai mostrato per il provider NuGet
    # mancante (vedi anche Bootstrap-Winget.ps1, stesso principio).
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
    }

    # Controllo anche il percorso WindowsApps diretto, non solo Get-Command (22/08/2026, bug
    # reale segnalato dal vivo su Windows Sandbox): un winget installato pochi minuti prima da
    # Bootstrap-Winget.ps1 (Windows PowerShell 5.1, dentro M365Ops.bat) puo' risultare "non
    # trovato" qui perche' questa funzione gira in un processo PowerShell 7 SEPARATO
    # (Launch-M365Ops.ps1), che eredita il PATH del proprio processo genitore al momento in
    # cui e' stato creato - non necessariamente aggiornato con l'installazione appena fatta.
    # Senza questo controllo, il sintomo e' un secondo bootstrap ridondante e lento (rieseguito
    # qui sotto) anche quando winget e' gia' realmente presente su disco.
    $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
    if (-not $winget) {
        $windowsAppsWinget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
        if (Test-Path $windowsAppsWinget) { $winget = $windowsAppsWinget }
    }
    if (-not $winget) {
        # Bootstrap automatico di winget stesso (21/08/2026, richiesto esplicitamente
        # dall'utente dopo un test su PC pulito: "si puo' prevedere una installazione del
        # prereq winget?"). winget manca tipicamente su installazioni Windows molto minimali/
        # datate o Windows Server, dove l'App Installer del Microsoft Store non e' mai stato
        # preinstallato - comune proprio sul tipo di "PC pulito" dove questa funzione serve di
        # piu'. Metodo ufficiale Microsoft (non un URL indovinato): il modulo
        # Microsoft.WinGet.Client, cmdlet Repair-WinGetPackageManager - gestisce da solo le
        # dipendenze (VCLibs, Microsoft.UI.Xaml) invece di richiedere URL di pacchetti .appx
        # fissati a mano, che si romperebbero alla prima nuova versione delle dipendenze.
        try {
            Write-M365OpsLog "winget non trovato - tento il bootstrap automatico via Microsoft.WinGet.Client."
            # TLS 1.2 + provider NuGet: gia' forzati in cima alla funzione, condivisi con
            # l'installazione dei moduli PowerShell piu' sotto - non ripetuti qui.
            if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
                Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            }
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            Repair-WinGetPackageManager -ErrorAction Stop
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
        }
        catch {
            $bootstrapError = $_.Exception.Message
        }

        if (-not $winget) {
            return @([pscustomobject]@{
                Name   = 'winget'
                Status = 'Missing'
                Action = "Bootstrap automatico tentato (modulo Microsoft.WinGet.Client, Repair-WinGetPackageManager) - fallito."
                Detail = "winget non e' disponibile su questo PC e il tentativo di installazione automatica e' fallito$(if ($bootstrapError) { ": $bootstrapError" } else { '.' }) Installa i pacchetti `"App Installer`" dal Microsoft Store, oppure installa i prerequisiti manualmente (vedi sezione 3 della guida)."
            })
        }
        $results += [pscustomobject]@{ Name = 'winget'; Status = 'OK'; Action = 'Installato automaticamente (Repair-WinGetPackageManager).'; Detail = $null }
    }

    $checks = @(
        @{
            Name       = 'Node.js (npx, richiesto da Lokka)'
            IsPresent  = { (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue) }
            WingetId   = 'OpenJS.NodeJS.LTS'
        },
        @{
            Name       = 'Microsoft Edge (per export PDF)'
            IsPresent  = { (Get-Command 'msedge.exe' -ErrorAction SilentlyContinue) -or (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") }
            WingetId   = 'Microsoft.Edge'
        }
    )

    $installedSomething = $false
    foreach ($c in $checks) {
        if (& $c.IsPresent) {
            $results += [pscustomobject]@{ Name = $c.Name; Status = 'OK'; Action = 'Gia'' presente, nessuna installazione necessaria.'; Detail = $null }
            continue
        }

        # --source winget aggiunto il 21/08/2026 (bug reale trovato dal vivo su un PC pulito):
        # senza, winget interroga TUTTE le sorgenti configurate (tipicamente winget + msstore) -
        # se il backend msstore risponde con un errore (visto dal vivo: "Failed when searching
        # source: msstore... 0x8a15003b Rest API internal error"), l'intera chiamata falliva
        # ANCHE quando il pacchetto era gia' disponibile e trovabile nella sorgente "winget"
        # (community repository, quella che vogliamo sempre usare per questi prerequisiti - mai
        # lo Store). Specificare la sorgente evita del tutto la query al backend msstore.
        # $winget (percorso risolto, non il nome nudo "winget"): stesso motivo del controllo di
        # presenza sopra - se risolto solo via fallback WindowsApps, un "& winget install..." nudo
        # tornerebbe a dipendere dal PATH e fallirebbe di nuovo nello stesso identico scenario.
        $output = & $winget install --id $c.WingetId -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $installedSomething = $true

        # Aggiorna il PATH del processo corrente dal registro (Machine + User) - winget
        # scrive il nuovo percorso nel registro di sistema, ma un processo gia' avviato (questo
        # server) non lo rilegge mai da solo finche' non viene riavviato: senza questo, la
        # ri-verifica subito sotto fallirebbe sempre anche a installazione riuscita.
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

        $nowPresent = & $c.IsPresent
        $results += [pscustomobject]@{
            Name   = $c.Name
            Status = if ($nowPresent) { 'OK' } else { 'Failed' }
            Action = "Installazione tentata (winget install $($c.WingetId), exit code $exitCode)."
            Detail = if ($nowPresent) { 'Installato e rilevato correttamente.' } else { "Non rilevato dopo il tentativo di installazione - output winget: $($output.Trim())" }
        }
    }

    # CLI Microsoft 365 (26/08/2026, richiesto esplicitamente dall'utente dopo un test su PC
    # nuovo: "rendila disponibile out of the box, installala al primo avvio esattamente come
    # Lokka") - a differenza di Lokka (npx -y scarica ed esegue il pacchetto MCP al volo,
    # nessuna installazione globale necessaria), il server MCP CLI-Microsoft365 e' solo un
    # wrapper sottile che invoca internamente il comando 'm365' come processo ESTERNO gia'
    # installato: va installato GLOBALMENTE (npm install -g @pnp/cli-microsoft365) a parte, non
    # tramite winget come Node.js/Edge sopra ne' tramite Install-Module come i moduli
    # PowerShell sotto. Seconda passata idempotente rispetto a
    # Show-M365OpsPrereqInstaller.ps1 (che gia' lo fa, visibile, PRIMA che il server parta la
    # primissima volta) - utile se quell'installer e' stato saltato (es. sviluppo diretto da
    # Server.ps1). Assert-M365OpsCliMicrosoft365Installed (Private) resta comunque come
    # ultima rete di sicurezza al primo uso reale del connettore, se anche questa passata
    # viene saltata.
    $hasNode = (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue)
    $hasM365 = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'm365' -ErrorAction SilentlyContinue)
    if (-not $hasM365) {
        # Stesso bug/fix gia' presente qualche riga sopra per winget, mai propagato qui - bug
        # REALE trovato dal vivo il 31/08/2026 (non teorico): un cold start ha rieseguito un
        # intero `npm install -g @pnp/cli-microsoft365` (~2 minuti misurati) su
        # un'installazione gia' presente su disco, solo perche' m365.cmd non era nel PATH
        # ereditato da QUESTO specifico processo (Server.ps1, avviato da Launch-M365Ops.ps1) -
        # stessa classe di problema gia' documentata sopra per winget ("un processo separato
        # eredita il PATH del proprio genitore al momento in cui e' stato creato, non
        # necessariamente aggiornato"). Controllo diretto sul percorso standard dei pacchetti
        # globali npm (confermato dal vivo con "npm config get prefix") prima di concludere che
        # manchi per davvero, invece di fidarsi solo di Get-Command.
        $npmGlobalM365 = Join-Path $env:APPDATA 'npm\m365.cmd'
        if (Test-Path $npmGlobalM365) { $hasM365 = $true }
    }
    if ($hasM365) {
        $results += [pscustomobject]@{ Name = 'CLI Microsoft 365 (connettore AI CLI-Microsoft365)'; Status = 'OK'; Action = 'Gia'' presente, nessuna installazione necessaria.'; Detail = $null }
    } elseif (-not $hasNode) {
        $results += [pscustomobject]@{ Name = 'CLI Microsoft 365 (connettore AI CLI-Microsoft365)'; Status = 'Failed'; Action = 'Saltata: richiede Node.js/npm, non disponibile in questo momento.'; Detail = 'Verra'' installata automaticamente al primo utilizzo del connettore (tab Tenant, sezione Stato connessioni), se Node.js diventa disponibile.' }
    } else {
        $npmCmd = (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue).Source
        if (-not $npmCmd) { $npmCmd = (Get-Command 'npm' -ErrorAction SilentlyContinue).Source }
        if (-not $npmCmd) {
            $results += [pscustomobject]@{ Name = 'CLI Microsoft 365 (connettore AI CLI-Microsoft365)'; Status = 'Failed'; Action = 'Saltata: comando npm non risolvibile.'; Detail = 'Verra'' installata automaticamente al primo utilizzo del connettore.' }
        } else {
            $installedSomething = $true
            try {
                Write-M365OpsLog "CLI Microsoft 365 non trovata - la installo (npm install -g @pnp/cli-microsoft365)."
                # Stesso identico bug/fix di Assert-M365OpsCliMicrosoft365Installed.ps1 (v0.9.82,
                # trovato dal vivo il 23/08/2026): '2>&1' su un comando nativo impacchetta ogni
                # riga di STDERR come ErrorRecord - npm scrive avvisi non fatali li' (es. "npm
                # warn allow-scripts..."). Sotto $ErrorActionPreference = 'Stop' (livello modulo),
                # Windows PowerShell 5.1 promuove il primo di quegli avvisi a eccezione terminante
                # ben prima del controllo su $LASTEXITCODE sotto - un'installazione riuscita per
                # davvero verrebbe segnalata Failed con l'avviso npm scambiato per l'errore vero.
                # Il fix del v0.9.82 era stato applicato solo alla chiamata "al primo uso" in
                # Assert-M365OpsCliMicrosoft365Installed.ps1, non a questo gemello (stessa
                # chiamata npm, eseguita qui in anticipo durante l'installazione prerequisiti) -
                # propagato qui per lo stesso motivo. EAP locale, ripristinato in finally; il
                # controllo su $LASTEXITCODE resta l'unica fonte di verita'.
                $previousEap = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    & $npmCmd install -g "@pnp/cli-microsoft365" 2>&1 | ForEach-Object { Write-Host $_ }
                } finally {
                    $ErrorActionPreference = $previousEap
                }
                if ($LASTEXITCODE -ne 0) { throw "npm install terminato con codice $LASTEXITCODE." }
                $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
                $nowPresent = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'm365' -ErrorAction SilentlyContinue)
                $results += [pscustomobject]@{
                    Name   = 'CLI Microsoft 365 (connettore AI CLI-Microsoft365)'
                    Status = if ($nowPresent) { 'OK' } else { 'Failed' }
                    Action = 'Installazione tentata (npm install -g @pnp/cli-microsoft365).'
                    Detail = if ($nowPresent) { 'Installato e rilevato correttamente.' } else { 'Installato ma non ancora visibile a questo processo - servira'' un riavvio completo, non solo "Riavvia server" (Windows non rende visibile un programma npm appena installato a un processo gia'' in esecuzione).' }
                }
            } catch {
                $results += [pscustomobject]@{ Name = 'CLI Microsoft 365 (connettore AI CLI-Microsoft365)'; Status = 'Failed'; Action = 'Installazione tentata (npm install -g) - fallita.'; Detail = $_.Exception.Message }
            }
        }
    }

    # Moduli PowerShell (22/08/2026, richiesto esplicitamente dall'utente dopo un login
    # Exchange delegato riuscito ma poi fallito con un errore criptico di modulo mancante:
    # "installa TUTTO come prerequisito"). Installati qui in anticipo via Install-Module
    # -Scope CurrentUser, invece di affidarsi solo al fallback "al primo uso" dentro le
    # singole cmdlet - quel fallback resta comunque presente per difesa in profondita', ma
    # non deve piu' essere l'UNICO posto dove l'assenza di un modulo viene scoperta, ne'
    # deve dipendere da quale specifico percorso di codice viene toccato per primo (bug
    # reale: Complete-M365OpsExchangeDelegatedLogin.ps1 non aveva nessun fallback per
    # ExchangeOnlineManagement, a differenza di Connect-M365OpsExchange.ps1 - lo stesso
    # modulo, due percorsi diversi, uno solo dei due gestiva l'assenza).
    # Elenco completo (22/08/2026, secondo giro dopo che l'utente ha chiesto esplicitamente
    # "ma i moduli teams sharepoint graph etc ci sono????" - Graph non serve un modulo, questo
    # progetto lo chiama sempre via REST puro (Invoke-M365OpsGraphRequest), ma Teams/SharePoint/
    # PDF si', trovati con lo stesso grep sistematico gia' usato per Exchange/Excel/Intune):
    # ExchangeOnlineManagement E MicrosoftTeams hanno ENTRAMBI una RequiredVersion fissata come
    # COPPIA (25/08/2026: 3.4.0 + 6.5.0, Exchange connesso prima - vedi
    # Assert-M365OpsExoSafeVersion.ps1/Assert-M365OpsTeamsSafeVersion.ps1 per il dettaglio
    # completo di come si e' arrivati a questi due numeri specifici, dopo che un pin sulla sola
    # ExchangeOnlineManagement 3.9.0 si era rivelato insufficiente). Senza pin qui, questa
    # funzione avrebbe installato "l'ultima disponibile" per entrambi, vanificando il pin gia'
    # messo nelle cmdlet di connessione: PowerShell tiene versioni diverse dello stesso modulo in
    # cartelle separate, ma Import-Module senza -RequiredVersion sceglie sempre la piu' recente
    # installata - avere SOLO l'ultima su disco avrebbe reso quel pin inutile.
    # Gestiti a parte, PRIMA del ciclo generico sotto - Assert-M365Ops*SafeVersion non si limita
    # a controllare/installare come il ciclo generico, verifica anche l'INTEGRITA' dei file (non
    # solo la presenza del manifest, bug reale trovato il 25/08/2026) e, solo per Exchange,
    # disinstalla ATTIVAMENTE anche una eventuale versione >= 3.10.0 gia' presente sul disco
    # (nota per andare SEMPRE in conflitto con MicrosoftTeams, indipendentemente dalla sua
    # versione - vedi guida sezione 6.6).
    # -InstallOnly: questa funzione gira ad OGNI avvio del server, prima che l'utente scelga se
    # gli serve Teams o Exchange - importare i moduli qui (comportamento di default di entrambe
    # le funzioni, usato invece dalle cmdlet di connessione vere) caricherebbe entrambi nel
    # processo del server anche per chi ne vuole usare SOLO uno in quella sessione, vedi
    # Assert-M365OpsExoSafeVersion.ps1 per il dettaglio completo.
    # $exoResult.Version/$teamsResult.Version (26/08/2026): Assert-M365Ops*SafeVersion non
    # punta piu' a una versione fissata (vedi quei file per il perche' - isolamento reattivo
    # dei processi invece di una coppia di versioni "verificata sicura") - la versione
    # effettivamente in uso e' quindi dinamica, mai piu' una stringa costante '3.4.0'/'6.5.0'
    # da controllare qui.
    $exoResult = Assert-M365OpsExoSafeVersion -InstallOnly
    if ($exoResult.RemovedVersions.Count -gt 0) { $installedSomething = $true }
    if ($exoResult.Installed) { $installedSomething = $true }
    $exoNowPresent = [bool]$exoResult.Version
    $exoDetailParts = @()
    if ($exoResult.RemovedVersions.Count -gt 0) { $exoDetailParts += "Versione/i precedente/i rimossa/e: $($exoResult.RemovedVersions -join ', ')." }
    $exoDetailParts += if ($exoNowPresent) { "Versione $($exoResult.Version) presente (ultima disponibile)." } else { 'Nessuna versione rilevata dopo il tentativo di installazione - riprova o installa manualmente.' }
    $results += [pscustomobject]@{
        Name   = 'Modulo ExchangeOnlineManagement (connessione Exchange Online)'
        Status = if ($exoNowPresent) { 'OK' } else { 'Failed' }
        Action = if ($exoResult.RemovedVersions.Count -gt 0 -or $exoResult.Installed) { 'Installazione/pulizia tentata (Assert-M365OpsExoSafeVersion).' } else { 'Gia'' presente, nessuna azione necessaria.' }
        Detail = $exoDetailParts -join ' '
    }

    $teamsResult = Assert-M365OpsTeamsSafeVersion -InstallOnly
    if ($teamsResult.Installed) { $installedSomething = $true }
    $teamsNowPresent = [bool]$teamsResult.Version
    $results += [pscustomobject]@{
        Name   = 'Modulo MicrosoftTeams (connessione Teams)'
        Status = if ($teamsNowPresent) { 'OK' } else { 'Failed' }
        Action = if ($teamsResult.Installed) { 'Installazione/pulizia tentata (Assert-M365OpsTeamsSafeVersion).' } else { 'Gia'' presente, nessuna azione necessaria.' }
        Detail = if ($teamsNowPresent) { "Versione $($teamsResult.Version) presente (ultima disponibile)." } else { 'Nessuna versione rilevata dopo il tentativo di installazione - riprova o installa manualmente.' }
    }

    $moduleChecks = @(
        @{ Name = 'ImportExcel'; FriendlyName = 'Modulo ImportExcel (export report .xlsx)' }
        @{ Name = 'IntuneWin32App'; FriendlyName = 'Modulo IntuneWin32App (packaging app Win32 per Intune)' }
        @{ Name = 'PnP.PowerShell'; FriendlyName = 'Modulo PnP.PowerShell (connessione SharePoint)' }
        @{ Name = 'PdfLexer'; FriendlyName = 'Modulo PdfLexer (estrazione testo da PDF caricati nella Knowledge Base)' }
    )
    foreach ($m in $moduleChecks) {
        $installed = Get-Module -ListAvailable -Name $m.Name
        $present = if ($m.RequiredVersion) { [bool]($installed | Where-Object Version -eq $m.RequiredVersion) } else { [bool]$installed }
        if ($present) {
            $results += [pscustomobject]@{ Name = $m.FriendlyName; Status = 'OK'; Action = 'Gia'' presente, nessuna installazione necessaria.'; Detail = $null }
            continue
        }
        $installedSomething = $true
        try {
            $versionLabel = if ($m.RequiredVersion) { " $($m.RequiredVersion)" } else { '' }
            Write-M365OpsLog "$($m.Name)$versionLabel non trovato - lo installo (Install-Module -Scope CurrentUser)."
            $installParams = @{ Name = $m.Name; Scope = 'CurrentUser'; Force = $true; AllowClobber = $true; SkipPublisherCheck = $true; ErrorAction = 'Stop' }
            if ($m.RequiredVersion) { $installParams.RequiredVersion = $m.RequiredVersion }
            Install-Module @installParams
            $nowPresent = if ($m.RequiredVersion) { [bool](Get-Module -ListAvailable -Name $m.Name | Where-Object Version -eq $m.RequiredVersion) } else { [bool](Get-Module -ListAvailable -Name $m.Name) }
            $results += [pscustomobject]@{
                Name   = $m.FriendlyName
                Status = if ($nowPresent) { 'OK' } else { 'Failed' }
                Action = 'Installazione tentata (Install-Module).'
                Detail = if ($nowPresent) { 'Installato e rilevato correttamente.' } else { 'Install-Module completato senza errori ma il modulo non risulta rilevabile - riprova o installa manualmente.' }
            }
        } catch {
            $results += [pscustomobject]@{
                Name   = $m.FriendlyName
                Status = 'Failed'
                Action = 'Installazione tentata (Install-Module) - fallita.'
                Detail = $_.Exception.Message
            }
        }
    }

    if ($installedSomething) {
        Write-M365OpsLog "Install-M365OpsPrerequisites: $(($results | Where-Object { $_.Status -ne 'OK' -or $_.Action -like 'Installazione*' } | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ', ')"
    }

    $results
}
