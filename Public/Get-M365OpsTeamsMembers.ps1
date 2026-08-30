function Get-M365OpsTeamsMembers {
    <#
    .SYNOPSIS
        Elenca i membri di UN team (GroupId da Get-M365OpsTeamsList, mai indovinato), con ruolo
        (owner/member/guest) - utile per capire chi ha diritti di ospite in un team specifico.
        Verificato dal vivo il 17/08/2026.
    .NOTES
        Retry via isolamento reattivo aggiunto (bug reale, stesso schema gia' corretto su
        Get-M365OpsTeamsPolicies/Get-M365OpsTeamsExternalAccessConfig - vedi quei file per il
        dettaglio completo): Connect-M365OpsTeams sopra copre solo il proprio tentativo di
        connessione, non un conflitto .NET che scatta invece sulla chiamata diretta a
        Get-TeamUser qui sotto. Corpo in uno scriptblock invocato due volte (primo tentativo +
        eventuale retry post-isolamento) per non duplicare il codice ne' esportare una seconda
        funzione pubblica.
    #>
    param([Parameter(Mandatory)] [string]$GroupId)
    Connect-M365OpsTeams
    $body = {
        Get-TeamUser -GroupId $GroupId | Select-Object User, Name, Role
    }
    try {
        & $body
    }
    catch {
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Microsoft Teams' -OtherService 'Exchange Online'
        if (-not $hint) { throw }
        Connect-M365OpsIsolatedModule -ModuleType 'Teams' -ConnectParams (Get-M365OpsIsolatedConnectParams -ModuleType 'Teams')
        & $body
    }
}
