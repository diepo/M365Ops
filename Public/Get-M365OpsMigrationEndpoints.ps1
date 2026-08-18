function Get-M365OpsMigrationEndpoints {
    <#
    .SYNOPSIS
        Elenca gli endpoint di migrazione GIA' configurati nel tenant (IMAP, Exchange
        remoto, cross-tenant...) - usali con New-M365OpsMigrationBatch per creare un batch.
        La creazione di un NUOVO endpoint non e' esposta da questo modulo: richiede le
        credenziali del sistema sorgente esterno, va fatta manualmente dal centro
        amministrazione Exchange o con New-MigrationEndpoint diretto, con supervisione.
    #>
    Connect-M365OpsExchange
    Get-MigrationEndpoint | Select-Object Identity, EndpointType, RemoteServer, Max, MaxConcurrentMigrations, IsValid
}
