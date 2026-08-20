<#
    Avvia (o riusa) il server M365Ops e apre il browser sulla chat - pensato per essere
    lanciato da M365Ops.bat con un doppio click, non a mano. Se il server e' gia' attivo
    (verificato con una vera chiamata HTTP, non solo un controllo di porta) NON lo riavvia
    ne' ne avvia una seconda copia in parallelo: apre solo il browser sulla sessione gia'
    in corso, cosi' non si perde lo stato (tenant attivo, file caricato, connessioni).

    Questo script gira sempre con -WindowStyle Hidden (lanciato da M365Ops.bat): qualunque
    fallimento qui dentro e' altrimenti invisibile, sia per chi fa doppio click sia per uno
    script/automazione che lo invoca senza aspettarne il completamento. Per questo ogni esito
    (OK o FAILED) viene sia scritto in Config\last-start-status.txt (controllabile a
    programma) sia mostrato con un MessageBox nei casi di errore reale.
#>
param(
    [int]$Port
)

$root = $PSScriptRoot
$serverScript = Join-Path $root 'Gui\Server.ps1'
$activePortFile = Join-Path $root 'Config\active-port.txt'
$portPrefFile = Join-Path $root 'Config\server-port.txt'
$statusFile = Join-Path $root 'Config\last-start-status.txt'

function Write-M365OpsStartupStatus {
    param([string]$Status, [string]$Detail = '')
    try {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$Status`t$Detail"
        Set-Content -Path $statusFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {}
}

# MessageBox visibile anche a -WindowStyle Hidden: e' l'unico modo per far sapere a chi ha
# fatto doppio click su M365Ops.bat che qualcosa e' andato storto, dato che qui non c'e'
# nessuna console visibile su cui scrivere.
function Show-M365OpsStartupError {
    param([string]$Message)
    Write-M365OpsStartupStatus -Status 'FAILED' -Detail $Message
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            "$Message`n`nLog: $(Join-Path $root 'Logs\server-console-error.log')",
            'M365Ops - Avvio non riuscito',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {}
}

function Test-M365OpsServerUp {
    param([int]$TestPort)
    try {
        Invoke-RestMethod -Uri "http://localhost:$TestPort/api/status" -Method GET -TimeoutSec 2 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Se un'istanza e' gia' attiva, la porta VERA e' quella scritta da Server.ps1 all'ultimo avvio
# (puo' differire dal default/dalla preferenza se all'epoca era occupata da un altro
# programma) - va controllata quella, non un valore assunto, altrimenti si rischia di aprire
# il browser su una porta morta mentre il server vero risponde altrove.
if (Test-Path $activePortFile) {
    $lastKnownPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($lastKnownPort -match '^\d+$' -and (Test-M365OpsServerUp -TestPort ([int]$lastKnownPort))) {
        Start-Process "http://localhost:$lastKnownPort/"
        Write-M365OpsStartupStatus -Status 'OK' -Detail "Istanza gia' attiva, porta $lastKnownPort"
        return
    }
}

# Nessuna istanza attiva: la avvia da zero, riprendendo l'ultimo tenant usato se noto
# (Connect-M365Ops lo salva ad ogni cambio profilo) - altrimenti il default del server.
$lastTenantFile = Join-Path $root 'Config\last-active-tenant.txt'
$tenantProfile = $null
if (Test-Path $lastTenantFile) {
    try { $tenantProfile = (Get-Content $lastTenantFile -Raw -ErrorAction Stop).Trim() } catch {}
}
if (-not $tenantProfile) { $tenantProfile = 'contoso-test' }

# Porta di PARTENZA da provare: parametro esplicito > preferenza salvata (tab Manutenzione) >
# 8743. E' solo un punto di partenza - se occupata da un altro programma, Server.ps1 sceglie
# da solo la prima libera successiva e scrive quella reale in Config\active-port.txt.
if (-not $Port) {
    $Port = 8743
    if (Test-Path $portPrefFile) {
        $savedPort = (Get-Content $portPrefFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($savedPort -match '^\d+$') { $Port = [int]$savedPort }
    }
}

$logDir = Join-Path $root 'Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# Collegamento sul Desktop con icona dedicata (22/08/2026, richiesto esplicitamente
# dall'utente: "disegna una icona bellina per il bat" - un .bat non puo' avere un'icona
# propria, serve un collegamento .lnk). Idempotente e non bloccante: uno script a parte
# (Tools\New-M365OpsShortcut.ps1) crea/aggiorna il collegamento solo se serve davvero,
# un fallimento qui e' solo cosmetico e non deve mai impedire l'avvio del server.
try {
    & (Join-Path $root 'Tools\New-M365OpsShortcut.ps1') -Root $root
} catch {}

# Controllo prerequisiti (Node.js, Microsoft Edge) PRIMA di avviare il server, in modo
# silenzioso - nessun click richiesto. Richiesto esplicitamente dall'utente il 18/08/2026:
# "deve esserci l'autoinstallazione di tutto cio che manca per essere pronta all'uso".
# Il pulsante "Installa automaticamente" nel banner Impostazioni resta come fallback manuale
# per il solo caso in cui questo controllo silenzioso fallisca (es. winget assente/bloccato).
try {
    Import-Module (Join-Path $root 'M365Ops.psd1') -Force -ErrorAction Stop
    $prereqResults = Install-M365OpsPrerequisites
    $prereqResults | ForEach-Object {
        if ($_.Status -eq 'Failed') {
            Write-Host "Prerequisito non installato automaticamente: $($_.Name) - $($_.Detail)" -ForegroundColor Yellow
        }
    }
} catch {
    # Non bloccante di proposito: un fallimento qui (es. Import-Module rotto) non deve impedire
    # il tentativo di avvio del server, che importa il modulo per conto suo in un processo
    # separato (riga sotto) e potrebbe comunque riuscire. Si registra solo per diagnosi.
    Write-M365OpsStartupStatus -Status 'WARNING' -Detail "Controllo prerequisiti non riuscito: $($_.Exception.Message)"
}

# Sempre pwsh.exe (PowerShell 7), mai powershell.exe (5.1) - il modulo e il server sono
# scritti e testati per PS7, non per Windows PowerShell. Non ci si affida a $PID/Get-Process
# qui perche' questo script stesso potrebbe girare sotto un pwsh.exe diverso da quello
# risolto da PATH a seconda di come e' stato invocato - si cerca il comando esplicitamente.
$pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwshPath) {
    $candidatePaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    $pwshPath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $pwshPath) {
    Show-M365OpsStartupError "PowerShell 7 (pwsh.exe) non trovato su questo PC - necessario per avviare M365Ops."
    return
}

# -STA aggiunto il 17/08/2026 (bug reale, vedi lo stesso fix nel ramo di riavvio dentro
# Server.ps1 per i dettagli): senza, pwsh gira in MTA e le finestre di login interattivo
# SharePoint/Teams falliscono con "Specified method is not supported" (controlli COM,
# richiedono un thread STA).
Start-Process -FilePath $pwshPath -ArgumentList @('-NoProfile', '-STA', '-File', $serverScript, '-TenantProfile', $tenantProfile, '-Port', $Port) -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir 'server-console.log') -RedirectStandardError (Join-Path $logDir 'server-console-error.log')

# Attende che risponda prima di aprire il browser, per evitare la pagina "impossibile
# raggiungere il sito" se il browser si apre prima che il server sia pronto (~1-2s tipici).
# Server.ps1 potrebbe finire su una porta DIVERSA da quella richiesta se occupata da un altro
# programma - si rilegge active-port.txt ad ogni giro invece di continuare a controllare solo
# quella di partenza, che potrebbe non essere mai quella vera.
# Budget alzato da 10s a 30s il 22/08/2026 (bug reale segnalato dal vivo su Windows Sandbox,
# hardware volutamente limitato): un primo avvio a freddo puo' impiegare piu' di 10s per
# importare il modulo (350+ file in Public\/Private\) su CPU/disco piu' lenti - il ciclo esce
# comunque appena il server risponde, quindi il percorso comune veloce (~1-2s) resta invariato,
# solo il caso limite lento smette di mostrare un errore fuorviante mentre sta ancora lavorando.
$ready = $false
$actualPort = $Port
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $activePortFile) {
        $currentPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($currentPort -match '^\d+$') { $actualPort = [int]$currentPort }
    }
    if (Test-M365OpsServerUp -TestPort $actualPort) { $ready = $true; break }
}

Start-Process "http://localhost:$actualPort/"
if ($ready) {
    Write-M365OpsStartupStatus -Status 'OK' -Detail "Porta $actualPort"
} else {
    Show-M365OpsStartupError "Il server non ha risposto entro 10s sulla porta $actualPort. La pagina e' stata aperta comunque, ma potrebbe non caricarsi - riprova tra poco o controlla i log."
}
