function New-M365OpsRoomMailbox {
    <#
    .SYNOPSIS
        Crea una mailbox risorsa di tipo sala riunioni, opzionalmente con capienza.
        -ExtraParams passa altri parametri nativi di New-Mailbox (es. Location,
        MailboxRegion) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "New-Mailbox".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [int]$Capacity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params = @{ Room = $true; Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $room = New-Mailbox @params
    if ($Capacity) { Set-Mailbox -Identity $room.Identity -ResourceCapacity $Capacity -ErrorAction Stop }
    Write-Host "Sala riunioni creata: $($room.DisplayName)" -ForegroundColor Green
    $room | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails
}
