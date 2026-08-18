function Get-M365OpsInboxRulesReport {
    <#
    .SYNOPSIS
        Regole della posta in arrivo (inbox rule) configurate su tutte le mailbox utente,
        con evidenza delle regole potenzialmente sospette (inoltro/redirect esterno,
        cancellazione automatica) - utile per individuare compromissioni di account.
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    $targets = if ($Identity) { , $Identity } else { (Get-EXOMailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited).PrimarySmtpAddress }
    $targets | ForEach-Object {
        $mailboxId = $_
        Get-InboxRule -Mailbox $mailboxId -ErrorAction SilentlyContinue | ForEach-Object {
            $suspicious = [bool]($_.ForwardTo -or $_.ForwardAsAttachmentTo -or $_.RedirectTo -or $_.DeleteMessage)
            [pscustomobject]@{
                Mailbox       = $mailboxId
                RuleName      = $_.Name
                Enabled       = $_.Enabled
                ForwardTo     = (@($_.ForwardTo) + @($_.ForwardAsAttachmentTo) + @($_.RedirectTo)) -join '; '
                DeleteMessage = $_.DeleteMessage
                Suspicious    = $suspicious
            }
        }
    }
}
