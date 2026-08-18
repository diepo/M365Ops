function Get-M365OpsAllMailboxes {
    <#
    .SYNOPSIS
        Elenca tutte le mailbox del tenant, di ogni tipo (utente, condivisa, risorsa).
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, WhenMailboxCreated
}
