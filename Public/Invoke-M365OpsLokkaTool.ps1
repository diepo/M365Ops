function Invoke-M365OpsLokkaTool {
    <#
    .SYNOPSIS
        Chiama un tool esposto da Lokka (vedi Connect-M365OpsLokka per l'elenco).
        Avvia Lokka automaticamente se non e' gia' attivo.

        Alias sottile su Invoke-M365OpsMcpServerTool -ServerName 'lokka' (26/08/2026) - vedi
        Connect-M365OpsMcpServer.ps1 per il perche'.
    #>
    param(
        [Parameter(Mandatory)] [string]$ToolName,
        [hashtable]$Arguments = @{}
    )
    Invoke-M365OpsMcpServerTool -ServerName 'lokka' -ToolName $ToolName -Arguments $Arguments
}
