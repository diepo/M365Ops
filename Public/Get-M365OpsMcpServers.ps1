function Get-M365OpsMcpServers {
    <#
    .SYNOPSIS
        Elenca i server MCP configurati per il TENANT ATTIVO (sotto-sezione McpServers
        del profilo in Config\tenants.json - connettori/credenziali diversi possono servire
        a tenant diversi). "lokka" e' sempre presente con valori di default se non
        personalizzato per questo tenant.
    #>
    # Bug reale segnalato dal vivo il 26/08/2026 (screenshot dell'utente: banner "Nessun
    # tenant attivo" in alto, MA tab MCP/Connettori mostrava "Errore nel caricare i server
    # MCP" invece di degradare come fanno tutte le altre sezioni della GUI in questo stato):
    # questa funzione lanciava un'eccezione quando nessun tenant e' attivo, e il gestore
    # "GET /api/mcp-servers" in Gui\Server.ps1 non aveva un try/catch proprio - l'eccezione
    # arrivava quindi al gestore d'errore generico (risposta 500 con {role;text}, non un
    # array), che il JS della GUI (servers.find/.filter) non sa interpretare, finendo nel
    # catch generico "Errore nel caricare i server MCP". Nessun altro chiamante di questa
    # funzione dipende dal throw (Connect-M365OpsMcpServer controlla il contesto PRIMA di
    # chiamarla; gli altri due punti la avvolgono gia' in try/catch) - restituire un elenco
    # vuoto invece di lanciare e' quindi sicuro ovunque e coerente con Get-M365OpsTenantList,
    # che gia' fa lo stesso quando non c'e' nessun profilo salvato.
    if (-not $script:M365OpsContext) { return @() }

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
