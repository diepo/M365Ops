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
    $params = @{ Equipment = $true; Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $eq = New-Mailbox @params
    Write-Host "Attrezzatura creata: $($eq.DisplayName)" -ForegroundColor Green
    $eq | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails
}
