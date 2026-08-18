function Get-M365OpsSharedMailboxes {
    <#
    .SYNOPSIS
        Elenca le mailbox condivise del tenant (dato Exchange Online, non disponibile via Graph).
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, WhenMailboxCreated
}
