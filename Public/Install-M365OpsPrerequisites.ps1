function Install-M365OpsPrerequisites {
    <#
    .SYNOPSIS
        Controlla i prerequisiti di sistema (Node.js, Microsoft Edge) e installa
        automaticamente quelli mancanti tramite winget - non si limita a segnalarli come fa
        Get-M365OpsSetupStatus (che da' solo istruzioni manuali). Richiesto esplicitamente
        dall'utente il 17/08/2026: "se non ci sono direttamente procede alla installazione".

        I moduli PowerShell (ImportExcel, ExchangeOnlineManagement, IntuneWin32App) NON sono
        gestiti qui: si auto-installano gia' da soli al primo uso con Install-Module
        -Scope CurrentUser dentro le rispettive cmdlet - non serve ripetere quella logica qui.

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

    $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
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
            # TLS 1.2 + provider NuGet espliciti (22/08/2026, allineato a Bootstrap-Winget.ps1
            # dopo che lo stesso identico blocco "ps7 assente e winget non disponibile" e'
            # ricomparso dal vivo su un secondo PC pulito con la v0.9.26 gia' installata - vedi
            # quel file per il dettaglio del perche' questo blocco qui non bastava da solo).
            # Senza, Install-Module puo' fallire silenziosamente su TLS piu' vecchio negoziato
            # di default, o restare in attesa di un prompt mai mostrato per il provider NuGet
            # mancante (nessuno dei due sintomi ovvio dal solo messaggio d'errore).
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
            }
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
        $output = & winget install --id $c.WingetId -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
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

    if ($installedSomething) {
        Write-M365OpsLog "Install-M365OpsPrerequisites: $(($results | Where-Object { $_.Status -ne 'OK' -or $_.Action -like 'Installazione*' } | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ', ')"
    }

    $results
}
