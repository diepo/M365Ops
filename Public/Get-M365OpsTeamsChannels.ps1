function Get-M365OpsTeamsChannels {
    <#
    .SYNOPSIS
        Elenca i canali di UN team (GroupId da Get-M365OpsTeamsList, mai indovinato). Verificato
        dal vivo il 17/08/2026.
    .NOTES
        Retry via isolamento reattivo aggiunto (bug reale, stesso schema gia' corretto su
        Get-M365OpsTeamsPolicies/Get-M365OpsTeamsExternalAccessConfig - vedi quei file per il
        dettaglio completo): Connect-M365OpsTeams sopra copre solo il proprio tentativo di
        connessione, non un conflitto .NET che scatta invece sulla chiamata diretta a
        Get-TeamChannel qui sotto. Corpo in uno scriptblock invocato due volte (primo tentativo
        + eventuale retry post-isolamento) per non duplicare il codice ne' esportare una seconda
        funzione pubblica.
    #>
    param([Parameter(Mandatory)] [string]$GroupId)
    Connect-M365OpsTeams
    $body = {
        Get-TeamChannel -GroupId $GroupId | Select-Object DisplayName, Id, Description, MembershipType
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
