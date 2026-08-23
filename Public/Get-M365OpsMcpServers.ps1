function Get-M365OpsMcpServers {
    <#
    .SYNOPSIS
        Elenca i server MCP configurati per il TENANT ATTIVO (sotto-sezione McpServers
        del profilo in Config\tenants.json - connettori/credenziali diversi possono servire
        a tenant diversi). "lokka" e "CLI-Microsoft365" sono sempre presenti con valori di
        default se non personalizzati per questo tenant - nessuna configurazione manuale
        richiesta per usarli su un tenant nuovo.
    .NOTES
        CLI-Microsoft365 aggiunto ai default built-in il 23/08/2026 (richiesto esplicitamente
        dal vivo: un nuovo profilo tenant, "AlePiras", falliva con "Server MCP
        'CLI-Microsoft365' non configurato per questo tenant" - l'utente si aspettava che
        ogni tenant arrivasse gia' con questo connettore pronto, come gia' avviene per lokka,
        non che andasse aggiunto a mano da "Altri server MCP" per ciascun profilo). Stesso
        meccanismo di override gia' valido per lokka: un tenant che ha una propria voce
        "CLI-Microsoft365" in McpServers (es. per puntare a una versione fissata invece di
        @latest) continua a vincere sul default, il dizionario sotto imposta solo il valore
        USATO SE NON gia' presente per quel tenant.
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
        lokka              = @{ command = "npx"; args = "-y @merill/lokka"; envMapping = "tenant"; builtIn = $true }
        'CLI-Microsoft365' = @{ command = "npx"; args = "-y @pnp/cli-microsoft365-mcp-server@latest"; envMapping = "none"; builtIn = $true }
    }

    $builtInNames = @('lokka', 'CLI-Microsoft365')
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
                    builtIn    = ($prop.Name -in $builtInNames)
                }
            }
        }
    }

    $servers.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; Command = $_.Value.command; Args = $_.Value.args; EnvMapping = $_.Value.envMapping; BuiltIn = $_.Value.builtIn }
    }
}
