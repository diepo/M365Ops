function Get-M365OpsMailboxDelegatesReport {
    <#
    .SYNOPSIS
        Report aggregato di TUTTI i permessi (FullAccess, SendAs, SendOnBehalf) su TUTTE
        le mailbox del tenant, non solo condivise - utile per audit generale di delega.
        Puo' essere lento su tenant con molte mailbox: usa -Identity per limitare l'analisi.
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    $targets = if ($Identity) { , (Get-EXOMailbox -Identity $Identity -Properties GrantSendOnBehalfTo) }
               else { Get-EXOMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo }

    $targets | ForEach-Object {
        $mbx = $_
        Get-M365OpsMailboxPermissions -Identity $mbx.PrimarySmtpAddress | ForEach-Object {
            [pscustomobject]@{
                Mailbox = $mbx.PrimarySmtpAddress
                User    = $_.User
                Type    = $_.Type
                Rights  = $_.Rights
            }
        }
    }
}
