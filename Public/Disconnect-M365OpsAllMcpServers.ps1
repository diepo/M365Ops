function Disconnect-M365OpsAllMcpServers {
    <#
    .SYNOPSIS
        Ferma OGNI sottoprocesso MCP attivo, di TUTTI i tenant (Lokka, CLI-Microsoft365, ecc.) -
        usata al riavvio/arresto del server (Gui\Server.ps1), MAI piu' automaticamente ad ogni
        cambio tenant dal 26/08/2026 (vedi Connect-M365OpsMcpServer.ps1: i processi ora restano
        vivi in background per riuso quando si torna su un tenant gia' visitato in questa
        sessione) - qui serve invece una pulizia totale, es. prima che il processo server stesso
        termini, per non lasciare sottoprocessi orfani.
    .PARAMETER TenantName
        Se specificato, ferma solo i server MCP di QUEL tenant invece di tutti - usata da
        Remove-M365OpsTenant per ripulire un profilo specifico senza toccare gli altri tenant
        eventualmente ancora attivi in background.
    #>
    param([string]$TenantName)

    if (-not $script:M365OpsMcpProcesses) { return }

    $tenants = if ($TenantName) { @($TenantName) } else { @($script:M365OpsMcpProcesses.Keys) }
    foreach ($tenant in $tenants) {
        if (-not $script:M365OpsMcpProcesses[$tenant]) { continue }
        foreach ($name in @($script:M365OpsMcpProcesses[$tenant].Keys)) {
            Disconnect-M365OpsMcpServer -Name $name -TenantName $tenant
        }
    }
}
