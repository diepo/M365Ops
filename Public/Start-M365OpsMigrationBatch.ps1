function Start-M365OpsMigrationBatch {
    <#
    .SYNOPSIS
        Avvia un batch di migrazione creato in precedenza con New-M365OpsMigrationBatch
        (creato sempre non avviato) - passo separato ed esplicito, mai automatico alla
        creazione. Con -StartAfter la sincronizzazione parte da sola alla data/ora indicata
        invece che subito (utile per programmarla fuori orario), restando comunque "in coda"
        da questo momento. -ExtraParams passa altri parametri nativi di Start-MigrationBatch
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs "Start-MigrationBatch".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [datetime]$StartAfter,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Identity = $Identity; ErrorAction = 'Stop' }
    if ($StartAfter) { $params.StartAfter = $StartAfter }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Start-MigrationBatch @params
    Write-Host "Batch di migrazione avviato: $Identity" -ForegroundColor Green
    Get-MigrationBatch -Identity $Identity | Select-Object Identity, Status, TotalCount, FinalizedCount
}
