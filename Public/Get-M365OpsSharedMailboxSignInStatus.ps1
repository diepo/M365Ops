function Get-M365OpsSharedMailboxSignInStatus {
    <#
    .SYNOPSIS
        Controllo di sicurezza incrociato Exchange+Graph: verifica se l'account Entra ID
        collegato a una mailbox condivisa ha il login abilitato. Una mailbox condivisa
        con account abilitato al login e' una configurazione a rischio (permette accesso
        diretto con password anziche' solo via delega) - dovrebbe restare sempre disabilitato.
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited | ForEach-Object {
        $mbx = $_
        try {
            $user = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$($mbx.PrimarySmtpAddress)?`$select=accountEnabled"
            [pscustomobject]@{
                DisplayName        = $mbx.DisplayName
                PrimarySmtpAddress = $mbx.PrimarySmtpAddress
                SignInEnabled      = $user.accountEnabled
                Risk               = if ($user.accountEnabled) { 'Login abilitato su mailbox condivisa - da disabilitare' } else { 'OK' }
            }
        }
        catch {
            [pscustomobject]@{ DisplayName = $mbx.DisplayName; PrimarySmtpAddress = $mbx.PrimarySmtpAddress; SignInEnabled = $null; Risk = 'Impossibile verificare' }
        }
    }
}
