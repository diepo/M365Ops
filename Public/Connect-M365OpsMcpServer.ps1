function Connect-M365OpsMcpServer {
    <#
    .SYNOPSIS
        Avvia (se non gia' attivo) un server MCP configurato per il tenant attivo come
        sottoprocesso locale e completa l'handshake MCP (initialize -> notifications/initialized
        -> tools/list). Generalizzazione di quello che prima era solo Connect-M365OpsLokka
        (26/08/2026, richiesto esplicitamente dall'utente per poter collegare un secondo
        server MCP, "CLI-Microsoft365", oltre a Lokka): lo stato non e' piu' in due variabili
        singolari ($script:M365OpsLokkaProcess/...LokkaTools, un solo server tracciabile alla
        volta) ma in due dizionari per nome ($script:M365OpsMcpProcesses/...McpTools), cosi'
        piu' server MCP possono restare connessi insieme nello stesso processo server.
        Connect-M365OpsLokka resta come alias sottile su questa funzione (-Name 'lokka') per
        non dover toccare tutto il codice esistente che la chiama gia'.

        Le credenziali passate al sottoprocesso dipendono dal server: 'lokka' riceve sempre
        client credentials (TENANT_ID/CLIENT_ID/CLIENT_SECRET, richiede AuthMode AppOnly).
        Altri server con un proprio modello di autenticazione (es. 'CLI-Microsoft365', che si
        autentica con un comando 'm365 login' separato, non con env var passate al processo)
        vengono sincronizzati con il tenant attivo chiamando una funzione dedicata subito dopo
        l'handshake - vedi Connect-M365OpsCliMicrosoft365.ps1.
    .PARAMETER Name
        Nome del server MCP, come appare in Get-M365OpsMcpServers (es. 'lokka',
        'CLI-Microsoft365' - case-insensitive, stessa semantica delle chiavi hashtable di
        PowerShell).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [switch]$Force
    )

    if (-not $script:M365OpsMcpProcesses) { $script:M365OpsMcpProcesses = @{} }
    if (-not $script:M365OpsMcpTools) { $script:M365OpsMcpTools = @{} }

    $existing = $script:M365OpsMcpProcesses[$Name]
    if ($existing -and -not $existing.HasExited -and -not $Force) {
        return $script:M365OpsMcpTools[$Name]
    }

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    $serverConfig = Get-M365OpsMcpServers | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $serverConfig) { throw "Server MCP '$Name' non configurato per questo tenant (tab MCP/Connettori)." }

    $commandName = $serverConfig.Command
    $commandArgs = $serverConfig.Args

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
            throw "Il tenant '$($script:M365OpsContext.Name)' e' in modalita' Delegated: Lokka richiede client credentials (client secret) e non e' disponibile per questo profilo. L'AI usera' solo le cmdlet dirette del modulo."
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

    $script:M365OpsMcpProcesses[$Name] = $process
    $script:M365OpsMcpTools[$Name] = $toolsResult.tools

    # Server con un modello di autenticazione proprio, separato dalle env var passate al
    # sottoprocesso sopra (vedi .SYNOPSIS) - sincronizzato SOLO ora che il processo e' su e
    # risponde, mai prima (un login su un processo che potrebbe non partire sarebbe uno
    # sforzo sprecato, oltre a lasciare un login orfano se l'handshake fallisce).
    if ($Name -eq 'CLI-Microsoft365') {
        try { Connect-M365OpsCliMicrosoft365 }
        catch {
            if (-not $process.HasExited) { $process.Kill() }
            $script:M365OpsMcpProcesses.Remove($Name)
            $script:M365OpsMcpTools.Remove($Name)
            throw
        }
    }

    Write-Host "Server MCP '$Name' connesso. Tool disponibili: $(($toolsResult.tools | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor Green
    return $toolsResult.tools
}
