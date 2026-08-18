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
    $params = @{ Identity = $Identity; Confirm = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Remove-MailContact @params
    Write-Host "Contatto rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
