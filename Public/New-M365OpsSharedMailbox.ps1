function New-M365OpsSharedMailbox {
    <#
    .SYNOPSIS
        Crea una nuova mailbox condivisa. Nessun permesso viene assegnato per default -
        usa Grant-M365OpsMailboxPermission come passo separato. -ExtraParams passa
        qualunque altro parametro nativo di New-Mailbox non gia' previsto qui (es. Alias,
        OrganizationalUnit, Database) - se non sei sicuro del nome esatto o del formato
        atteso, consulta prima lookup_ms_docs "New-Mailbox".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Shared = $true; Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $mbx = New-Mailbox @params
    Write-Host "Mailbox condivisa creata: $($mbx.DisplayName) ($($mbx.PrimarySmtpAddress))" -ForegroundColor Green
    $mbx | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails
}
