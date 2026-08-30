function Remove-M365OpsMcpServer {
    <#
    .SYNOPSIS
        Rimuove un server MCP dalla sotto-sezione McpServers del profilo TENANT ATTIVO.
        Rimuovere "lokka" ripristina semplicemente i valori di default (npx -y @merill/lokka)
        invece di disabilitarlo, dato che Lokka e' sempre presente come builtIn - vedi
        Get-M365OpsMcpServers.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name
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
                # Stesso bug reale di Set-M365OpsMcpServer.ps1 (31/08/2026) - vedi li' per il
                # dettaglio completo.
                SharePointInteractiveClientId = $prop.Value.SharePointInteractiveClientId
                McpServers              = $mcpServers
            }
        }
    }

    if (-not $config.ContainsKey($activeName)) { throw "Profilo tenant '$activeName' non trovato in tenants.json." }
    if (-not $config[$activeName].McpServers -or -not $config[$activeName].McpServers.ContainsKey($Name)) {
        throw "Server MCP '$Name' non configurato per il tenant '$activeName' - niente da rimuovere."
    }
    $config[$activeName].McpServers.Remove($Name)

    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
    Write-Host "Server MCP '$Name' rimosso dal profilo '$activeName'." -ForegroundColor Green
}
