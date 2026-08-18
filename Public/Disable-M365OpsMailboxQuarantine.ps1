function Disable-M365OpsMailboxQuarantine {
    <#
    .SYNOPSIS
        Toglie una mailbox dalla quarantena (rimuove il blocco sull'invio impostato da
        Enable-M365OpsMailboxQuarantine) - usalo solo dopo aver verificato che l'account
        non e' piu' compromesso.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Disable-MailboxQuarantine -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Mailbox tolta dalla quarantena: $Identity" -ForegroundColor Green
}
