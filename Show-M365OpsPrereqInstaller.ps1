<#
    Finestra grafica che mostra dal vivo l'installazione dei prerequisiti mancanti
    (PowerShell 7, winget se assente, Node.js, Microsoft Edge) - richiamata da M365Ops.bat
    SOLO quando almeno uno di questi manca (il percorso comune, con tutto gia' presente,
    resta silenzioso e istantaneo come prima). Windows PowerShell 5.1 compatibile
    (nessuna dipendenza dal modulo M365Ops, che richiederebbe PowerShell 7 gia' presente).

    Richiesto esplicitamente dall'utente il 22/08/2026: "una gui che segua l'installazione
    dei moduli. aggrega dentro l'installazione dei prereq anche nodejs visto che cmq serve" -
    prima Node.js veniva installato solo DOPO, in un secondo momento invisibile
    (Install-M365OpsPrerequisites.ps1, dentro il modulo, via Launch-M365Ops.ps1). Qui i
    passaggi sono unificati in un solo flusso visibile, cosi' un utente su un PC pulito vede
    UNA sola schermata "sto installando tutto cio' che serve" invece di un .bat silenzioso
    seguito da un secondo controllo invisibile minuti dopo.

    Il bootstrap di winget stesso (se assente) riusa Bootstrap-Winget.ps1 as-is, lanciato
    come processo figlio separato (mai dot-sorgente: quello script termina con "exit", che
    ucciderebbe anche questo processo GUI se venisse eseguito nello stesso scope).

    Uscita: exit code 0 se PowerShell 7 risulta disponibile alla fine (gia' presente o
    installato ora), 1 altrimenti - M365Ops.bat legge %errorlevel% per decidere se proseguire.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Bug reale segnalato dal vivo il 22/08/2026 ("manca la progress bar in alto"): senza
# EnableVisualStyles(), WinForms disegna i controlli con il rendering classico non temato -
# in quella modalita' una ProgressBar in stile Marquee puo' non disegnarsi affatto (spazio
# vuoto, nessun errore) invece di limitarsi a un aspetto meno moderno, un problema noto di
# WinForms specifico dello stile Marquee. Va chiamato PRIMA di creare qualunque controllo.
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = $PSScriptRoot
$iconPath = Join-Path $root 'Assets\M365Ops.ico'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'M365Ops - Verifica prerequisiti'
$form.Size = New-Object System.Drawing.Size(520, 400)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Verifica dei prerequisiti in corso...'
$statusLabel.Location = New-Object System.Drawing.Point(15, 15)
$statusLabel.Size = New-Object System.Drawing.Size(480, 20)
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($statusLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 40)
$progressBar.Size = New-Object System.Drawing.Size(480, 18)
# Continuous con avanzamento manuale a passi, non Marquee: piu' affidabile su sessioni remote/
# RDP (Windows Sandbox inclusa) dove l'animazione Marquee puo' non ridisegnarsi in tempo, e
# mostra un progresso reale (X di 4 sezioni) invece del solo "sta succedendo qualcosa".
$progressBar.Style = 'Continuous'
$progressBar.Minimum = 0
$progressBar.Maximum = 4
$progressBar.Value = 0
$form.Controls.Add($progressBar)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 68)
$logBox.Size = New-Object System.Drawing.Size(480, 260)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::White
$logBox.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$form.Controls.Add($logBox)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Chiudi'
$closeButton.Location = New-Object System.Drawing.Point(415, 335)
$closeButton.Size = New-Object System.Drawing.Size(80, 25)
$closeButton.Enabled = $false
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

$exitCode = 1

function Write-InstallerLog {
    param([string]$Message)
    $logBox.AppendText("$Message`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Wait-ProcessWithLiveOutput {
    <#
        Bug reale segnalato dal vivo il 22/08/2026 durante il primo test su un PC pulito
        (screenshot dell'utente: finestra ferma su "tento il bootstrap automatico..." per
        oltre un minuto senza nessuna nuova riga, "sembra stuck... le persone si rompono").
        Causa: Wait-ProcessResponsive (rimossa) aspettava la fine dell'intero processo
        figlio PRIMA di leggere il suo output (StandardOutput.ReadToEnd() e' bloccante fino
        all'uscita) - durante Install-Module/Repair-WinGetPackageManager, che puo' durare
        1-2 minuti su un PC vergine, la finestra non aveva NESSUN modo di mostrare
        progresso nel frattempo. Corretto: il processo figlio scrive il suo output su un
        file temporaneo (RedirectStandardOutput), e questa funzione lo "tail-a" ad ogni
        giro del polling gia' esistente, mostrando le righe non appena compaiono - piu' un
        contatore di secondi nella status label, cosi' anche nei tratti senza nuove righe
        di log la finestra mostra comunque segni di vita continui, non solo alla fine.
    #>
    param(
        [System.Diagnostics.Process]$Process,
        [string]$OutputFile,
        [string]$BaseStatusText
    )
    $lastLength = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.HasExited) {
        if ($OutputFile -and (Test-Path $OutputFile)) {
            try {
                $content = Get-Content -Path $OutputFile -Raw -ErrorAction SilentlyContinue
                if ($content -and $content.Length -gt $lastLength) {
                    $newText = $content.Substring($lastLength)
                    $lastLength = $content.Length
                    foreach ($line in ($newText -split "`r?`n")) { if ($line.Trim()) { Write-InstallerLog "  $line" } }
                }
            } catch {}
        }
        if ($BaseStatusText) { $statusLabel.Text = "$BaseStatusText ($([int]$sw.Elapsed.TotalSeconds)s)" }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
    if ($OutputFile -and (Test-Path $OutputFile)) {
        try {
            $content = Get-Content -Path $OutputFile -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Length -gt $lastLength) {
                foreach ($line in ($content.Substring($lastLength) -split "`r?`n")) { if ($line.Trim()) { Write-InstallerLog "  $line" } }
            }
        } catch {}
    }
    if ($BaseStatusText) { $statusLabel.Text = $BaseStatusText }
}

function Test-M365OpsPwshPresent {
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { return $true }
    return (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe")
}

function Test-M365OpsWingetPresent {
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) { return $true }
    return (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")
}

function Get-M365OpsPwshPath {
    $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Invoke-M365OpsModuleInstall {
    <#
        Installa TUTTI i moduli PowerShell mancanti in un SOLO processo pwsh.exe (PowerShell
        7) figlio - non uno per modulo. Bug reale segnalato dal vivo il 22/08/2026: la prima
        versione lanciava un processo pwsh.exe SEPARATO per ciascuno dei 6 moduli, ciascuno dei
        quali ripeteva da zero il bootstrap di TLS1.2/provider NuGet - su un PC dove NuGet non
        era ancora installato, i sei tentativi finivano per correre a ridosso l'uno dell'altro
        e collidere sullo stesso file delle librerie PackageManagement/PowerShellGet ("The
        version 'X' of module 'PackageManagement' is currently in use. Retry the operation
        after closing the applications.") - TUTTI E SEI i tentativi fallivano con lo stesso
        errore. Un solo processo, che fa il bootstrap UNA volta sola e poi installa tutti i
        moduli in sequenza nello stesso spazio, elimina la possibilita' stessa della collisione
        (mai due processi che toccano quei file insieme) - piu' veloce e piu' robusto.

        Nello scope di PowerShell 7, non di QUESTO script (Windows PowerShell 5.1): un modulo
        installato con -Scope CurrentUser sotto Windows PowerShell 5.1 finisce in
        Documents\WindowsPowerShell\Modules, un percorso DIVERSO da quello che PowerShell 7
        (dove gira davvero l'app) cerca (Documents\PowerShell\Modules) - installarlo qui
        direttamente lo lascerebbe comunque invisibile all'app vera.
    #>
    param([string]$PwshPath, [array]$Modules)
    if (-not $Modules -or $Modules.Count -eq 0) { return @{} }

    # "Nome=Versione" per modulo, versione vuota se nessun pin - nessun chiamante di questa
    # funzione passa piu' una versione fissata dal 26/08/2026 (isolamento reattivo dei
    # processi al posto del vecchio pin a coppia 3.4.0/6.5.0, vedi il commento sopra
    # $moduleChecks piu' sotto in questo file), il supporto a RequiredVersion resta qui solo
    # come meccanismo generico per un eventuale pin futuro su un modulo diverso.
    $specsJoined = ($Modules | ForEach-Object { "$($_.Name)=$($_.RequiredVersion)" }) -join ';'
    $psCommand = @"
`$ErrorActionPreference = 'Continue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch { Write-Host "NUGET-PROVIDER-FAILED: `$(`$_.Exception.Message)" }
}
foreach (`$spec in ('$specsJoined' -split ';')) {
    `$parts = `$spec -split '=', 2
    `$name = `$parts[0]
    `$ver = if (`$parts.Count -gt 1 -and `$parts[1]) { `$parts[1] } else { `$null }
    try {
        # Nessuna disinstallazione mirata di versioni "in conflitto" qui (26/08/2026, rimossa
        # insieme al pin fisso 3.4.0/6.5.0 - vedi commento sopra `$moduleChecks): la pulizia di
        # versioni vecchie/multiple e' ora responsabilita' di Assert-M365OpsExoSafeVersion/
        # Assert-M365OpsTeamsSafeVersion, chiamate dal vero modulo M365Ops al primo uso reale
        # (che qui non e' ancora importato) - questo script installa solo "qualcosa", se manca.
        `$installParams = @{ Name = `$name; Scope = 'CurrentUser'; Force = `$true; AllowClobber = `$true; SkipPublisherCheck = `$true; ErrorAction = 'Stop' }
        if (`$ver) { `$installParams.RequiredVersion = `$ver }
        Install-Module @installParams
        Write-Host "MODULE-RESULT: `$name=OK"
    } catch {
        Write-Host "MODULE-RESULT: `$name=FAILED: `$(`$_.Exception.Message)"
    }
}
"@
    $tmpScript = [System.IO.Path]::GetTempFileName() + '.ps1'
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $results = @{}
    try {
        Set-Content -Path $tmpScript -Value $psCommand -Encoding UTF8
        $proc = Start-Process -FilePath $PwshPath -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tmpScript`"") -PassThru -WindowStyle Hidden -RedirectStandardOutput $tmpOut
        Wait-ProcessWithLiveOutput -Process $proc -OutputFile $tmpOut -BaseStatusText 'Installazione moduli PowerShell...'
        $finalOutput = Get-Content -Path $tmpOut -Raw -ErrorAction SilentlyContinue
        foreach ($line in ($finalOutput -split "`r?`n")) {
            if ($line -match '^MODULE-RESULT: (\S+?)=OK\s*$') { $results[$Matches[1]] = $true }
            elseif ($line -match '^MODULE-RESULT: (\S+?)=FAILED') { $results[$Matches[1]] = $false }
        }
    } finally {
        Remove-Item $tmpScript, $tmpOut -Force -ErrorAction SilentlyContinue
    }

    foreach ($m in $Modules) {
        if ($results.ContainsKey($m.Name) -and $results[$m.Name]) {
            Write-InstallerLog "  $($m.FriendlyName): installato."
        } else {
            Write-InstallerLog "  $($m.FriendlyName): installazione fallita - M365Ops ritentera' comunque al primo uso."
        }
    }
    return $results
}

function Get-M365OpsWingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Invoke-M365OpsWingetInstall {
    param([string]$WingetPath, [string]$PackageId, [string]$FriendlyName)
    Write-InstallerLog "  winget install $PackageId in corso..."
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $args = @('install', '--id', $PackageId, '-e', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    try {
        $proc = Start-Process -FilePath $WingetPath -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $tmpOut
        Wait-ProcessWithLiveOutput -Process $proc -OutputFile $tmpOut -BaseStatusText $statusLabel.Text
        $exitCode = $proc.ExitCode
    } finally {
        Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($exitCode -eq 0) {
        Write-InstallerLog "  $FriendlyName installato."
    } else {
        Write-InstallerLog "  ${FriendlyName}: winget ha restituito il codice $exitCode - potrebbe essere gia' installato o richiedere un intervento manuale."
    }
    return $exitCode
}

$form.Add_Shown({
    Write-InstallerLog "=== PowerShell 7 ==="
    if (Test-M365OpsPwshPresent) {
        Write-InstallerLog "  Gia' presente."
    } else {
        Write-InstallerLog "  Non trovato."
        if (-not (Test-M365OpsWingetPresent)) {
            $statusLabel.Text = 'Bootstrap di winget (necessario per installare PowerShell 7)...'
            Write-InstallerLog "=== winget ==="
            Write-InstallerLog "  Non disponibile - tento il bootstrap automatico (Microsoft.WinGet.Client)..."
            Write-InstallerLog "  (puo' richiedere 1-2 minuti su un PC nuovo - provider NuGet, poi il modulo, poi il repair vero e proprio)"
            $bootstrapScript = Join-Path $root 'Bootstrap-Winget.ps1'
            $tmpBootstrapOut = [System.IO.Path]::GetTempFileName()
            try {
                $bootstrapProc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$bootstrapScript`"") -PassThru -WindowStyle Hidden -RedirectStandardOutput $tmpBootstrapOut
                Wait-ProcessWithLiveOutput -Process $bootstrapProc -OutputFile $tmpBootstrapOut -BaseStatusText 'Bootstrap di winget (necessario per installare PowerShell 7)...'
            } finally {
                Remove-Item $tmpBootstrapOut -Force -ErrorAction SilentlyContinue
            }
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        }

        if (Test-M365OpsWingetPresent) {
            $statusLabel.Text = 'Installazione di PowerShell 7...'
            $wingetPath = Get-M365OpsWingetPath
            Invoke-M365OpsWingetInstall -WingetPath $wingetPath -PackageId 'Microsoft.PowerShell' -FriendlyName 'PowerShell 7' | Out-Null
        } else {
            Write-InstallerLog "  winget non disponibile: impossibile installare PowerShell 7 automaticamente."
        }
    }
    $progressBar.Value = 1

    if (Test-M365OpsWingetPresent) {
        $wingetPath = Get-M365OpsWingetPath

        Write-InstallerLog "=== Node.js (richiesto da Lokka e CLI Microsoft 365) ==="
        $hasNode = (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue)
        if ($hasNode) {
            Write-InstallerLog "  Gia' presente."
        } else {
            $statusLabel.Text = 'Installazione di Node.js...'
            Invoke-M365OpsWingetInstall -WingetPath $wingetPath -PackageId 'OpenJS.NodeJS.LTS' -FriendlyName 'Node.js' | Out-Null
        }

        # CLI Microsoft 365 (26/08/2026, richiesto esplicitamente dall'utente dopo un test su
        # PC nuovo: "la CLI 365 MCP non arriva preconfigurata... rendila disponibile out of the
        # box, installala al primo avvio col .bat esattamente come Lokka"). A differenza di
        # Lokka (npx -y scarica ed esegue il pacchetto al volo, nessuna installazione globale
        # necessaria), il server MCP CLI-Microsoft365 e' solo un wrapper sottile che invoca
        # internamente il comando 'm365' come processo ESTERNO gia' installato - va installato
        # GLOBALMENTE (npm install -g @pnp/cli-microsoft365) prima che possa funzionare.
        # Installato qui, PRIMA che il server parta per la primissima volta, cosi' il PRIMO
        # processo server mai avviato su questo PC ha gia' 'm365' visibile sul PATH - evita
        # del tutto il "funziona solo dopo un riavvio completo" gia' documentato per
        # l'installazione lazy dentro Assert-M365OpsCliMicrosoft365Installed (Private, che
        # resta comunque come rete di sicurezza per chi salta questo installer, es. sviluppo
        # locale diretto da Server.ps1).
        Write-InstallerLog "=== CLI Microsoft 365 (richiesta dal connettore AI CLI-Microsoft365) ==="
        $hasNodeNow = (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue)
        if (-not $hasNodeNow) {
            Write-InstallerLog "  Saltata: richiede Node.js/npm, non ancora disponibile in questo momento (M365Ops la installera' comunque al primo utilizzo del connettore, se serve)."
        } else {
            $npmCmd = (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue).Source
            if (-not $npmCmd) { $npmCmd = (Get-Command 'npm' -ErrorAction SilentlyContinue).Source }
            $hasM365 = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'm365' -ErrorAction SilentlyContinue)
            if ($hasM365) {
                Write-InstallerLog "  Gia' presente."
            } elseif (-not $npmCmd) {
                Write-InstallerLog "  Saltata: comando 'npm' non risolvibile subito dopo l'installazione di Node.js - M365Ops la installera' comunque al primo utilizzo del connettore."
            } else {
                $statusLabel.Text = 'Installazione di CLI Microsoft 365...'
                Write-InstallerLog "  npm install -g @pnp/cli-microsoft365 in corso..."
                $tmpOut = [System.IO.Path]::GetTempFileName()
                try {
                    $proc = Start-Process -FilePath $npmCmd -ArgumentList @('install', '-g', '@pnp/cli-microsoft365') -PassThru -WindowStyle Hidden -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpOut
                    Wait-ProcessWithLiveOutput -Process $proc -OutputFile $tmpOut -BaseStatusText 'Installazione di CLI Microsoft 365...'
                    if ($proc.ExitCode -eq 0) {
                        Write-InstallerLog "  CLI Microsoft 365 installata."
                    } else {
                        Write-InstallerLog "  Installazione fallita (npm exit code $($proc.ExitCode)) - M365Ops la ritentera' comunque al primo utilizzo del connettore."
                    }
                } finally {
                    Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
                }
                # Aggiorna il PATH del processo corrente dal registro - stesso motivo gia'
                # documentato altrove in questo file per winget: senza, un comando appena
                # installato da un processo figlio non e' visibile a QUESTO processo finche'
                # non viene riavviato manualmente.
                $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            }
        }
        $progressBar.Value = 2

        Write-InstallerLog "=== Microsoft Edge (per export PDF) ==="
        $hasEdge = (Get-Command 'msedge.exe' -ErrorAction SilentlyContinue) -or (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")
        if ($hasEdge) {
            Write-InstallerLog "  Gia' presente."
        } else {
            $statusLabel.Text = 'Installazione di Microsoft Edge...'
            Invoke-M365OpsWingetInstall -WingetPath $wingetPath -PackageId 'Microsoft.Edge' -FriendlyName 'Microsoft Edge' | Out-Null
        }
    } else {
        Write-InstallerLog "=== Node.js / Microsoft Edge ==="
        Write-InstallerLog "  Saltati: senza winget non possono essere installati automaticamente qui (M365Ops li ritentera' comunque al primo avvio del server)."
    }
    $progressBar.Value = 3

    # Moduli PowerShell (22/08/2026, richiesto esplicitamente dall'utente: "installa TUTTO
    # come prerequisito" dopo un login Exchange delegato riuscito ma poi fallito per un
    # ExchangeOnlineManagement mancante) - installati qui, visibili, invece che solo dentro
    # Install-M365OpsPrerequisites (che gira dopo, senza finestra, dentro Launch-M365Ops.ps1) -
    # cosi' un'attesa di decine di secondi per modulo non sembra piu' un buco silenzioso tra
    # la chiusura di questa finestra e l'apertura del browser.
    Write-InstallerLog "=== Moduli PowerShell (Exchange/Teams/SharePoint/Excel/Intune/PDF) ==="
    if (Test-M365OpsPwshPresent) {
        $pwshPath = Get-M365OpsPwshPath
        if ($pwshPath) {
            # Elenco completo (22/08/2026, secondo giro dopo "ma i moduli teams sharepoint
            # graph etc ci sono????" - vedi lo stesso elenco/commento in
            # Install-M365OpsPrerequisites.ps1 per il dettaglio del perche' Graph non serve un
            # modulo qui).
            # ExchangeOnlineManagement + MicrosoftTeams NON hanno piu' una RequiredVersion
            # fissata qui (26/08/2026, sostituisce il pin a coppia 3.4.0/6.5.0 introdotto il
            # 25/08/2026) - vedi Assert-M365OpsExoSafeVersion.ps1/
            # Assert-M365OpsTeamsSafeVersion.ps1 per il perche' completo: con l'isolamento
            # reattivo dei processi ora in vigore per il conflitto di sezione 6.6, non serve
            # piu' restare su una coppia di versioni "verificata sicura" - un eventuale
            # conflitto viene gestito isolando la connessione al bisogno, non evitandolo a
            # monte scegliendo con cura una versione. Questa GUI installa quindi "l'ultima
            # disponibile" per entrambi, come per ogni altro modulo qui sotto - la pulizia di
            # eventuali versioni vecchie gia' presenti (installate a mano, o da una versione
            # precedente di M365Ops con un pin diverso) avviene al primo uso reale, dentro
            # Assert-M365OpsExoSafeVersion/Assert-M365OpsTeamsSafeVersion (il vero modulo
            # M365Ops non e' ancora importato in questo processo figlio, quindi non puo'
            # farlo direttamente da qui).
            $moduleChecks = @(
                @{ Name = 'ExchangeOnlineManagement'; FriendlyName = 'ExchangeOnlineManagement' }
                @{ Name = 'ImportExcel'; FriendlyName = 'ImportExcel' }
                @{ Name = 'IntuneWin32App'; FriendlyName = 'IntuneWin32App' }
                @{ Name = 'MicrosoftTeams'; FriendlyName = 'MicrosoftTeams' }
                @{ Name = 'PnP.PowerShell'; FriendlyName = 'PnP.PowerShell (SharePoint)' }
                @{ Name = 'PdfLexer'; FriendlyName = 'PdfLexer (estrazione testo PDF)' }
            )
            # Un solo processo pwsh.exe per controllare la presenza di TUTTI i moduli insieme
            # (non uno per modulo) - stesso principio del fix qui sotto per l'installazione:
            # meno processi separati che toccano PackageManagement/PowerShellGet in sequenza
            # ravvicinata, meno rischio di collisione sugli stessi file. Nessun modulo qui ha
            # piu' una versione fissata (vedi sopra) - "presente" significa solo "e' installata
            # QUALUNQUE versione", la scelta di quale tenere/rimuovere e' del vero modulo
            # M365Ops al primo uso reale.
            $specsForCheck = ($moduleChecks | ForEach-Object { "$($_.Name)=" }) -join ';'
            $checkCmd = "foreach (`$spec in ('$specsForCheck' -split ';')) { `$p = `$spec -split '=',2; `$n = `$p[0]; `$found = [bool](Get-Module -ListAvailable -Name `$n); if (`$found) { Write-Output ('PRESENT:' + `$n) } else { Write-Output ('MISSING:' + `$n) } }"
            $checkOutput = (& $pwshPath -NoProfile -Command $checkCmd 2>$null | Out-String)
            $missingModules = @()
            foreach ($m in $moduleChecks) {
                if ($checkOutput -match "PRESENT:$([regex]::Escape($m.Name))(\r?\n|$)") {
                    Write-InstallerLog "  $($m.FriendlyName): gia' presente."
                } else {
                    $missingModules += $m
                }
            }
            if ($missingModules.Count -gt 0) {
                $statusLabel.Text = "Installazione di $($missingModules.Count) moduli PowerShell..."
                Invoke-M365OpsModuleInstall -PwshPath $pwshPath -Modules $missingModules | Out-Null
            }
        } else {
            Write-InstallerLog "  Saltati: percorso di pwsh.exe non risolvibile in questo momento (M365Ops li installera' comunque al primo avvio del server)."
        }
    } else {
        Write-InstallerLog "  Saltati: richiedono PowerShell 7, non ancora disponibile in questo momento."
    }
    $progressBar.Value = 4

    if (Test-M365OpsPwshPresent) {
        $statusLabel.Text = 'Prerequisiti pronti - avvio M365Ops...'
        Write-InstallerLog ""
        Write-InstallerLog "Fatto. Questa finestra si chiude da sola tra un istante."
        $script:exitCode = 0
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 1200
        $form.Close()
    } else {
        $statusLabel.Text = 'PowerShell 7 non disponibile - installazione manuale necessaria.'
        Write-InstallerLog ""
        Write-InstallerLog "Installa PowerShell 7 manualmente da https://aka.ms/powershell-release, poi rilancia M365Ops.bat."
        $script:exitCode = 1
        $closeButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
exit $exitCode
