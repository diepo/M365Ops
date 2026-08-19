function Remove-M365OpsSendOnBehalf {
    <#
    .SYNOPSIS
        Rimuove un delegato SendOnBehalf da una mailbox. -ExtraParams passa altri
        parametri nativi di Set-Mailbox - se non sei sicuro del nome esatto, consulta
        prima lookup_ms_docs "Set-Mailbox".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$User,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $mailbox = Get-Mailbox -Identity $Identity
    $remaining = @($mailbox.GrantSendOnBehalfTo) | Where-Object { $_ -ne $User }

    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026).
    $params = @{ Identity = $Identity; GrantSendOnBehalfTo = $remaining; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-Mailbox @params

    Write-Host "SendOnBehalf rimosso da $User su $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; User = $User; Revoked = $true }
}
