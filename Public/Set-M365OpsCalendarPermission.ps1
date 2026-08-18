function Set-M365OpsCalendarPermission {
    <#
    .SYNOPSIS
        Assegna (o aggiorna se gia' presente) un permesso sulla cartella Calendario di
        una mailbox, es. AccessRights 'Reviewer', 'Editor', 'AvailabilityOnly'.
        -ExtraParams passa altri parametri nativi di Add-/Set-MailboxFolderPermission
        (es. SharingPermissionFlags) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "Add-MailboxFolderPermission".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$AccessRights,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # Vedi Get-M365OpsCalendarPermissions: il nome della cartella e' localizzato, risolto qui
    # dinamicamente invece di assumere ":\Calendar" (fallirebbe su mailbox non in inglese).
    $calendarFolder = Get-MailboxFolderStatistics -Identity $Identity -FolderScope Calendar | Where-Object { $_.FolderType -eq 'Calendar' } | Select-Object -First 1
    if (-not $calendarFolder) { throw "Cartella Calendario non trovata per $Identity." }
    $folder = "$($Identity):\$($calendarFolder.Name)"
    $existing = Get-MailboxFolderPermission -Identity $folder -User $User -ErrorAction SilentlyContinue

    $params = @{ Identity = $folder; User = $User; AccessRights = $AccessRights }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    if ($existing) {
        Set-MailboxFolderPermission @params
    } else {
        Add-MailboxFolderPermission @params
    }
    Write-Host "Permesso calendario '$AccessRights' impostato per $User su $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; User = $User; AccessRights = $AccessRights }
}
