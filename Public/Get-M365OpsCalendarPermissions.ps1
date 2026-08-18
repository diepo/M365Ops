function Get-M365OpsCalendarPermissions {
    <#
    .SYNOPSIS
        Permessi sulla cartella Calendario di una mailbox.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # Il nome della cartella Calendario e' localizzato (es. "Calendario" su mailbox italiane) -
    # non si puo' assumere ":\Calendar" a prescindere dalla lingua della mailbox, va risolto
    # dinamicamente con Get-MailboxFolderStatistics (stesso principio per Set-M365OpsCalendarPermission).
    $calendarFolder = Get-MailboxFolderStatistics -Identity $Identity -FolderScope Calendar | Where-Object { $_.FolderType -eq 'Calendar' } | Select-Object -First 1
    if (-not $calendarFolder) { throw "Cartella Calendario non trovata per $Identity." }
    $folder = "$($Identity):\$($calendarFolder.Name)"
    Get-MailboxFolderPermission -Identity $folder |
        Select-Object User, AccessRights, SharingPermissionFlags
}
