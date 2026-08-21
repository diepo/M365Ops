function Get-M365OpsActiveTenantInfo {
    <#
    .SYNOPSIS
        Restituisce le informazioni non sensibili del tenant attivo (mai il secret).
        Serve per esporre lo stato al livello GUI senza toccare lo scope interno del modulo.
    #>
    if (-not $script:M365OpsContext) { return $null }
    $delegatedSession = $script:M365OpsTokenCache[$script:M365OpsContext.Name].Delegated
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
        LokkaConnected         = [bool]($script:M365OpsLokkaProcess -and -not $script:M365OpsLokkaProcess.HasExited)
        LokkaToolCount         = if ($script:M365OpsLokkaTools) { @($script:M365OpsLokkaTools).Count } else { 0 }
    }
}
