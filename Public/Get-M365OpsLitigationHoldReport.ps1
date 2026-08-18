function Get-M365OpsLitigationHoldReport {
    <#
    .SYNOPSIS
        Mailbox con litigation hold attivo e relativa durata configurata.
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -ResultSize Unlimited -Properties LitigationHoldEnabled, LitigationHoldDuration |
        Where-Object { $_.LitigationHoldEnabled } |
        Select-Object DisplayName, PrimarySmtpAddress, LitigationHoldEnabled, LitigationHoldDuration
}
