<#
    Avvia (o riusa) il server M365Ops e apre il browser sulla chat - pensato per essere
    lanciato da M365Ops.bat con un doppio click, non a mano. Se il server e' gia' attivo
    (verificato con una vera chiamata HTTP, non solo un controllo di porta) NON lo riavvia
    ne' ne avvia una seconda copia in parallelo: apre solo il browser sulla sessione gia'
    in corso, cosi' non si perde lo stato (tenant attivo, file caricato, connessioni).
#>
param(
    [int]$Port = 8743
)

$root = $PSScriptRoot
$serverScript = Join-Path $root 'Gui\Server.ps1'
$statusUrl = "http://localhost:$Port/api/status"
$homeUrl = "http://localhost:$Port/"

function Test-M365OpsServerUp {
    try {
        Invoke-RestMethod -Uri $statusUrl -Method GET -TimeoutSec 2 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

if (Test-M365OpsServerUp) {
    Start-Process $homeUrl
    return
}

# Nessuna istanza attiva: la avvia da zero, riprendendo l'ultimo tenant usato se noto
# (Connect-M365Ops lo salva ad ogni cambio profilo) - altrimenti il default del server.
$lastTenantFile = Join-Path $root 'Config\last-active-tenant.txt'
$tenantProfile = $null
if (Test-Path $lastTenantFile) {
    try { $tenantProfile = (Get-Content $lastTenantFile -Raw -ErrorAction Stop).Trim() } catch {}
}
if (-not $tenantProfile) { $tenantProfile = 'contoso-test' }

$logDir = Join-Path $root 'Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

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
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-M365OpsServerUp) { $ready = $true; break }
}

Start-Process $homeUrl
if (-not $ready) {
    Write-Host "Il server non ha risposto entro 10s - se la pagina non si carica, riprova tra poco." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}
