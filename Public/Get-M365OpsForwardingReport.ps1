function Get-M365OpsForwardingReport {
    <#
    .SYNOPSIS
        Mailbox con inoltro automatico configurato (ForwardingSmtpAddress o
        ForwardingAddress) - rilevante per sicurezza, l'inoltro esterno non autorizzato
        e' un vettore comune di esfiltrazione dati.
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -ResultSize Unlimited -Properties ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward |
        Where-Object { $_.ForwardingSmtpAddress -or $_.ForwardingAddress } |
        Select-Object DisplayName, PrimarySmtpAddress, ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward
}
