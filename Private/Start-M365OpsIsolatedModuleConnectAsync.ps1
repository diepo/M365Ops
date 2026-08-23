function Start-M365OpsIsolatedModuleConnectAsync {
    <#
    .SYNOPSIS
        Variante NON BLOCCANTE di Connect-M365OpsIsolatedModule: avvia il worker isolato e
        INVIA la richiesta "connect" senza aspettarne la risposta - torna subito al chiamante.
        Lo stato del login in corso va poi controllato con
        Get-M365OpsIsolatedModuleConnectAsyncStatus (polling), MAI con
        Invoke-M365OpsMcpRequest direttamente su questo stesso processo (romperebbe la
        corrispondenza id/risposta che il polling si aspetta di trovare).

        RICHIESTO ESPLICITAMENTE DALL'UTENTE il 23/08/2026 ("rendi la questione multi thread
        cosi che queste operazioni non blocchino tutto... trova un modo per velocizzare sti
        login"): il server e' a thread singolo per design (vedi Connect-M365OpsIsolatedModule.ps1
        e la documentazione estesa del progetto su questa scelta) - riscrivere l'intero server
        per essere davvero multi-thread e' stato scartato (rischio concreto di bug di
        concorrenza su stato condiviso critico per la sicurezza delle scritture, vedi la
        discussione con l'utente). Questa e' l'alternativa mirata concordata: il login
        INTERATTIVO (l'unica parte davvero lunga - attesa umana reale, non calcolo) avviene nel
        processo worker SEPARATO gia' esistente e collaudato per l'isolamento reattivo -
        bloccare QUEL processo durante l'attesa e' innocuo, blocca solo se stesso. Il processo
        server principale invece non aspetta mai sincronamente: manda la richiesta e torna
        subito, il chiamante (Gui/Server.ps1) risponde "connessione avviata" al browser e lascia
        che sia il browser a fare polling a intervalli (stesso schema gia' in uso per il
        device-code Graph/Exchange) - il ciclo principale del server (`$listener.GetContext()`)
        resta quindi libero di servire altre richieste (altri tenant, pagine, log) nel
        frattempo, invece di restare fermo per l'intera durata del login umano.

        BONUS DI ROBUSTEZZA, non il motivo primario ma un effetto reale: se il login
        interattivo dovesse causare un fault nativo non catturabile da .NET (es. un problema
        del broker WAM/COM - la preoccupazione originale dell'utente, "sembra che il server sia
        crashato"), a crashare sarebbe SOLO questo processo worker, mai il server principale.
    .PARAMETER ModuleType
        'Exchange' o 'Teams'.
    .PARAMETER ConnectParams
        Come per Connect-M365OpsIsolatedModule - vedi Get-M365OpsIsolatedConnectParams.
    .OUTPUTS
        pscustomobject con Status: 'AlreadyConnected' (nulla da attendere, i proxy sono gia'
        installati) oppure 'Started' (login avviato, chiama
        Get-M365OpsIsolatedModuleConnectAsyncStatus per sapere quando finisce).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType,
        [Parameter(Mandatory)] [hashtable]$ConnectParams
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    if (-not $script:M365OpsIsolatedWorkers) { $script:M365OpsIsolatedWorkers = @{} }
    if (-not $script:M365OpsIsolatedWorkers[$tenantName]) { $script:M365OpsIsolatedWorkers[$tenantName] = @{} }

    $existing = $script:M365OpsIsolatedWorkers[$tenantName][$ModuleType]
    if ($existing -and -not $existing.HasExited) {
        return [pscustomobject]@{ Status = 'AlreadyConnected' }
    }

    if (-not $script:M365OpsIsolatedPendingConnects) { $script:M365OpsIsolatedPendingConnects = @{} }
    $pendingKey = "$tenantName|$ModuleType"
    $alreadyPending = $script:M365OpsIsolatedPendingConnects[$pendingKey]
    if ($alreadyPending -and -not $alreadyPending.Process.HasExited) {
        # Un login e' gia' in corso per questa stessa coppia tenant+modulo (es. l'utente ha
        # ricaricato la pagina e ricliccato) - non ne avviamo un secondo, si continua ad
        # aspettare quello gia' partito.
        return [pscustomobject]@{ Status = 'Started' }
    }

    $workerScript = Join-Path $script:M365OpsModuleRoot 'Private\Workers\M365OpsIsolatedWorker.ps1'
    if (-not (Test-Path -LiteralPath $workerScript)) { throw "Worker isolato non trovato: $workerScript" }
    $pwshPath = (Get-Process -Id $PID).Path

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwshPath
    $psi.Arguments = "-NoProfile -File `"$workerScript`" -ModuleType $ModuleType"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    Write-M365OpsLog "Login asincrono: avvio un processo separato per $ModuleType (tenant '$tenantName') - il server resta libero di servire altre richieste nel frattempo."
    $process = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Milliseconds 800
    if ($process.HasExited) {
        $err = $process.StandardError.ReadToEnd()
        throw "Il processo isolato per $ModuleType si e' chiuso subito dopo l'avvio (exit $($process.ExitCode)). Stderr: $err"
    }

    # Stessa numerazione richieste JSON-RPC gia' usata dal percorso sincrono - un solo
    # contatore condiviso nello script scope del modulo, corretto perche' ogni ID e' comunque
    # unico a prescindere da quale percorso lo genera.
    $script:M365OpsMcpRequestId = if ($script:M365OpsMcpRequestId) { $script:M365OpsMcpRequestId + 1 } else { 1 }
    $requestId = $script:M365OpsMcpRequestId

    $payload = [ordered]@{ jsonrpc = "2.0"; method = "connect"; params = $ConnectParams; id = $requestId }
    $json = $payload | ConvertTo-Json -Depth 12 -Compress
    $process.StandardInput.WriteLine($json)
    $process.StandardInput.Flush()

    $isDelegatedIsolation = $script:M365OpsContext.AuthMode -eq 'Delegated'
    $script:M365OpsIsolatedPendingConnects[$pendingKey] = @{
        Process     = $process
        RequestId   = $requestId
        TenantName  = $tenantName
        ModuleType  = $ModuleType
        StartedAt   = Get-Date
        # Stesso limite gia' in uso lato sincrono (Connect-M365OpsIsolatedModule): un login
        # Delegato puo' legittimamente richiedere diversi minuti (attesa umana reale, MFA),
        # uno App-only no (solo calcolo) - oltre questo tempo il polling lo segnala come
        # scaduto invece di aspettare per sempre un worker forse bloccato per altri motivi.
        TimeoutSeconds = if ($isDelegatedIsolation) { 240 } else { 60 }
    }

    [pscustomobject]@{ Status = 'Started' }
}
