function Get-M365OpsTransportConfig {
    <#
    .SYNOPSIS
        Configurazione di trasporto globale dell'organizzazione (impostazioni valide per
        TUTTO il tenant, non per un singolo connettore/regola - es. dimensione massima
        messaggio predefinita, rilevamento loop, TLS legacy).
    .NOTES
        Mode: ReadOnly
    #>
    Connect-M365OpsExchange
    Get-TransportConfig
}
