function Get-M365OpsInactiveMailboxes {
    <#
    .SYNOPSIS
        Mailbox senza logon da piu' di -DaysInactive giorni (default 90) - utile per
        individuare licenze/risorse inutilizzate.
    #>
    param([int]$DaysInactive = 90)
    Connect-M365OpsExchange
    $threshold = (Get-Date).AddDays(-$DaysInactive)
    Get-EXOMailbox -ResultSize Unlimited | ForEach-Object {
        $stats = Get-EXOMailboxStatistics -Identity $_.PrimarySmtpAddress -Properties LastLogonTime -ErrorAction SilentlyContinue
        if (-not $stats.LastLogonTime -or $stats.LastLogonTime -lt $threshold) {
            [pscustomobject]@{
                DisplayName          = $_.DisplayName
                PrimarySmtpAddress   = $_.PrimarySmtpAddress
                RecipientTypeDetails = $_.RecipientTypeDetails
                LastLogonTime        = $stats.LastLogonTime
            }
        }
    }
}
