function Get-M365OpsRoomMailboxBookingPolicy {
    <#
    .SYNOPSIS
        Legge la policy di prenotazione (approvazione automatica, delegati approvatori,
        durata massima) di una mailbox risorsa.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Get-CalendarProcessing -Identity $Identity |
        Select-Object Identity, AutomateProcessing, AllBookInPolicy, BookInPolicy, ResourceDelegates, MaximumDurationInMinutes
}
