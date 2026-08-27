function Get-M365OpsActiveTenantInfo {
    <#
    .SYNOPSIS
        Restituisce le informazioni non sensibili del tenant attivo (mai il secret).
        Serve per esporre lo stato al livello GUI senza toccare lo scope interno del modulo.
    #>
    if (-not $script:M365OpsContext) { return $null }
    $delegatedSession = $script:M365OpsTokenCache[$script:M365OpsContext.Name].Delegated
    # AppOnlyTokenCached (27/08/2026, per il pulsante "Disconnetti/Connetti tutto"): a
    # differenza di ExchangeConnected/TeamsConnected/ecc., prima d'ora non esisteva NESSUN modo
    # per la GUI di sapere se esiste gia' un token Graph app-only diretto in cache per questo
    # tenant (usato da Invoke-M365OpsGraphRequest -> Get-M365OpsToken, quindi da Intune/Copilot/
    # ogni cmdlet Public\* che legge Graph) - senza questo campo, disconnettere SOLO quel token
    # (senza toccare Exchange/Teams/ecc.) sarebbe rimasto invisibile nello stato "connesso".
    # Per AppOnly la cache e' un oggetto piatto {AccessToken;ExpiresAt} (vedi Get-M365OpsToken.ps1);
    # .Delegated esiste solo per i tenant Delegated, quindi il controllo su .AccessToken basta a
    # non confondere le due forme.
    $appOnlyTokenCached = [bool]($script:M365OpsContext.AuthMode -ne 'Delegated' -and $script:M365OpsTokenCache[$script:M365OpsContext.Name].AccessToken)

    # 26/08/2026: i server MCP sono tracciati in dizionari a DUE livelli, per tenant poi per
    # nome server ($script:M365OpsMcpProcesses[$TenantName][$ServerName]/...McpTools), non
    # piu' un solo livello per nome condiviso tra tutti i tenant - vedi
    # Connect-M365OpsMcpServer.ps1 per il perche' (isolamento per tenant: un processo OS
    # distinto per ogni coppia tenant+server, mai condiviso). LokkaConnected/LokkaToolCount
    # restano per compatibilita' con la GUI esistente, derivati dalla voce 'lokka' del
    # dizionario per IL TENANT ATTIVO. McpServerStatus e' il campo generico: un oggetto per
    # OGNI server MCP configurato per questo tenant (non solo quelli gia' connessi), cosi' la
    # GUI puo' mostrare anche un server mai avviato in questa sessione come "non connesso"
    # invece di ometterlo del tutto.
    $tenantMcpProcesses = if ($script:M365OpsMcpProcesses) { $script:M365OpsMcpProcesses[$script:M365OpsContext.Name] } else { $null }
    $tenantMcpTools = if ($script:M365OpsMcpTools) { $script:M365OpsMcpTools[$script:M365OpsContext.Name] } else { $null }
    $lokkaProcess = if ($tenantMcpProcesses) { $tenantMcpProcesses['lokka'] } else { $null }
    $lokkaTools = if ($tenantMcpTools) { $tenantMcpTools['lokka'] } else { $null }
    $mcpServerStatus = @()
    try {
        foreach ($server in @(Get-M365OpsMcpServers)) {
            $proc = if ($tenantMcpProcesses) { $tenantMcpProcesses[$server.Name] } else { $null }
            $tools = if ($tenantMcpTools) { $tenantMcpTools[$server.Name] } else { $null }
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
        AppOnlyTokenCached     = $appOnlyTokenCached
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
