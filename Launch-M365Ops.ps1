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

    31/08/2026 - due bug reali segnalati dal vivo dall'utente ("a volte si apre subito, altre
    volte resta a pensarci un sacco e se clicco piu' volte non funziona nulla, salvo poi
    aprirsi tutte le istanze insieme su porte diverse"), corretti insieme:
    1) NESSUNA mutua esclusione tra avvii concorrenti: se questo script viene lanciato una
       seconda volta (doppio click, o un click impaziente durante un avvio a freddo ancora
       invisibile) mentre un primo avvio e' ancora in corso, il controllo "server gia' attivo"
       fallisce per ENTRAMBE le copie (nessuna delle due ha ancora un server in ascolto), e
       ciascuna partiva con la propria copia di Server.ps1 - che sceglie da sola la prima
       porta libera successiva se quella di partenza e' occupata (comportamento corretto per
       "un altro programma occupa la porta", ma qui usato per errore per "un'altra MIA copia e'
       gia' partita"). Risultato: piu' server, ognuno su una porta diversa, aperti tutti
       insieme in browser quando ciascuno finisce di avviarsi. Corretto con un lock file a
       livello di sistema operativo (Config\startup.lock, Tools\M365OpsStartupLock.ps1): un
       secondo avvio concorrente non parte una seconda copia, aspetta che quella in corso sia
       pronta e apre il browser sulla STESSA istanza.
    2) Zero evidenza visiva durante un avvio a freddo (fino a 30s, girava con -WindowStyle
       Hidden): da fuori sembrava che il click non avesse avuto effetto, inducendo a ricliccare
       (che scatenava il bug #1). Corretto con una piccola finestra di avanzamento non modale
       (Tools\M365OpsStartupUI.ps1), mostrata SOLO quando si esce dal percorso rapido (istanza
       gia' pronta) - il caso comune resta invariato, istantaneo e silenzioso.
    In piu', velocizzato l'avvio a freddo: questo script importava PRIMA l'intero modulo (350+
    file, ~4.7s misurati dal vivo) solo per richiamare Install-M365OpsPrerequisites, per poi
    avviare Server.ps1 che importa di nuovo l'INTERO modulo per conto proprio - un secondo
    Import-Module completo, in serie, per lo stesso lavoro. Il controllo prerequisiti e' stato
    spostato dentro Server.ps1 stesso (dopo il suo import, che gli serve comunque), eliminando
    qui l'import doppio: circa 4.7s in meno sul percorso critico di ogni avvio a freddo,
    verificato dal vivo prima/dopo il cambio.
#>
param(
    [int]$Port
)

$root = $PSScriptRoot
$serverScript = Join-Path $root 'Gui\Server.ps1'
$activePortFile = Join-Path $root 'Config\active-port.txt'
$portPrefFile = Join-Path $root 'Config\server-port.txt'
$statusFile = Join-Path $root 'Config\last-start-status.txt'
$lockPath = Join-Path $root 'Config\startup.lock'
# Scritto da Server.ps1 stesso (un processo separato) man mano che avanza nell'avvio -
# riletto qui durante l'attesa cosi' la finestra mostra CHE COSA sta succedendo, non solo il
# tempo che passa (31/08/2026, richiesto esplicitamente dall'utente).
$stageFile = Join-Path $root 'Config\startup-stage.txt'

. (Join-Path $root 'Tools\M365OpsStartupLock.ps1')
. (Join-Path $root 'Tools\M365OpsStartupUI.ps1')

function Write-M365OpsStartupStatus {
    param([string]$Status, [string]$Detail = '', [double]$ElapsedSeconds = -1)
    try {
        $elapsedPart = if ($ElapsedSeconds -ge 0) { "{0:N1}s" -f $ElapsedSeconds } else { '' }
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$Status`t$Detail`t$elapsedPart"
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

$overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Percorso rapido: se un'istanza e' gia' attiva, la porta VERA e' quella scritta da Server.ps1
# all'ultimo avvio (puo' differire dal default/dalla preferenza se all'epoca era occupata da un
# altro programma) - va controllata quella, non un valore assunto, altrimenti si rischia di
# aprire il browser su una porta morta mentre il server vero risponde altrove. Nessun lock
# coinvolto qui: se risponde davvero, non c'e' nessun avvio da coordinare con nessuno.
if (Test-Path $activePortFile) {
    $lastKnownPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($lastKnownPort -match '^\d+$' -and (Test-M365OpsServerUp -TestPort ([int]$lastKnownPort))) {
        Start-Process "http://localhost:$lastKnownPort/"
        Write-M365OpsStartupStatus -Status 'OK' -Detail "Istanza gia' attiva, porta $lastKnownPort" -ElapsedSeconds $overallStopwatch.Elapsed.TotalSeconds
        return
    }
}

# Da qui in poi serve un avvio vero (o l'attesa di uno gia' in corso altrove) - percorso lento,
# mostra la finestra di avanzamento invece di restare invisibile.
$window = New-M365OpsStartupWindow -Title 'M365Ops - Avvio'
Set-M365OpsStartupStage -Window $window -Stage 'Verifica di eventuali avvii gia'' in corso...'

# Tentativo BREVE (mezzo secondo): serve solo a deduplicare due click quasi simultanei, non a
# mettersi in coda per l'intera durata di un avvio a freddo altrui (che richiederebbe comunque
# di attendere sotto, identico sia che si tenga il lock sia che no).
$lockHandle = Lock-M365OpsStartup -LockPath $lockPath -TimeoutMs 500

if (-not $lockHandle) {
    # Un'altra copia di questo stesso script (o di Kill-And-Restart) sta gia' avviando il
    # server in questo momento - NON se ne avvia una seconda: si aspetta che quella in corso
    # diventi pronta e si apre il browser sulla STESSA istanza. Questo e' esattamente il fix
    # del bug "clicco piu' volte e si aprono tutte le istanze insieme".
    Set-M365OpsStartupStage -Window $window -Stage "Un altro avvio e' gia'' in corso - attendo che sia pronto..."
    $ready = $false
    $waitPort = $Port
    if (-not $waitPort) { $waitPort = 8743 }
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        Update-M365OpsStartupWindow -Window $window -StageFilePath $stageFile
        if (Test-Path $activePortFile) {
            $currentPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($currentPort -match '^\d+$') { $waitPort = [int]$currentPort }
        }
        if (Test-M365OpsServerUp -TestPort $waitPort) { $ready = $true; break }
    }
    $elapsed = Close-M365OpsStartupWindow -Window $window
    Start-Process "http://localhost:$waitPort/"
    if ($ready) {
        Write-M365OpsStartupStatus -Status 'OK' -Detail "Istanza avviata da un altro processo, porta $waitPort" -ElapsedSeconds $elapsed
    } else {
        Show-M365OpsStartupError "Un altro avvio era in corso ma il server non ha risposto entro 30s sulla porta $waitPort. La pagina e' stata aperta comunque - riprova tra poco o controlla i log."
    }
    return
}

try {
    # Nessuna istanza attiva: la avvia da zero, riprendendo l'ultimo tenant usato se noto
    # (Connect-M365Ops lo salva ad ogni cambio profilo) - altrimenti il default del server.
    $lastTenantFile = Join-Path $root 'Config\last-active-tenant.txt'
    $tenantProfile = $null
    if (Test-Path $lastTenantFile) {
        try { $tenantProfile = (Get-Content $lastTenantFile -Raw -ErrorAction Stop).Trim() } catch {}
    }
    if (-not $tenantProfile) { $tenantProfile = 'contoso-test' }

    # Porta di PARTENZA da provare: parametro esplicito > preferenza salvata (tab Manutenzione)
    # > 8743. E' solo un punto di partenza - se occupata da un altro programma, Server.ps1
    # sceglie da solo la prima libera successiva e scrive quella reale in Config\active-port.txt.
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
        Close-M365OpsStartupWindow -Window $window | Out-Null
        Show-M365OpsStartupError "PowerShell 7 (pwsh.exe) non trovato su questo PC - necessario per avviare M365Ops."
        return
    }

    Set-M365OpsStartupStage -Window $window -Stage 'Avvio del processo server...'
    # Ripulito prima di avviare Server.ps1 (che lo riscrive lui stesso come primissima cosa che
    # fa): senza, un eventuale contenuto residuo dell'avvio PRECEDENTE (es. "Server pronto...")
    # resterebbe visibile per una frazione di secondo prima di essere sovrascritto per davvero.
    Remove-Item -Path $stageFile -ErrorAction SilentlyContinue

    # -STA aggiunto il 17/08/2026 (bug reale, vedi lo stesso fix nel ramo di riavvio dentro
    # Server.ps1 per i dettagli): senza, pwsh gira in MTA e le finestre di login interattivo
    # SharePoint/Teams falliscono con "Specified method is not supported" (controlli COM,
    # richiedono un thread STA). Il controllo prerequisiti (Node.js/Edge/moduli PS) NON viene
    # piu' fatto qui: e' stato spostato dentro Server.ps1 stesso (subito dopo il suo import del
    # modulo, che gli serve comunque) per eliminare un secondo Import-Module completo in serie
    # - vedi nota in cima al file.
    Start-Process -FilePath $pwshPath -ArgumentList @('-NoProfile', '-STA', '-File', $serverScript, '-TenantProfile', $tenantProfile, '-Port', $Port) -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logDir 'server-console.log') -RedirectStandardError (Join-Path $logDir 'server-console-error.log')

    # Attende che risponda prima di aprire il browser, per evitare la pagina "impossibile
    # raggiungere il sito" se il browser si apre prima che il server sia pronto. Server.ps1
    # potrebbe finire su una porta DIVERSA da quella richiesta se occupata da un altro
    # programma - si rilegge active-port.txt ad ogni giro invece di continuare a controllare
    # solo quella di partenza, che potrebbe non essere mai quella vera.
    # Budget 30s (alzato da 10s il 22/08/2026, bug reale su Windows Sandbox con hardware
    # limitato): un primo avvio a freddo puo' impiegare piu' di 10s per importare il modulo
    # (350+ file in Public\/Private\) su CPU/disco piu' lenti - il ciclo esce comunque appena
    # il server risponde, quindi il percorso comune (~1-2s dopo il fix del doppio import) resta
    # invariato, solo il caso limite lento smette di mostrare un errore fuorviante.
    Set-M365OpsStartupStage -Window $window -Stage 'Attendo che il server risponda...'
    $ready = $false
    $actualPort = $Port
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        Update-M365OpsStartupWindow -Window $window -StageFilePath $stageFile
        if (Test-Path $activePortFile) {
            $currentPort = (Get-Content $activePortFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($currentPort -match '^\d+$') { $actualPort = [int]$currentPort }
        }
        if (Test-M365OpsServerUp -TestPort $actualPort) { $ready = $true; break }
    }

    if ($ready) { Set-M365OpsStartupStage -Window $window -Stage 'Pronto - apertura del browser...' }
    $elapsed = Close-M365OpsStartupWindow -Window $window

    Start-Process "http://localhost:$actualPort/"
    if ($ready) {
        Write-M365OpsStartupStatus -Status 'OK' -Detail "Porta $actualPort" -ElapsedSeconds $elapsed
    } else {
        Write-M365OpsStartupStatus -Status 'FAILED' -Detail "Timeout 30s sulla porta $actualPort" -ElapsedSeconds $elapsed
        Show-M365OpsStartupError "Il server non ha risposto entro 30s sulla porta $actualPort. La pagina e' stata aperta comunque, ma potrebbe non caricarsi - riprova tra poco o controlla i log."
    }
} finally {
    Unlock-M365OpsStartup -LockHandle $lockHandle
}
