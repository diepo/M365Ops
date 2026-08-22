function Remove-M365OpsMailContact {
    <#
    .SYNOPSIS
        Elimina un contatto di posta esterno. -ExtraParams passa altri parametri nativi
        di Remove-MailContact - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "Remove-MailContact".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Identity = $Identity; Confirm = $false; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Remove-MailContact @params
    Write-Host "Contatto rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
