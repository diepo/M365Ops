<#
    Termina forzatamente il processo del server M365Ops (anche se bloccato/non risponde a
    nessuna richiesta HTTP) e lo riavvia da M365Ops.bat - pensato per essere lanciato da
    fuori, quando il server e' congelato e non puo' aiutarsi da solo (un pulsante DENTRO la
    pagina web non funzionerebbe in questo caso: se il server e' bloccato, non puo' nemmeno
    ricevere/processare il click sul proprio pulsante - stesso motivo per cui, durante un
    blocco reale, anche il tab Log smette di rispondere).

    Richiesto esplicitamente dall'utente il 22/08/2026 dopo aver dovuto chiudere a mano
    pwsh.exe da Task Manager durante il blocco Teams/WAM (poi risolto in v0.9.35, ma questo
    resta uno strumento utile per qualunque futuro blocco imprevisto).

    Windows PowerShell 5.1 compatibile (non richiede che pwsh.exe funzioni - e' proprio
    pwsh.exe il processo che questo script deve poter terminare anche se e' lui stesso
    a essere bloccato).

    Termina SOLO i processi pwsh.exe che stanno eseguendo Gui\Server.ps1 DI QUESTA
    installazione specifica (percorso della cartella confrontato esplicitamente) - mai
    "tutti i pwsh.exe di sistema", che potrebbero appartenere a tutt'altro.

    31/08/2026 - stesso bug reale di Launch-M365Ops.ps1 (vedi note li' per il dettaglio
    completo): cliccare "Termina e riavvia" piu' volte in rapida successione (di nuovo perche'
    senza nessun feedback visibile sembrava non aver fatto nulla) poteva terminare un riavvio
    gia' in corso da un click precedente, prima ancora che diventasse pronto, ripartendo la
    corsa da capo - o, peggio, sovrapporsi al riavvio di un ALTRO click concorrente. Corretto
    controllando lo stesso lock file usato da Launch-M365Ops.ps1 (Config\startup.lock) PRIMA di
    terminare qualunque processo: se un avvio e' gia' onestamente in corso da un altro click,
    questo script non lo interrompe (terminarlo a meta' sarebbe controproducente, non
    protettivo) - aspetta semplicemente che diventi pronto, esattamente come farebbe un secondo
    click su "Avvia". Aggiunta anche la stessa finestra di avanzamento non modale
    (Tools\M365OpsStartupUI.ps1) per dare evidenza visiva invece del solo testo in console.
#>
$root = $PSScriptRoot
$serverScriptPath = (Join-Path $root 'Gui\Server.ps1')
$lockPath = Join-Path $root 'Config\startup.lock'
$activePortFile = Join-Path $root 'Config\active-port.txt'
$stageFile = Join-Path $root 'Config\startup-stage.txt'

. (Join-Path $root 'Tools\M365OpsStartupLock.ps1')
. (Join-Path $root 'Tools\M365OpsStartupUI.ps1')

function Test-M365OpsServerUp {
    param([int]$TestPort)
    try {
        Invoke-RestMethod -Uri "http://localhost:$TestPort/api/status" -Method GET -TimeoutSec 2 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

Write-Host "M365Ops - Termina e riavvia" -ForegroundColor Cyan

$window = New-M365OpsStartupWindow -Title 'M365Ops - Termina e riavvia'
Set-M365OpsStartupStage -Window $window -Stage "Verifico se un avvio e' gia'' in corso..."

# Tentativo di 2s (un po' piu' generoso dei 500ms usati da Launch-M365Ops.ps1: qui l'utente ha
# scelto esplicitamente "termina e riavvia", vale la pena una piccola attesa in piu' prima di
# rinunciare a terminare qualcosa). Se un altro processo tiene gia' il lock, significa che un
# avvio e' onestamente in corso in questo momento da un altro click - non va interrotto a meta',
# va solo atteso.
$lockHandle = Lock-M365OpsStartup -LockPath $lockPath -TimeoutMs 2000

if (-not $lockHandle) {
    Write-Host "Un avvio e' gia' in corso da un altro processo - lo attendo invece di interromperlo." -ForegroundColor Yellow
    Set-M365OpsStartupStage -Window $window -Stage "Un avvio e' gia'' in corso altrove - lo attendo (non lo interrompo)..."
    $ready = $false
    $waitPort = 8743
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        Update-M365OpsStartupWindow -Window $window -StageFilePath $stageFile
        if (Test-Path $activePortFile) {
            $currentPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($currentPort -match '^\d+$') { $waitPort = [int]$currentPort }
        }
        if (Test-M365OpsServerUp -TestPort $waitPort) { $ready = $true; break }
    }
    Close-M365OpsStartupWindow -Window $window | Out-Null
    Start-Process "http://localhost:$waitPort/"
    if ($ready) {
        Write-Host "Pronto - browser aperto sulla porta $waitPort." -ForegroundColor Green
    } else {
        Write-Host "Il server non ha risposto entro 30s - la pagina e' stata aperta comunque, riprova tra poco." -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
    return
}

try {
    Write-Host "Cerco processi del server bloccato..."
    Set-M365OpsStartupStage -Window $window -Stage 'Termino il processo server bloccato...'

    $killed = 0
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.CommandLine -and $p.CommandLine.Contains($serverScriptPath)) {
                Write-Host "Termino processo PID $($p.ProcessId)..." -ForegroundColor Yellow
                try {
                    Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                    $killed++
                } catch {
                    Write-Host "Impossibile terminare PID $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Host "Errore cercando i processi: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($killed -eq 0) {
        Write-Host "Nessun processo server trovato in esecuzione (forse era gia' fermo)." -ForegroundColor Yellow
    } else {
        Write-Host "$killed processo(i) terminato(i)." -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
} finally {
    # Rilasciato SUBITO dopo il kill (non tenuto fino alla fine dello script): M365Ops.bat, tra
    # un attimo, lancera' Launch-M365Ops.ps1, che deve poter riacquisire il lock da zero per
    # gestire lui stesso l'avvio vero e proprio (con la sua finestra e il suo polling di
    # readiness) - tenerlo qui bloccherebbe inutilmente quel riavvio.
    Unlock-M365OpsStartup -LockHandle $lockHandle
}

Write-Host "Riavvio M365Ops..."
Set-M365OpsStartupStage -Window $window -Stage 'Riavvio in corso...'
Close-M365OpsStartupWindow -Window $window | Out-Null

# Da qui in poi, Launch-M365Ops.ps1 (invocato da M365Ops.bat) mostra la propria finestra di
# avanzamento e gestisce l'attesa di readiness - nessuna duplicazione di quella logica qui.
Start-Process -FilePath (Join-Path $root 'M365Ops.bat') -WorkingDirectory $root
Write-Host "Fatto - il browser si aprira' automaticamente tra pochi secondi." -ForegroundColor Green
Start-Sleep -Seconds 3
