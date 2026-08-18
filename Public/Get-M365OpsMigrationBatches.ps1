function Get-M365OpsMigrationBatches {
    <#
    .SYNOPSIS
        Elenca i batch di migrazione (verso o da Exchange Online: cutover, staged,
        IMAP, cross-tenant) con stato ed eventuali errori - sola lettura.
        Per crearne uno nuovo vedi New-M365OpsMigrationBatch (richiede un endpoint gia'
        configurato, vedi Get-M365OpsMigrationEndpoints).
    #>
    Connect-M365OpsExchange
    Get-MigrationBatch | Select-Object Identity, MigrationType, Status, TotalCount, FinalizedCount, SyncedCount, ErrorCount
}
