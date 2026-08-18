function Enable-M365OpsMailboxQuarantine {
    <#
    .SYNOPSIS
        Mette in quarantena una MAILBOX (non un singolo messaggio) - le impedisce di
        inviare posta, tipicamente usato su un account compromesso sospettato di inviare
        spam/phishing mentre e' sotto indagine. Diverso da Get-/Release-/Remove-
        M365OpsQuarantineMessages, che agiscono su singoli messaggi.
    .PARAMETER Duration
        Formato TimeSpan (es. "1.00:00:00" per 1 giorno) - se omesso, il servizio usa il
        proprio default nativo.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string]$Duration
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity; Confirm = $false }
    if ($Duration) { $params.Duration = $Duration }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Enable-MailboxQuarantine @params -ErrorAction Stop
    Write-Host "Mailbox messa in quarantena (invio bloccato): $Identity" -ForegroundColor Green
}
