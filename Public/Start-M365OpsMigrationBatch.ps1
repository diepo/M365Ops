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
    $params = @{ Identity = $Identity }
    if ($StartAfter) { $params.StartAfter = $StartAfter }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop impostato DOPO il merge di $ExtraParams (e non prima): $ExtraParams e'
    # un passthrough generico esposto al livello tool dell'IA, quindi un chiamante potrebbe
    # passare ExtraParams = @{ ErrorAction = 'SilentlyContinue' } - impostandolo prima del merge
    # quel valore lo sovrascriverebbe silenziosamente, disabilitando la protezione. Stesso
    # principio gia' applicato in New-M365OpsMigrationBatch.ps1 (bug-hunt 19/08/2026).
    $params.ErrorAction = 'Stop'
    Start-MigrationBatch @params
    Write-Host "Batch di migrazione avviato: $Identity" -ForegroundColor Green
    Get-MigrationBatch -Identity $Identity | Select-Object Identity, Status, TotalCount, FinalizedCount
}
