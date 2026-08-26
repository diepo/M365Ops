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

    # Bug reale (stesso schema di v0.10.1/v0.10.2/v0.10.6, trovato durante l'audit del
    # 26/08/2026): su un tenant con molte mailbox, una singola mailbox "problematica" (es. un
    # tipo di destinatario raro su cui Get-EXOMailboxPermission/Get-EXORecipientPermission
    # lancia un errore terminante, o una limitazione/throttling momentanea) faceva morire
    # l'INTERO report a meta' - tutte le mailbox successive nel ciclo, per quanto perfettamente
    # sane, sparivano in silenzio dal risultato invece di essere semplicemente saltate. Ogni
    # mailbox e' un'unita' di lavoro indipendente dalle altre: un errore su una non deve mai
    # impedire di riportare le altre.
    $targets | ForEach-Object {
        $mbx = $_
        try {
            Get-M365OpsMailboxPermissions -Identity $mbx.PrimarySmtpAddress | ForEach-Object {
                [pscustomobject]@{
                    Mailbox = $mbx.PrimarySmtpAddress
                    User    = $_.User
                    Type    = $_.Type
                    Rights  = $_.Rights
                }
            }
        }
        catch {
            [pscustomobject]@{
                Mailbox = $mbx.PrimarySmtpAddress
                User    = $null
                Type    = 'Errore'
                Rights  = "Impossibile leggere i permessi di questa mailbox: $($_.Exception.Message)"
            }
        }
    }
}
