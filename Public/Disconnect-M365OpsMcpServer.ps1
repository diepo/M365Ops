function Disconnect-M365OpsMcpServer {
    <#
    .SYNOPSIS
        Ferma il sottoprocesso di un server MCP per un tenant, se attivo. Generalizzazione di
        Disconnect-M365OpsLokka (26/08/2026) - vedi Connect-M365OpsMcpServer.ps1 per il perche'
        dell'isolamento per tenant (dizionario a due livelli, non piu' un solo processo per
        nome server condiviso tra tutti i tenant).

        Dal 26/08/2026 NON viene piu' chiamata automaticamente ad ogni cambio tenant (prima lo
        era, tramite Disconnect-M365OpsAllMcpServers in Connect-M365Ops.ps1) - i processi MCP
        di un tenant restano vivi in background quando si passa a un altro, cosi' tornare su un
        tenant gia' usato riattiva l'istanza gia' pronta invece di rifare login/handshake da
        capo. Resta utile per una pulizia esplicita (es. rimozione di un profilo tenant) o per
        far ripartire un server rotto.

        Ferma solo il PROCESSO MCP locale: per server con un login separato e persistente su
        disco (es. CLI-Microsoft365, vedi Connect-M365OpsCliMicrosoft365.ps1) quel login NON
        viene revocato qui - rifare login da zero sarebbe inutilmente lento, il record resta
        salvato e si riattiva da solo al prossimo utilizzo.
    .PARAMETER TenantName
        Default il tenant attivo. Specificarlo esplicitamente per fermare il processo di un
        ALTRO tenant (es. Remove-M365OpsTenant, che deve poter ripulire un profilo che non e'
        necessariamente quello attivo in questo momento).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$TenantName = $(if ($script:M365OpsContext) { $script:M365OpsContext.Name } else { $null })
    )

    if (-not $TenantName) { return }
    if ($script:M365OpsMcpProcesses -and $script:M365OpsMcpProcesses[$TenantName] -and $script:M365OpsMcpProcesses[$TenantName][$Name] -and -not $script:M365OpsMcpProcesses[$TenantName][$Name].HasExited) {
        $script:M365OpsMcpProcesses[$TenantName][$Name].Kill()
        Write-Host "Server MCP '$Name' fermato (tenant '$TenantName')." -ForegroundColor Yellow
    }
    if ($script:M365OpsMcpProcesses -and $script:M365OpsMcpProcesses[$TenantName]) { $script:M365OpsMcpProcesses[$TenantName].Remove($Name) }
    if ($script:M365OpsMcpTools -and $script:M365OpsMcpTools[$TenantName]) { $script:M365OpsMcpTools[$TenantName].Remove($Name) }
}
