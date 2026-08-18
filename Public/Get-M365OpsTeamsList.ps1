function Get-M365OpsTeamsList {
    <#
    .SYNOPSIS
        Elenca i Team del tenant: visibilita', se archiviato, e i criteri di collaborazione a
        livello di team (chi puo' creare canali/aggiungere app/menzionare tutto il team, ecc.).
        Verificato dal vivo il 17/08/2026 - funziona con lo stesso certificato di Exchange,
        nessun permesso aggiuntivo necessario.
    #>
    Connect-M365OpsTeams
    Get-Team |
        Select-Object DisplayName, GroupId, Visibility, Archived, MailNickName, Description,
            AllowCreateUpdateChannels, AllowCreatePrivateChannels, AllowDeleteChannels, AllowAddRemoveApps,
            AllowGuestCreateUpdateChannels, AllowGuestDeleteChannels, AllowTeamMentions, AllowChannelMentions
}
