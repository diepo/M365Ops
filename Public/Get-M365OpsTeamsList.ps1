function Get-M365OpsTeamsList {
    <#
    .SYNOPSIS
        Elenca i Team del tenant: visibilita', se archiviato, e i criteri di collaborazione a
        livello di team (chi puo' creare canali/aggiungere app/menzionare tutto il team, ecc.).
        Verificato dal vivo il 17/08/2026 - funziona con lo stesso certificato di Exchange,
        nessun permesso aggiuntivo necessario.
    .NOTES
        Retry via isolamento reattivo aggiunto (bug reale, stesso schema gia' corretto su
        Get-M365OpsTeamsPolicies/Get-M365OpsTeamsExternalAccessConfig - vedi quei file per il
        dettaglio completo): Connect-M365OpsTeams sopra copre solo il proprio tentativo di
        connessione, non un conflitto .NET che scatta invece sulla chiamata diretta a Get-Team
        qui sotto. Corpo in uno scriptblock invocato due volte (primo tentativo + eventuale
        retry post-isolamento) per non duplicare il codice ne' esportare una seconda funzione
        pubblica.
    #>
    Connect-M365OpsTeams
    $body = {
        Get-Team |
            Select-Object DisplayName, GroupId, Visibility, Archived, MailNickName, Description,
                AllowCreateUpdateChannels, AllowCreatePrivateChannels, AllowDeleteChannels, AllowAddRemoveApps,
                AllowGuestCreateUpdateChannels, AllowGuestDeleteChannels, AllowTeamMentions, AllowChannelMentions
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
