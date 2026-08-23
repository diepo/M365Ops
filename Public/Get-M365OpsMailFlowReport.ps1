function Get-M365OpsMailFlowReport {
    <#
    .SYNOPSIS
        Report sintetico del flusso posta nel periodo indicato, ricavato da
        Get-MailTrafficSummaryReport (report storici aggregati Microsoft) o, in fallback,
        da un conteggio per stato via Get-MessageTraceV2 (max 10 giorni).
    .NOTES
        Fallback su Get-MessageTraceV2, non il vecchio Get-MessageTrace (bug reale corretto il
        23/08/2026): Get-MessageTrace e' in dismissione dal 1/09/2025 (vedi le stesse note in
        Get-M365OpsMessageTrace.ps1) ed e' stato verificato dal vivo su questo tenant che ormai
        fallisce con un errore terminante invece di un semplice warning - il fallback, pensato
        per essere piu' affidabile del percorso primario, falliva a sua volta sempre. -ResultSize
        sostituisce -PageSize (non esiste piu' su V2).
    #>
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-7),
        [datetime]$EndDate = (Get-Date)
    )
    Connect-M365OpsExchange
    try {
        Get-MailTrafficSummaryReport -Category TopMailSender -StartDate $StartDate -EndDate $EndDate -AggregateBy Summary
    }
    catch {
        Write-Host "Get-MailTrafficSummaryReport non disponibile, fallback su Get-MessageTraceV2 (campione)." -ForegroundColor Yellow
        Get-MessageTraceV2 -StartDate $StartDate -EndDate $EndDate -ResultSize 1000 |
            Group-Object Status | Select-Object Name, Count
    }
}
