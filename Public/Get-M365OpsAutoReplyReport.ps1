function Get-M365OpsAutoReplyReport {
    <#
    .SYNOPSIS
        Stato della risposta automatica (fuori sede) per tutte le mailbox utente, o solo
        per -Identity se specificato.
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    $targets = if ($Identity) { , $Identity } else { (Get-EXOMailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited).PrimarySmtpAddress }
    $targets | ForEach-Object {
        $cfg = Get-MailboxAutoReplyConfiguration -Identity $_ -ErrorAction SilentlyContinue
        if ($cfg) {
            [pscustomobject]@{
                Identity       = $_
                AutoReplyState = $cfg.AutoReplyState
                StartTime      = $cfg.StartTime
                EndTime        = $cfg.EndTime
            }
        }
    }
}
