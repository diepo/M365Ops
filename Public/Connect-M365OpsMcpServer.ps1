function Connect-M365OpsMcpServer {
    <#
    .SYNOPSIS
        Avvia (se non gia' attivo PER QUESTO TENANT) un server MCP configurato come
        sottoprocesso locale e completa l'handshake MCP (initialize -> notifications/initialized
        -> tools/list). Generalizzazione di quello che prima era solo Connect-M365OpsLokka
        (26/08/2026, richiesto esplicitamente dall'utente per poter collegare un secondo
        server MCP, "CLI-Microsoft365", oltre a Lokka) - Connect-M365OpsLokka resta come alias
        sottile su questa funzione (-Name 'lokka') per non dover toccare tutto il codice
        esistente che la chiama gia'.

        ISOLAMENTO PER TENANT (26/08/2026, richiesto esplicitamente dall'utente: "rendi ogni
        processo MCP isolato da altri tenant"): lo stato non e' un dizionario per nome server
        (un solo processo per server, condiviso tra tutti i tenant) ma un dizionario A DUE
        LIVELLI - $script:M365OpsMcpProcesses[$TenantName][$ServerName] - un sottoprocesso
        DISTINTO per ogni coppia tenant+server, mai condiviso. Cambiare tenant NON termina piu'
        i processi del tenant precedente (comportamento fino a v0.9.57): restano vivi in
        background, cosi' tornare su un tenant gia' usato in questa sessione riattiva
        l'istanza gia' pronta invece di rifare login/handshake da capo. L'isolamento e'
        strutturale (processi OS separati, mai la stessa istanza per due tenant) - per
        CLI-Microsoft365 in particolare, che si autentica tramite un file di configurazione
        CONDIVISO per l'intero utente Windows (m365 login/connection use, non env var passate
        al processo come Lokka), questo da solo NON basta a garantire che un comando su un
        processo non venga eseguito con l'identita' sbagliata se un ALTRO processo (di un
        altro tenant) ha nel frattempo cambiato la connessione "attiva" in quel file condiviso
        - vedi Invoke-M365OpsMcpServerTool.ps1, che riafferma sempre la connessione giusta
        immediatamente prima di ogni comando reale per questo motivo, invece di fidarsi che un
        singolo "connection use" fatto una volta sola al login resti valido per tutta la vita
        del processo.

        Le credenziali passate al sottoprocesso dipendono dal server: 'lokka' riceve sempre
        client credentials (TENANT_ID/CLIENT_ID/CLIENT_SECRET, richiede AuthMode AppOnly) -
        gia' isolato per costruzione anche prima di questo fix, dato che le credenziali sono
        cablate nel processo stesso al momento dello spawn, mai condivise con altri tenant.
        Altri server con un proprio modello di autenticazione (es. 'CLI-Microsoft365')
        vengono sincronizzati con il tenant attivo chiamando una funzione dedicata subito dopo
        l'handshake - vedi Connect-M365OpsCliMicrosoft365.ps1.
    .PARAMETER Name
        Nome del server MCP, come appare in Get-M365OpsMcpServers (es. 'lokka',
        'CLI-Microsoft365' - case-insensitive, stessa semantica delle chiavi hashtable di
        PowerShell).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [switch]$Force,
        # Passato SOLO a Connect-M365OpsCliMicrosoft365 (server con un proprio login, vedi
        # sopra) - su tenant Delegato quella funzione richiede un login a browser BLOCCANTE,
        # concesso solo dietro questo switch esplicito, mai in un flusso composto automatico.
        [switch]$AllowInteractive
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    if (-not $script:M365OpsMcpProcesses) { $script:M365OpsMcpProcesses = @{} }
    if (-not $script:M365OpsMcpTools) { $script:M365OpsMcpTools = @{} }
    if (-not $script:M365OpsMcpProcesses[$tenantName]) { $script:M365OpsMcpProcesses[$tenantName] = @{} }
    if (-not $script:M365OpsMcpTools[$tenantName]) { $script:M365OpsMcpTools[$tenantName] = @{} }

    $existing = $script:M365OpsMcpProcesses[$tenantName][$Name]
    if ($existing -and -not $existing.HasExited -and -not $Force) {
        return $script:M365OpsMcpTools[$tenantName][$Name]
    }

    $serverConfig = Get-M365OpsMcpServers | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $serverConfig) { throw "Server MCP '$Name' non configurato per questo tenant (tab Tenant, sezione Stato connessioni)." }

    $commandName = $serverConfig.Command
    $commandArgs = $serverConfig.Args

    # Assert-M365OpsCliMicrosoft365Installed (Private, 26/08/2026): il server MCP
    # CLI-Microsoft365 e' solo un wrapper sottile che invoca il comando 'm365' esterno GIA'
    # installato - a differenza di Lokka (npx -y lo scarica ed esegue al volo, nessuna
    # installazione globale necessaria), qui npx scarica solo il WRAPPER, non anche la CLI
    # vera. Chiamata PRIMA di spawnare il processo (fallisce/installa subito, invece di far
    # partire un npx cold-start inutile solo per scoprire poi che manca un prerequisito) -
    # stesso principio di Assert-M365OpsExoSafeVersion prima di Import-Module.
    if ($Name -eq 'CLI-Microsoft365') { Assert-M365OpsCliMicrosoft365Installed }

    $resolvedCommand = (Get-Command "$commandName.cmd" -ErrorAction SilentlyContinue).Source
    if (-not $resolvedCommand) { $resolvedCommand = (Get-Command $commandName -ErrorAction SilentlyContinue).Source }
    if (-not $resolvedCommand) { throw "Comando '$commandName' non trovato (server MCP '$Name') - verifica che sia installato e nel PATH di questo PC." }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedCommand
    $psi.Arguments = $commandArgs
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    if ($Name -eq 'lokka') {
        if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
            throw "Il tenant '$tenantName' e' in modalita' Delegated: Lokka richiede client credentials (client secret) e non e' disponibile per questo profilo. L'AI usera' solo le cmdlet dirette del modulo."
        }
        $secret = Get-M365OpsSecret -Name $script:M365OpsContext.SecretEnvVar
        if (-not $secret) { throw "Secret del tenant ('$($script:M365OpsContext.SecretEnvVar)') non trovato." }
        $psi.EnvironmentVariables["TENANT_ID"] = $script:M365OpsContext.TenantId
        $psi.EnvironmentVariables["CLIENT_ID"] = $script:M365OpsContext.ClientId
        $psi.EnvironmentVariables["CLIENT_SECRET"] = $secret
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Seconds 2
    if ($process.HasExited) {
        $err = $process.StandardError.ReadToEnd()
        throw "Server MCP '$Name' si e' chiuso subito dopo l'avvio (exit $($process.ExitCode)). Stderr: $err"
    }

    try {
        Invoke-M365OpsMcpRequest -Process $process -Method "initialize" -Params @{
            protocolVersion = "2024-11-05"
            capabilities    = @{}
            clientInfo      = @{ name = "M365Ops"; version = "0.1.0" }
        } | Out-Null

        Invoke-M365OpsMcpRequest -Process $process -Method "notifications/initialized" -Notification | Out-Null

        $toolsResult = Invoke-M365OpsMcpRequest -Process $process -Method "tools/list"
    }
    catch {
        if (-not $process.HasExited) { $process.Kill() }
        throw
    }

    $script:M365OpsMcpProcesses[$tenantName][$Name] = $process
    $script:M365OpsMcpTools[$tenantName][$Name] = $toolsResult.tools

    # Server con un modello di autenticazione proprio, separato dalle env var passate al
    # sottoprocesso sopra (vedi .SYNOPSIS) - sincronizzato SOLO ora che il processo e' su e
    # risponde, mai prima (un login su un processo che potrebbe non partire sarebbe uno
    # sforzo sprecato, oltre a lasciare un login orfano se l'handshake fallisce).
    if ($Name -eq 'CLI-Microsoft365') {
        try { Connect-M365OpsCliMicrosoft365 -AllowInteractive:$AllowInteractive }
        catch {
            if (-not $process.HasExited) { $process.Kill() }
            $script:M365OpsMcpProcesses[$tenantName].Remove($Name)
            $script:M365OpsMcpTools[$tenantName].Remove($Name)
            throw
        }
    }

    Write-Host "Server MCP '$Name' connesso per il tenant '$tenantName'. Tool disponibili: $(($toolsResult.tools | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor Green
    return $toolsResult.tools
}
