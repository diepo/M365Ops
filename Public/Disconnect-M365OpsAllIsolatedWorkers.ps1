function Disconnect-M365OpsAllIsolatedWorkers {
    <#
    .SYNOPSIS
        Ferma OGNI processo worker isolato attivo (Exchange/Teams, di TUTTI i tenant) - usata
        al riavvio/arresto del server (Gui\Server.ps1), MAI automaticamente ad ogni cambio
        tenant: stesso principio gia' scelto per i server MCP (Disconnect-M365OpsAllMcpServers)
        - i worker isolati restano vivi in background per riuso quando si torna su un tenant
        gia' visitato, evitando di rifare l'intero Connect-ExchangeOnline/Connect-MicrosoftTeams
        (potenzialmente lento) ad ogni switch.
    .PARAMETER TenantName
        Se specificato, ferma solo i worker di QUEL tenant - usata da Remove-M365OpsTenant.
    #>
    param([string]$TenantName)

    if (-not $script:M365OpsIsolatedWorkers) { return }

    $tenants = if ($TenantName) { @($TenantName) } else { @($script:M365OpsIsolatedWorkers.Keys) }
    foreach ($tenant in $tenants) {
        if (-not $script:M365OpsIsolatedWorkers[$tenant]) { continue }
        foreach ($moduleType in @($script:M365OpsIsolatedWorkers[$tenant].Keys)) {
            $proc = $script:M365OpsIsolatedWorkers[$tenant][$moduleType]
            if ($proc -and -not $proc.HasExited) {
                try { $proc.Kill() } catch {}
                Write-Host "Worker isolato $moduleType fermato (tenant '$tenant')." -ForegroundColor Yellow
            }
        }
        $script:M365OpsIsolatedWorkers.Remove($tenant)
    }
}
