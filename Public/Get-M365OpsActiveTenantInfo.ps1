function Get-M365OpsActiveTenantInfo {
    <#
    .SYNOPSIS
        Restituisce le informazioni non sensibili del tenant attivo (mai il secret).
        Serve per esporre lo stato al livello GUI senza toccare lo scope interno del modulo.
    #>
    if (-not $script:M365OpsContext) { return $null }
    $delegatedSession = $script:M365OpsTokenCache[$script:M365OpsContext.Name].Delegated

    # 26/08/2026: Lokka non e' piu' tracciato in variabili singolari
    # ($script:M365OpsLokkaProcess/...LokkaTools) ma in due dizionari per nome
    # ($script:M365OpsMcpProcesses/...McpTools), per poter tracciare piu' server MCP insieme
    # (vedi Connect-M365OpsMcpServer.ps1) - LokkaConnected/LokkaToolCount restano per
    # compatibilita' con la GUI esistente, derivati dalla voce 'lokka' del dizionario.
    # McpServerStatus e' il nuovo campo generico: un oggetto per OGNI server MCP configurato
    # per questo tenant (non solo quelli gia' connessi), cosi' la GUI puo' mostrare anche un
    # server mai avviato in questa sessione come "non connesso" invece di ometterlo del tutto.
    $lokkaProcess = if ($script:M365OpsMcpProcesses) { $script:M365OpsMcpProcesses['lokka'] } else { $null }
    $lokkaTools = if ($script:M365OpsMcpTools) { $script:M365OpsMcpTools['lokka'] } else { $null }
    $mcpServerStatus = @()
    try {
        foreach ($server in @(Get-M365OpsMcpServers)) {
            $proc = if ($script:M365OpsMcpProcesses) { $script:M365OpsMcpProcesses[$server.Name] } else { $null }
            $tools = if ($script:M365OpsMcpTools) { $script:M365OpsMcpTools[$server.Name] } else { $null }
            $mcpServerStatus += [pscustomobject]@{
                Name      = $server.Name
                BuiltIn   = $server.BuiltIn
                Connected = [bool]($proc -and -not $proc.HasExited)
                ToolCount = if ($tools) { @($tools).Count } else { 0 }
            }
        }
    } catch { }

    [pscustomobject]@{
        Name                   = $script:M365OpsContext.Name
        TenantId               = $script:M365OpsContext.TenantId
        ClientId               = $script:M365OpsContext.ClientId
        SecretEnvVar           = $script:M365OpsContext.SecretEnvVar
        AuthMode               = if ($script:M365OpsContext.AuthMode) { $script:M365OpsContext.AuthMode } else { 'AppOnly' }
        DelegatedUpn           = $script:M365OpsContext.DelegatedUpn
        DelegatedSessionActive = [bool]($delegatedSession -and $delegatedSession.ExpiresAt -gt (Get-Date))
        ExchangeCertThumbprint = $script:M365OpsContext.ExchangeCertThumbprint
        EmailSender            = $script:M365OpsContext.EmailSender
        ExchangeConnected      = [bool]$script:M365OpsExchangeConnected
        SharePointConnected    = [bool]$script:M365OpsSharePointConnectedUrl
        SharePointConnectedUrl = $script:M365OpsSharePointConnectedUrl
        SharePointInteractiveClientId = $script:M365OpsContext.SharePointInteractiveClientId
        TeamsConnected         = [bool]$script:M365OpsTeamsConnected
        ComplianceConnected    = [bool]$script:M365OpsComplianceConnected
        IntuneConnected        = [bool]$script:M365OpsIntuneConnected
        IntuneConnectedUpn     = $script:M365OpsIntuneConnectedAs.Upn
        IntuneConnectedTenant  = $script:M365OpsIntuneConnectedAs.TenantName
        LokkaConnected         = [bool]($lokkaProcess -and -not $lokkaProcess.HasExited)
        LokkaToolCount         = if ($lokkaTools) { @($lokkaTools).Count } else { 0 }
        McpServerStatus        = $mcpServerStatus
    }
}
