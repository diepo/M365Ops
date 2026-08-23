function Get-M365OpsSharedMailboxes {
    <#
    .SYNOPSIS
        Elenca le mailbox condivise del tenant (dato Exchange Online, non disponibile via Graph).
    #>
    Connect-M365OpsExchange
    # -Properties WhenMailboxCreated e' necessario: Get-EXOMailbox restituisce di default un set
    # ridotto di proprieta' e WhenMailboxCreated non ne fa parte - senza questo parametro la
    # colonna risultava sempre vuota anche se il dato esiste (bug reale verificato dal vivo,
    # 23/08/2026, stesso bug di Get-M365OpsAllMailboxes).
    Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties WhenMailboxCreated |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, WhenMailboxCreated
}
