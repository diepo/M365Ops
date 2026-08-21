function Disconnect-M365OpsAllMcpServers {
    <#
    .SYNOPSIS
        Ferma TUTTI i sottoprocessi MCP attivi (Lokka, CLI-Microsoft365, ecc.) - usata da
        Connect-M365Ops.ps1 ad ogni cambio tenant, stesso principio gia' applicato a
        Exchange/Teams/SharePoint: nessuno stato del tenant precedente deve sopravvivere a un
        cambio di profilo (26/08/2026).
    #>
    if (-not $script:M365OpsMcpProcesses) { return }
    foreach ($name in @($script:M365OpsMcpProcesses.Keys)) {
        Disconnect-M365OpsMcpServer -Name $name
    }
}
