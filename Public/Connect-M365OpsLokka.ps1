function Connect-M365OpsLokka {
    <#
    .SYNOPSIS
        Avvia (se non gia' attivo) il server MCP Lokka (github.com/merill/lokka) come
        sottoprocesso locale e completa l'handshake MCP. Riusa le credenziali del tenant
        attivo (client credentials - stesse dell'App Registration gia' configurata).
        Richiede Node.js (npx).

        Alias sottile su Connect-M365OpsMcpServer -Name 'lokka' (26/08/2026) - la logica vera
        e' generica, per poter collegare anche altri server MCP oltre a Lokka (vedi
        Connect-M365OpsMcpServer.ps1). Mantenuta come funzione a se' per non dover toccare
        tutto il codice esistente che chiama gia' Connect-M365OpsLokka.

    .EXAMPLE
        Connect-M365OpsLokka   # restituisce l'elenco di tool esposti da Lokka
    #>
    param([switch]$Force)
    Connect-M365OpsMcpServer -Name 'lokka' -Force:$Force
}
