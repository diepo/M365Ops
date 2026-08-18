function Set-M365OpsTransportConfig {
    <#
    .SYNOPSIS
        Modifica la configurazione di trasporto globale dell'organizzazione - ha effetto su
        TUTTO il tenant, non su un singolo connettore/regola. Passa i parametri da cambiare
        via -ExtraParams (es. AllowLegacyTLSClients, MaxSendSize) - se non sei sicuro del
        nome esatto, consulta prima lookup_ms_docs "Set-TransportConfig".
    #>
    param(
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-TransportConfig @ExtraParams -ErrorAction Stop
    Write-Host "Configurazione di trasporto globale aggiornata." -ForegroundColor Green
    Get-TransportConfig
}
