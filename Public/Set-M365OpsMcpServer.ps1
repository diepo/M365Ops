function Set-M365OpsMcpServer {
    <#
    .SYNOPSIS
        Registra o aggiorna un server MCP dentro la sotto-sezione McpServers del profilo
        TENANT ATTIVO in Config\tenants.json - cosi' tenant diversi possono avere connettori
        e credenziali diverse in parallelo, invece di condividere un'unica configurazione globale.

    .EXAMPLE
        Set-M365OpsMcpServer -Name "lokka" -Command "npx" -Args "-y @merill/lokka"
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string]$Args,
        [string]$EnvMapping = "none"
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $activeName = $script:M365OpsContext.Name

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    $config = @{}
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            $mcpServers = @{}
            if ($prop.Value.McpServers) {
                foreach ($mcpProp in $prop.Value.McpServers.PSObject.Properties) {
                    $mcpServers[$mcpProp.Name] = @{ command = $mcpProp.Value.command; args = $mcpProp.Value.args; envMapping = $mcpProp.Value.envMapping }
                }
            }
            $config[$prop.Name] = @{
                TenantId               = $prop.Value.TenantId
                ClientId               = $prop.Value.ClientId
                SecretEnvVar           = $prop.Value.SecretEnvVar
                AuthMode               = if ($prop.Value.AuthMode) { $prop.Value.AuthMode } else { 'AppOnly' }
                DelegatedUpn           = $prop.Value.DelegatedUpn
                ExchangeCertThumbprint = $prop.Value.ExchangeCertThumbprint
                EmailSender            = $prop.Value.EmailSender
                McpServers             = $mcpServers
            }
        }
    }

    if (-not $config.ContainsKey($activeName)) { throw "Profilo tenant '$activeName' non trovato in tenants.json." }
    if (-not $config[$activeName].McpServers) { $config[$activeName].McpServers = @{} }
    $config[$activeName].McpServers[$Name] = @{ command = $Command; args = $Args; envMapping = $EnvMapping }

    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
}
