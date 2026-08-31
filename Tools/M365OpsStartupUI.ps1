<#
    Piccola finestra WinForms non modale, per dare evidenza visiva + tempi durante l'avvio o
    il riavvio del server M365Ops - richiesta esplicitamente dall'utente il 31/08/2026 dopo un
    bug reale segnalato dal vivo: senza nessun feedback visibile durante un avvio a freddo
    (fino a 30s tra import modulo e connessione tenant), l'utente ricliccava piu' volte
    pensando che il primo click non avesse funzionato - ogni click avviava un
    Launch-M365Ops.ps1 completamente indipendente e, siccome nessuno dei processi concorrenti
    vedeva ancora un server in ascolto, partivano TUTTI una propria copia del server, ognuna
    finita su una porta diversa (Server.ps1 sceglie da sola la prima porta libera successiva) -
    da cui "si aprono tutte le istanze insieme su porte diverse" osservato dall'utente. La
    causa vera (nessuna mutua esclusione tra avvii concorrenti) e' corretta altrove con un lock
    file (Config\startup.lock, vedi Launch-M365Ops.ps1/Kill-And-Restart-M365Ops.ps1); questa
    finestra e' la parte "dare evidenza via GUI e calcolare i tempi" della richiesta.

    Dot-sourcabile sia da Launch-M365Ops.ps1 (pwsh.exe, PS7, invocato con -STA da M365Ops.bat)
    sia da Kill-And-Restart-M365Ops.ps1 (powershell.exe, PS 5.1) - usa solo
    System.Windows.Forms/System.Drawing, nessuna sintassi PS7-only, cosi' un solo file serve
    entrambi senza duplicazione.

    Non modale (Form.Show(), non ShowDialog()): il chiamante resta libero di continuare la
    propria logica di avvio/polling. Poiche' non gira nessun message loop WinForms vero e
    proprio, [System.Windows.Forms.Application]::DoEvents() va richiamato periodicamente
    (Update-M365OpsStartupWindow, o implicitamente ad ogni Set-M365OpsStartupStage) per far si'
    che la finestra resti reattiva e si ridisegni, altrimenti Windows la segnerebbe come "Non
    risponde" durante un'attesa lunga (es. i cicli da 500ms di polling della readiness HTTP).
#>

function New-M365OpsStartupWindow {
    param([string]$Title = 'M365Ops')
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(440, 150)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ControlBox = $false

    $stageLabel = New-Object System.Windows.Forms.Label
    $stageLabel.Text = 'Avvio in corso...'
    $stageLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $stageLabel.AutoSize = $false
    $stageLabel.Size = New-Object System.Drawing.Size(400, 40)
    $stageLabel.Location = New-Object System.Drawing.Point(20, 18)
    $form.Controls.Add($stageLabel)

    $timeLabel = New-Object System.Windows.Forms.Label
    $timeLabel.Text = '0.0s'
    $timeLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $timeLabel.ForeColor = [System.Drawing.Color]::Gray
    $timeLabel.AutoSize = $false
    $timeLabel.Size = New-Object System.Drawing.Size(400, 20)
    $timeLabel.Location = New-Object System.Drawing.Point(20, 62)
    $form.Controls.Add($timeLabel)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Style = 'Marquee'
    $progressBar.MarqueeAnimationSpeed = 30
    $progressBar.Size = New-Object System.Drawing.Size(400, 18)
    $progressBar.Location = New-Object System.Drawing.Point(20, 88)
    $form.Controls.Add($progressBar)

    $form.Show()
    $form.Activate()
    [System.Windows.Forms.Application]::DoEvents()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [pscustomobject]@{
        Form       = $form
        StageLabel = $stageLabel
        TimeLabel  = $timeLabel
        Stopwatch  = $sw
    }
}

function Set-M365OpsStartupStage {
    param($Window, [Parameter(Mandatory)] [string]$Stage)
    if (-not $Window -or $Window.Form.IsDisposed) { return }
    $Window.StageLabel.Text = $Stage
    $Window.TimeLabel.Text = "{0:N1}s" -f $Window.Stopwatch.Elapsed.TotalSeconds
    [System.Windows.Forms.Application]::DoEvents()
}

# Da richiamare durante le attese (es. dentro un ciclo di polling) senza cambiare lo stage
# mostrato - aggiorna solo il tempo trascorso e ripompa i messaggi Windows, cosi' la finestra
# non risulta "Non risponde" durante un'attesa lunga.
function Update-M365OpsStartupWindow {
    param($Window)
    if (-not $Window -or $Window.Form.IsDisposed) { return }
    $Window.TimeLabel.Text = "{0:N1}s" -f $Window.Stopwatch.Elapsed.TotalSeconds
    [System.Windows.Forms.Application]::DoEvents()
}

function Close-M365OpsStartupWindow {
    param($Window)
    if (-not $Window -or $Window.Form.IsDisposed) { return $null }
    $Window.Stopwatch.Stop()
    $elapsed = $Window.Stopwatch.Elapsed.TotalSeconds
    $Window.Form.Close()
    $Window.Form.Dispose()
    return $elapsed
}
