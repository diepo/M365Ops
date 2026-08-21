function Invoke-M365OpsMcpServerTool {
    <#
    .SYNOPSIS
        Chiama un tool esposto da un server MCP configurato (vedi Connect-M365OpsMcpServer
        per l'elenco tool). Avvia il server automaticamente se non e' gia' attivo.
        Generalizzazione di Invoke-M365OpsLokkaTool (26/08/2026) - vedi
        Connect-M365OpsMcpServer.ps1 per il perche'.
    #>
    param(
        [Parameter(Mandatory)] [string]$ServerName,
        [Parameter(Mandatory)] [string]$ToolName,
        [hashtable]$Arguments = @{}
    )

    if (-not $script:M365OpsMcpProcesses -or -not $script:M365OpsMcpProcesses[$ServerName] -or $script:M365OpsMcpProcesses[$ServerName].HasExited) {
        Connect-M365OpsMcpServer -Name $ServerName | Out-Null
    }

    Invoke-M365OpsMcpRequest -Process $script:M365OpsMcpProcesses[$ServerName] -Method "tools/call" -Params @{
        name      = $ToolName
        arguments = $Arguments
    }
}
