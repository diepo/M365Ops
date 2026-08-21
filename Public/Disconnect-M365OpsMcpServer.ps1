function Disconnect-M365OpsMcpServer {
    <#
    .SYNOPSIS
        Ferma il sottoprocesso di un server MCP, se attivo. Generalizzazione di
        Disconnect-M365OpsLokka (26/08/2026) - vedi Connect-M365OpsMcpServer.ps1 per il
        perche'. Ferma solo il PROCESSO MCP locale: per server con un login separato e
        persistente su disco (es. CLI-Microsoft365, vedi Connect-M365OpsCliMicrosoft365.ps1)
        quel login NON viene revocato qui - rifare login ad ogni cambio tenant sarebbe
        inutilmente lento, il record resta e si riattiva da solo al prossimo utilizzo.
    #>
    param([Parameter(Mandatory)] [string]$Name)

    if ($script:M365OpsMcpProcesses -and $script:M365OpsMcpProcesses[$Name] -and -not $script:M365OpsMcpProcesses[$Name].HasExited) {
        $script:M365OpsMcpProcesses[$Name].Kill()
        Write-Host "Server MCP '$Name' fermato." -ForegroundColor Yellow
    }
    if ($script:M365OpsMcpProcesses) { $script:M365OpsMcpProcesses.Remove($Name) }
    if ($script:M365OpsMcpTools) { $script:M365OpsMcpTools.Remove($Name) }
}
