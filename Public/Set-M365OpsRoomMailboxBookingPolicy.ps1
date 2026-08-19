function Set-M365OpsRoomMailboxBookingPolicy {
    <#
    .SYNOPSIS
        Imposta la policy di prenotazione di una mailbox risorsa: approvazione automatica
        o manuale (con delegati approvatori) e durata massima prenotazione. -ExtraParams
        passa altri parametri nativi di Set-CalendarProcessing (es. BookingWindowInDays,
        MinimumDurationInMinutes, AllowConflicts) - se non sei sicuro del nome esatto,
        consulta prima lookup_ms_docs "Set-CalendarProcessing".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [ValidateSet('AutoAccept', 'AutoUpdate', 'None')] [string]$AutomateProcessing,
        [string[]]$ResourceDelegates,
        [int]$MaximumDurationInMinutes,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026).
    $params = @{ Identity = $Identity; ErrorAction = 'Stop' }
    if ($AutomateProcessing) { $params.AutomateProcessing = $AutomateProcessing }
    if ($ResourceDelegates) { $params.ResourceDelegates = $ResourceDelegates; $params.AllBookInPolicy = $false }
    if ($MaximumDurationInMinutes) { $params.MaximumDurationInMinutes = $MaximumDurationInMinutes }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-CalendarProcessing @params
    Write-Host "Policy di prenotazione aggiornata per $Identity" -ForegroundColor Green
    Get-M365OpsRoomMailboxBookingPolicy -Identity $Identity
}
