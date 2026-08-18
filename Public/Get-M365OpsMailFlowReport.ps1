function Get-M365OpsMailFlowReport {
    <#
    .SYNOPSIS
        Report sintetico del flusso posta nel periodo indicato, ricavato da
        Get-MailTrafficSummaryReport (report storici aggregati Microsoft) o, in fallback,
        da un conteggio per stato via Get-MessageTrace (max 10 giorni).
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
        Write-Host "Get-MailTrafficSummaryReport non disponibile, fallback su Get-MessageTrace (campione)." -ForegroundColor Yellow
        Get-MessageTrace -StartDate $StartDate -EndDate $EndDate -PageSize 1000 |
            Group-Object Status | Select-Object Name, Count
    }
}
