<#
    Avvia (o riusa) il server M365Ops e apre il browser sulla chat - pensato per essere
    lanciato da M365Ops.bat con un doppio click, non a mano. Se il server e' gia' attivo
    (verificato con una vera chiamata HTTP, non solo un controllo di porta) NON lo riavvia
    ne' ne avvia una seconda copia in parallelo: apre solo il browser sulla sessione gia'
    in corso, cosi' non si perde lo stato (tenant attivo, file caricato, connessioni).
#>
param(
    [int]$Port
)

$root = $PSScriptRoot
$serverScript = Join-Path $root 'Gui\Server.ps1'
$activePortFile = Join-Path $root 'Config\active-port.txt'
$portPrefFile = Join-Path $root 'Config\server-port.txt'

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
    Write-Host "Controllo automatico dei prerequisiti (Node.js/Edge) non riuscito: $($_.Exception.Message)" -ForegroundColor Yellow
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
    Write-Host "PowerShell 7 (pwsh.exe) non trovato su questo PC - necessario per avviare M365Ops." -ForegroundColor Red
    Start-Sleep -Seconds 5
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
$ready = $false
$actualPort = $Port
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $activePortFile) {
        $currentPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($currentPort -match '^\d+$') { $actualPort = [int]$currentPort }
    }
    if (Test-M365OpsServerUp -TestPort $actualPort) { $ready = $true; break }
}

Start-Process "http://localhost:$actualPort/"
if (-not $ready) {
    Write-Host "Il server non ha risposto entro 10s - se la pagina non si carica, riprova tra poco." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}
