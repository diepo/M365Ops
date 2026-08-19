function Add-M365OpsSendOnBehalf {
    <#
    .SYNOPSIS
        Aggiunge un delegato SendOnBehalf su una mailbox (si somma ai delegati esistenti).
        -ExtraParams passa altri parametri nativi di Set-Mailbox (es. MessageCopyForSendOnBehalfEnabled)
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs "Set-Mailbox".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$User,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $mailbox = Get-Mailbox -Identity $Identity
    $current = @($mailbox.GrantSendOnBehalfTo)
    if ($current -contains $User) { throw "$User ha gia' SendOnBehalf su $Identity." }

    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026).
    $params = @{ Identity = $Identity; GrantSendOnBehalfTo = ($current + $User); ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-Mailbox @params

    Write-Host "SendOnBehalf concesso a $User su $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; User = $User; Granted = $true }
}
