function Get-M365OpsTeamsPolicies {
    <#
    .SYNOPSIS
        Elenca i criteri Teams di riunione, chiamata e messaggistica in un'unica lista, distinti
        dalla colonna PolicyType - stesso principio di Get-M365OpsThreatPolicies per Exchange
        (colonne non pertinenti a un tipo restano vuote per quella riga, mai un dato inventato).
    .NOTES
        VERIFICATO DAL VIVO il 23/08/2026 (maratona di debug) su vnsys-test: il permesso
        Application 'application_access' sotto l'API "Skype and Teams Tenant Admin API"
        (diversa sia da Microsoft Graph sia dall'API "SharePoint" usata per
        Sites.FullControl.All) risulta concesso su questo tenant - Get-CsTeamsMeetingPolicy/
        Get-CsTeamsCallingPolicy/Get-CsTeamsMessagingPolicy restituiscono dati reali (19 righe
        nel test), le proprieta' selezionate sotto confermate corrette. Su un tenant SENZA
        quel permesso, le stesse cmdlet falliscono ancora con "Access Denied. Provide different
        credential or request access." - vedi sezione 4.4 della guida per come concederlo.

        Retry via isolamento reattivo aggiunto il 23/08/2026 (bug reale trovato dal vivo su
        Get-M365OpsTeamsExternalAccessConfig.ps1, stesso schema qui - vedi quel file per il
        dettaglio completo): Connect-M365OpsTeams sotto copre solo il proprio tentativo di
        connessione, non un conflitto .NET che scatta invece sulle chiamate dirette ai cmdlet
        Cs* qui sotto. Corpo in uno scriptblock invocato due volte (primo tentativo + eventuale
        retry post-isolamento) per non duplicare il codice ne' esportare una seconda funzione
        pubblica.
    #>
    Connect-M365OpsTeams

    # -ErrorAction Stop obbligatorio qui (bug reale osservato il 17/08/2026): senza permesso,
    # queste cmdlet native emettono un errore NON terminante ("Access Denied...") e restituiscono
    # zero oggetti invece di lanciare un'eccezione - senza Stop, il risultato sarebbe silenziosamente
    # un array vuoto (letto come "nessun criterio configurato") invece di un errore chiaro da
    # propagare al chiamante (vedi il dispatch di teams_query in Invoke-M365OpsAgentTools, che si
    # aspetta un'eccezione catturabile per distinguere "vuoto" da "permesso mancante").
    $body = {
        $meeting = Get-CsTeamsMeetingPolicy -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                PolicyType                 = 'Meeting'
                Identity                   = $_.Identity
                AllowMeetNow                = $_.AllowMeetNow
                AutoAdmittedUsers           = $_.AutoAdmittedUsers
                AllowAnonymousUsersToJoinMeeting = $_.AllowAnonymousUsersToJoinMeeting
                AllowCloudRecording         = $_.AllowCloudRecording
                AllowTranscription          = $_.AllowTranscription
                AllowPrivateCalling         = $null
                AllowVoicemail              = $null
                AllowUserChat               = $null
                AllowGiphy                  = $null
            }
        }
        $calling = Get-CsTeamsCallingPolicy -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                PolicyType                 = 'Calling'
                Identity                   = $_.Identity
                AllowMeetNow                = $null
                AutoAdmittedUsers           = $null
                AllowAnonymousUsersToJoinMeeting = $null
                AllowCloudRecording         = $null
                AllowTranscription          = $null
                AllowPrivateCalling         = $_.AllowPrivateCalling
                AllowVoicemail              = $_.AllowVoicemail
                AllowUserChat               = $null
                AllowGiphy                  = $null
            }
        }
        $messaging = Get-CsTeamsMessagingPolicy -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                PolicyType                 = 'Messaging'
                Identity                   = $_.Identity
                AllowMeetNow                = $null
                AutoAdmittedUsers           = $null
                AllowAnonymousUsersToJoinMeeting = $null
                AllowCloudRecording         = $null
                AllowTranscription          = $null
                AllowPrivateCalling         = $null
                AllowVoicemail              = $null
                AllowUserChat               = $_.AllowUserChat
                AllowGiphy                  = $_.AllowGiphy
            }
        }
        @($meeting) + @($calling) + @($messaging)
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
