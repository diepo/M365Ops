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
$progressBar.Style = 'Marquee'
$progressBar.MarqueeAnimationSpeed = 30
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

    if (Test-M365OpsWingetPresent) {
        $wingetPath = Get-M365OpsWingetPath

        Write-InstallerLog "=== Node.js (richiesto da Lokka) ==="
        $hasNode = (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue)
        if ($hasNode) {
            Write-InstallerLog "  Gia' presente."
        } else {
            $statusLabel.Text = 'Installazione di Node.js...'
            Invoke-M365OpsWingetInstall -WingetPath $wingetPath -PackageId 'OpenJS.NodeJS.LTS' -FriendlyName 'Node.js' | Out-Null
        }

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

    $progressBar.Style = 'Continuous'
    $progressBar.Value = 100

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
