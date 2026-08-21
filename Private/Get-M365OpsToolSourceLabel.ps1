function Get-M365OpsToolSourceLabel {
    <#
    .SYNOPSIS
        Data il nome di un tool AI (vedi Invoke-M365OpsAgentTools.ps1), restituisce
        un'etichetta leggibile della SORGENTE reale dei dati/dell'azione - Lokka (MCP), CLI
        Microsoft 365 (MCP), Microsoft Graph diretto (tenant Delegato, nessun sottoprocesso
        MCP coinvolto), o i moduli PowerShell interni di questo progetto (Exchange/
        SharePoint/Teams/Intune/script personalizzati). Richiesto esplicitamente dall'utente
        il 26/08/2026: sapere SEMPRE quale backend ha risposto, sia nella risposta mostrata
        in chat sia nei log - prima l'unica traccia era il nome tecnico del tool
        (es. "graph_api_call"), che non dice da solo se e' passato da Lokka o da una
        chiamata diretta.
    .PARAMETER ToolName
        Nome del tool cosi' come appare nel dispatch (es. "graph_api_call", "exo_query").
    .PARAMETER IsDelegatedTenant
        Necessario SOLO per graph_api_call/propose_graph_write: su un tenant Delegato quei
        due tool non passano MAI da Lokka (che richiede client credentials) ma da una
        chiamata Graph diretta con lo stesso token delegato del resto del modulo - stessa
        etichetta "Lokka" sarebbe fuorviante in quel caso.
    #>
    param(
        [Parameter(Mandatory)] [string]$ToolName,
        [bool]$IsDelegatedTenant = $false
    )

    switch -Regex ($ToolName) {
        '^(graph_api_call|propose_graph_write)$' {
            if ($IsDelegatedTenant) { return 'Microsoft Graph diretto (token delegato, nessun MCP)' }
            return 'Lokka (MCP)'
        }
        '^cli_m365_|^propose_cli_m365_command$' { return 'CLI Microsoft 365 (MCP)' }
        default { return 'moduli PowerShell interni di M365Ops' }
    }
}
