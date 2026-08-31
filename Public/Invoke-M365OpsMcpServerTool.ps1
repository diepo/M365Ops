function Invoke-M365OpsMcpServerTool {
    <#
    .SYNOPSIS
        Chiama un tool esposto da un server MCP configurato (vedi Connect-M365OpsMcpServer
        per l'elenco tool). Avvia il server automaticamente se non e' gia' attivo PER IL
        TENANT ATTIVO. Generalizzazione di Invoke-M365OpsLokkaTool (26/08/2026) - vedi
        Connect-M365OpsMcpServer.ps1 per il perche' dell'isolamento per tenant.

        RIAFFERMAZIONE DIFENSIVA per CLI-Microsoft365 (26/08/2026, richiesto esplicitamente
        dall'utente: "rendi ogni processo MCP isolato da altri tenant, ragionaci bene"):
        verificato dal vivo (26/08/2026) che l'identita' "attiva" di CLI Microsoft 365 vive in
        un file di configurazione CONDIVISO per l'intero utente Windows (non nella memoria del
        singolo processo Node.js) - un processo isolato per tenant (vedi
        Connect-M365OpsMcpServer.ps1) impedisce che due tenant condividano lo STESSO processo,
        ma NON e' stato possibile verificare con certezza dalla sola documentazione se
        'm365 status'/altri comandi rileggano quell'identita' dal file condiviso ad ogni
        chiamata (vulnerabile se un ALTRO processo, di un altro tenant, ha nel frattempo
        cambiato la connessione attiva in quel file) oppure la mettano in cache in memoria al
        momento del login/'connection use' (sicuro per costruzione). Per non dipendere da un
        comportamento interno non verificabile con certezza su un'operazione che tocca dati
        reali di un tenant, ogni comando REALE (mai le sole chiamate di ricerca/documentazione,
        che non toccano dati di un tenant specifico) e' preceduto da un 'connection use'
        esplicito sullo STESSO processo, immediatamente prima - un costo minimo (comando CLI
        locale, nessuna chiamata di rete) per una garanzia di correttezza che non dipende da
        assunzioni sul comportamento interno del pacchetto.
    #>
    param(
        [Parameter(Mandatory)] [string]$ServerName,
        [Parameter(Mandatory)] [string]$ToolName,
        [hashtable]$Arguments = @{}
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $needsConnect = $true
    if ($script:M365OpsMcpProcesses -and $script:M365OpsMcpProcesses[$tenantName] -and $script:M365OpsMcpProcesses[$tenantName][$ServerName]) {
        $needsConnect = $script:M365OpsMcpProcesses[$tenantName][$ServerName].HasExited
    }
    $script:M365OpsCliJustInstalled = $false
    if ($needsConnect) { Connect-M365OpsMcpServer -Name $ServerName | Out-Null }
    # Visibilita' sull'auto-installazione silenziosa di CLI Microsoft 365 (31/08/2026,
    # richiesta esplicitamente dall'utente dopo averla vista scattare senza preavviso durante
    # un test IA - vedi Assert-M365OpsCliMicrosoft365Installed.ps1 per il dettaglio completo).
    # L'installazione stessa resta invariata (comportamento gia' richiesto in precedenza), solo
    # resa visibile: se e' appena scattata un vero "npm install -g" (non solo una connessione
    # a un server gia' pronto), lo anteponiamo al risultato del tool - l'UNICO punto in cui
    # questo turno di conversazione puo' ancora spiegare all'utente, dentro la risposta finale,
    # perche' e' stato piu' lento del solito, invece di scoprirlo solo nei log del server.
    $cliInstallNote = ""
    if ($ServerName -eq 'CLI-Microsoft365' -and $script:M365OpsCliJustInstalled) {
        $cliInstallNote = "[Nota: CLI Microsoft 365 non era ancora installata su questo PC - installata ora automaticamente (npm install -g, ~1-2 minuti), la prima volta soltanto. Le richieste successive non ne risentiranno piu'.]`n`n"
    }

    $process = $script:M365OpsMcpProcesses[$tenantName][$ServerName]

    # Riafferma la connessione CLI-Microsoft365 giusta PRIMA di ogni comando reale (vedi
    # .SYNOPSIS) - solo per m365_run_command con un comando che non e' 'connection'/'login'
    # esso stesso (evita un giro a vuoto sui comandi di ricerca/documentazione, che sono
    # SOLA LETTURA della documentazione del pacchetto stesso, non toccano mai dati del
    # tenant, e su 'login'/'connection use' stessi, gia' gestiti esplicitamente da
    # Connect-M365OpsCliMicrosoft365.ps1).
    if ($ServerName -eq 'CLI-Microsoft365' -and $ToolName -eq 'm365_run_command' -and $Arguments.command -notmatch '^\s*m365\s+(login|connection)\b') {
        Invoke-M365OpsMcpRequest -Process $process -Method "tools/call" -Params @{
            name      = "m365_run_command"
            arguments = @{ command = "m365 connection use --name `"$tenantName`"" }
        } | Out-Null
    }

    $toolResult = Invoke-M365OpsMcpRequest -Process $process -Method "tools/call" -Params @{
        name      = $ToolName
        arguments = $Arguments
    }
    if ($cliInstallNote -and $toolResult.content -and $toolResult.content.Count -gt 0) {
        $toolResult.content[0].text = $cliInstallNote + $toolResult.content[0].text
    }
    $toolResult
}
