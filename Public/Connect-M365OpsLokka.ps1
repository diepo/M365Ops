function Connect-M365OpsLokka {
    <#
    .SYNOPSIS
        Avvia (se non gia' attivo) il server MCP Lokka (github.com/merill/lokka) come
        sottoprocesso locale e completa l'handshake MCP. Riusa le credenziali del tenant
        attivo (client credentials - stesse dell'App Registration gia' configurata).
        Richiede Node.js (npx).

    .EXAMPLE
        Connect-M365OpsLokka   # restituisce l'elenco di tool esposti da Lokka
    #>
    param([switch]$Force)

    if ($script:M365OpsLokkaProcess -and -not $script:M365OpsLokkaProcess.HasExited -and -not $Force) {
        return $script:M365OpsLokkaTools
    }

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        throw "Il tenant '$($script:M365OpsContext.Name)' e' in modalita' Delegated: Lokka richiede client credentials (client secret) e non e' disponibile per questo profilo. L'AI usera' solo le cmdlet dirette del modulo (graph_api_call/propose_graph_write non offerti per questo tenant)."
    }
    $secret = Get-M365OpsSecret -Name $script:M365OpsContext.SecretEnvVar
    if (-not $secret) { throw "Secret del tenant ('$($script:M365OpsContext.SecretEnvVar)') non trovato." }

    # Comando e argomenti letti dalla configurazione (Config\mcp-servers.json) invece che
    # fissi nel codice - modificabili dal tab MCP/Connettori della GUI.
    $serverConfig = Get-M365OpsMcpServers | Where-Object { $_.Name -eq 'lokka' } | Select-Object -First 1
    $commandName = if ($serverConfig) { $serverConfig.Command } else { 'npx' }
    $commandArgs = if ($serverConfig) { $serverConfig.Args } else { '-y @merill/lokka' }

    $resolvedCommand = (Get-Command "$commandName.cmd" -ErrorAction SilentlyContinue).Source
    if (-not $resolvedCommand) { $resolvedCommand = (Get-Command $commandName -ErrorAction SilentlyContinue).Source }
    if (-not $resolvedCommand) { throw "Comando '$commandName' non trovato." }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedCommand
    $psi.Arguments = $commandArgs
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["TENANT_ID"] = $script:M365OpsContext.TenantId
    $psi.EnvironmentVariables["CLIENT_ID"] = $script:M365OpsContext.ClientId
    $psi.EnvironmentVariables["CLIENT_SECRET"] = $secret

    $process = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Seconds 2
    if ($process.HasExited) {
        $err = $process.StandardError.ReadToEnd()
        throw "Lokka si e' chiuso subito dopo l'avvio (exit $($process.ExitCode)). Stderr: $err"
    }

    $script:M365OpsMcpRequestId = 0

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

    $script:M365OpsLokkaProcess = $process
    $script:M365OpsLokkaTools = $toolsResult.tools

    Write-Host "Lokka connesso. Tool disponibili: $(($script:M365OpsLokkaTools | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor Green
    return $script:M365OpsLokkaTools
}
