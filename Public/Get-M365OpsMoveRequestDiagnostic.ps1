function Get-M365OpsMoveRequestDiagnostic {
    <#
    .SYNOPSIS
        Diagnostica dettagliata di una migrazione mailbox (move request), stesso livello di
        dettaglio di 'Get-MoveRequestStatistics -IncludeReport -DiagnosticInfo
        "showtimeslots,showtimeline,verbose"' usato manualmente dagli admin Exchange per
        troubleshooting di migrazioni bloccate/lente.
    .PARAMETER Identity
        Identity della mailbox/utente in migrazione.
    .PARAMETER ExportClixmlPath
        Se specificato, esporta anche l'oggetto diagnostico ORIGINALE completo (non solo i campi
        riassunti restituiti da questo comando) in formato CliXml a questo percorso - stesso
        risultato di 'Get-MoveRequestStatistics ... | Export-Clixml', utile per analisi offline
        o per allegare il report a un ticket Microsoft Support senza perdere dettaglio.
    .NOTES
        Non tutte le migrazioni EXO usano un Move Request classico - un batch di onboarding
        creato con New-M365OpsMigrationBatch traccia i suoi utenti come MigrationUser, non come
        MoveRequest diretto. Prova prima Get-MoveRequestStatistics (il caso esplicitamente
        richiesto) e, se non trova nulla, ripiega su Get-MigrationUserStatistics (stessi
        parametri -IncludeReport/-DiagnosticInfo, stesso livello di dettaglio) prima di
        arrendersi - un admin che chiede "diagnostica la migrazione di X" non dovrebbe doversi
        preoccupare di quale dei due meccanismi sia stato usato per avviarla.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string]$ExportClixmlPath
    )
    Connect-M365OpsExchange

    $diagnosticInfo = "showtimeslots,showtimeline,verbose"
    $stats = $null
    $source = $null
    try {
        $stats = Get-MoveRequestStatistics -Identity $Identity -IncludeReport -DiagnosticInfo $diagnosticInfo -ErrorAction Stop
        $source = 'MoveRequest'
    }
    catch {
        try {
            $stats = Get-MigrationUserStatistics -Identity $Identity -IncludeReport -DiagnosticInfo $diagnosticInfo -ErrorAction Stop
            $source = 'MigrationUser'
        }
        catch {
            throw "Nessuna migrazione (move request o migration batch) trovata per '$Identity'. Verifica che la migrazione sia stata avviata (Start-M365OpsMigrationBatch) e che l'identity sia corretta."
        }
    }

    if ($ExportClixmlPath) {
        $stats | Export-Clixml -Path $ExportClixmlPath -Depth 5
    }

    [pscustomobject]@{
        Identity            = $Identity
        Source              = $source
        Status              = $stats.Status
        StatusDetail        = $stats.StatusDetail
        PercentComplete     = $stats.PercentComplete
        TotalMailboxSize    = [string]$stats.TotalMailboxSize
        BytesTransferred    = [string]$stats.BytesTransferred
        QueuedTimestamp     = $stats.QueuedTimestamp
        StartTimestamp      = $stats.StartTimestamp
        LastUpdateTimestamp = $stats.LastUpdateTimestamp
        FailureType         = $stats.FailureType
        Message             = $stats.Message
        FailureCode         = $stats.FailureCode
        Report              = $stats.Report
        ExportedToClixml    = $ExportClixmlPath
    }
}
