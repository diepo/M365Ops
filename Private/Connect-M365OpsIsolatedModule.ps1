function Connect-M365OpsIsolatedModule {
    <#
    .SYNOPSIS
        Attiva l'isolamento reattivo per un modulo (Exchange o Teams) - avvia un worker
        PowerShell in un processo SEPARATO (Private\Workers\M365OpsIsolatedWorker.ps1), lo
        autentica, e genera dinamicamente una funzione proxy globale per OGNI cmdlet che quel
        modulo esporta davvero (interrogato dal worker stesso, mai una lista mantenuta a mano -
        vedi il worker per il dettaglio). Da questo momento, QUALUNQUE chiamata bare a uno di
        quei cmdlet, da QUALUNQUE punto del modulo M365Ops (i 129+19 cmdlet Exchange/Teams gia'
        usati da Public\*.ps1, verificati con un audit completo il 26/08/2026 - nessuno di
        quei call site usa un oggetto sessione o un nome di comando calcolato, sempre e solo
        nomi letterali con parametri splattati, il presupposto che rende questo approccio
        sicuro), viene automaticamente intercettata e inoltrata al processo isolato invece di
        eseguire il vero cmdlet in-process - senza dover modificare NESSUNO di quei file.

        RICHIESTO ESPLICITAMENTE DALL'UTENTE (26/08/2026) come soluzione DEFINITIVA al
        conflitto .NET tra ExchangeOnlineManagement e MicrosoftTeams nello stesso processo
        (sezione 6.6 della guida - documentato e riaffrontato piu' volte in questa sessione,
        nessuna coppia di versioni si e' mai rivelata affidabile in ogni ordine/scenario): con
        l'isolamento, il conflitto non puo' semplicemente PIU' VERIFICARSI, perche' i due
        moduli non condividono mai lo stesso processo .NET - a differenza dell'approccio
        precedente (scegliere con cura una coppia di versioni "verificata sicura", poi
        reagire con un messaggio chiaro se scattava comunque), qui la connessione che avrebbe
        causato il conflitto viene fatta funzionare DAVVERO, nello stesso turno, senza
        richiedere un riavvio del server.

        REATTIVO, MAI PREEMPTIVO (stesso principio guida gia' fissato in questa sessione per
        il vecchio approccio a guardia, poi rimosso su richiesta esplicita dell'utente - "non
        voglio il safe guard"): questa funzione viene chiamata SOLO dal blocco catch di
        Connect-M365OpsExchange.ps1/Connect-M365OpsTeams.ps1/Connect-M365OpsCompliance.ps1,
        SOLO quando Get-M365OpsModuleConflictHint riconosce davvero il pattern del conflitto in
        un'eccezione REALE gia' avvenuta - mai eseguita in anticipo "per sicurezza". Un utente
        che usa un solo modulo per tutta la sessione non paga mai il costo di un secondo
        processo: l'isolamento non scatta mai per lui.

        App-only: l'autenticazione a certificato funziona transparentemente tra processi (il
        certificato vive nel certificate store dell'utente Windows, non nella memoria di un
        processo specifico - lo stesso identico certificato e' quindi accessibile anche dal
        processo worker).

        Delegato (27/08/2026, richiesto con massima priorita' dal vivo: conflitto reale
        Teams+Exchange poi Purview su un tenant Delegato - prima di questa data l'isolamento
        era disponibile solo per App-only): un token/sessione del processo principale non
        attraversa mai il confine di processo, quindi il worker rifa' un login interattivo
        TUTTO SUO (popup browser/WAM per Exchange+Purview+Teams, MAI device-code - vedi
        Get-M365OpsIsolatedConnectParams.ps1 .NOTES per il perche') la prima volta che serve
        per quel tenant in questo processo server - costo pagato una tantum per la vita del
        worker, non ripetuto per ogni comando successivo (stesso principio "paga una volta,
        poi silenzioso" gia' vero per l'isolamento App-only).
    .PARAMETER ModuleType
        'Exchange' o 'Teams'.
    .PARAMETER ConnectParams
        Hashtable passato cosi' com'e' al metodo "connect" del worker - vedi
        Get-M365OpsIsolatedConnectParams per come viene costruito dal contesto del tenant
        attivo.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType,
        [Parameter(Mandatory)] [hashtable]$ConnectParams,
        [switch]$Force
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    if (-not $script:M365OpsIsolatedWorkers) { $script:M365OpsIsolatedWorkers = @{} }
    if (-not $script:M365OpsIsolatedWorkers[$tenantName]) { $script:M365OpsIsolatedWorkers[$tenantName] = @{} }

    $existing = $script:M365OpsIsolatedWorkers[$tenantName][$ModuleType]
    if ($existing -and -not $existing.HasExited -and -not $Force) {
        # Gia' connesso per questo tenant - i proxy sono comunque gia' installati (evento
        # unico per processo server, non per tenant, vedi sotto), niente da rifare qui.
        return
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

    Write-M365OpsLog "Isolamento reattivo: avvio un processo separato per $ModuleType (tenant '$tenantName') dopo un conflitto .NET reale rilevato."
    $process = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Milliseconds 800
    if ($process.HasExited) {
        $err = $process.StandardError.ReadToEnd()
        throw "Il processo isolato per $ModuleType si e' chiuso subito dopo l'avvio (exit $($process.ExitCode)). Stderr: $err"
    }

    $script:M365OpsMcpRequestId = if ($script:M365OpsMcpRequestId) { $script:M365OpsMcpRequestId } else { 0 }

    try {
        # TimeoutSeconds: 60 di base (26/08/2026, non il default 30) - il worker puo'
        # impiegare piu' tempo del solito qui - Connect-ExchangeOnline + Connect-IPPSSession
        # (entrambi tentati per il modulo Exchange) PIU' l'attesa di stabilizzazione
        # dell'elenco comandi (verificato dal vivo che ExchangeOnlineManagement lo popola in
        # background dopo che Connect-ExchangeOnline e' gia' tornato, non subito). Su un
        # tenant Delegato (27/08/2026) sale a 240s: il worker apre un popup browser/WAM che
        # richiede un'azione umana (login/consenso), non un'attesa di solo calcolo - 60s
        # sarebbero quasi sempre troppo pochi e farebbero fallire un login che l'utente sta
        # ancora completando, uccidendo il processo worker proprio mentre il popup e' aperto.
        $isDelegatedIsolation = $script:M365OpsContext.AuthMode -eq 'Delegated'
        $connectTimeout = if ($isDelegatedIsolation) { 240 } else { 60 }
        $connectResult = Invoke-M365OpsMcpRequest -Process $process -Method "connect" -Params $ConnectParams -TimeoutSeconds $connectTimeout
    }
    catch {
        if (-not $process.HasExited) { $process.Kill() }
        throw "Connessione $ModuleType nel processo isolato fallita: $($_.Exception.Message)"
    }

    # Registrazione worker + generazione proxy: estratta il 23/08/2026 in
    # Complete-M365OpsIsolatedModuleConnect (Private), riusata TALE E QUALE dal nuovo percorso
    # asincrono (Start-/Get-M365OpsIsolatedModuleConnectAsync*, per i login bloccanti Teams
    # delegati - vedi quei file) - nessuna differenza di comportamento qui, solo deduplicazione.
    Complete-M365OpsIsolatedModuleConnect -TenantName $tenantName -ModuleType $ModuleType -Process $process -ConnectResult $connectResult
}
