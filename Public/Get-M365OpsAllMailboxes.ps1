function Get-M365OpsAllMailboxes {
    <#
    .SYNOPSIS
        Elenca tutte le mailbox del tenant, di ogni tipo (utente, condivisa, risorsa).
    #>
    Connect-M365OpsExchange
    # -Properties WhenMailboxCreated e' necessario: Get-EXOMailbox restituisce di default un set
    # ridotto di proprieta' e WhenMailboxCreated non ne fa parte - senza questo parametro la
    # colonna risultava sempre vuota anche se il dato esiste (bug reale verificato dal vivo,
    # 23/08/2026).
    Get-EXOMailbox -ResultSize Unlimited -Properties WhenMailboxCreated | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, WhenMailboxCreated
}
