function New-M365OpsEquipmentMailbox {
    <#
    .SYNOPSIS
        Crea una mailbox risorsa di tipo attrezzatura. -ExtraParams passa altri
        parametri nativi di New-Mailbox - se non sei sicuro del nome esatto, consulta
        prima lookup_ms_docs "New-Mailbox".
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
    $params = @{ Equipment = $true; Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $eq = New-Mailbox @params
    Write-Host "Attrezzatura creata: $($eq.DisplayName)" -ForegroundColor Green
    $eq | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails
}
