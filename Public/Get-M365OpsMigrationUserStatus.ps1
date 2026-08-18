function Get-M365OpsMigrationUserStatus {
    <#
    .SYNOPSIS
        Stato di dettaglio per gli utenti di un batch di migrazione specifico.
    #>
    param([Parameter(Mandatory)] [string]$BatchIdentity)
    Connect-M365OpsExchange
    Get-MigrationUser -BatchId $BatchIdentity | Select-Object Identity, Status, SyncedItemCount, TotalItemCount, LastSyncedTime
}
