function Get-M365OpsMcpServers {
    <#
    .SYNOPSIS
        Elenca i server MCP configurati per il TENANT ATTIVO (sotto-sezione McpServers
        del profilo in Config\tenants.json - connettori/credenziali diversi possono servire
        a tenant diversi). "lokka" e' sempre presente con valori di default se non
        personalizzato per questo tenant.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    $servers = @{
        lokka = @{ command = "npx"; args = "-y @merill/lokka"; envMapping = "tenant"; builtIn = $true }
    }

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw | ConvertFrom-Json
        $entry = $raw.($script:M365OpsContext.Name)
        if ($entry -and $entry.McpServers) {
            foreach ($prop in $entry.McpServers.PSObject.Properties) {
                $servers[$prop.Name] = @{
                    command    = $prop.Value.command
                    args       = $prop.Value.args
                    envMapping = $prop.Value.envMapping
                    builtIn    = ($prop.Name -eq 'lokka')
                }
            }
        }
    }

    $servers.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; Command = $_.Value.command; Args = $_.Value.args; EnvMapping = $_.Value.envMapping; BuiltIn = $_.Value.builtIn }
    }
}
