function Get-M365OpsTeamsExternalAccessConfig {
    <#
    .SYNOPSIS
        Configurazione di accesso esterno/guest di Teams in un'unica lista, distinta dalla
        colonna ConfigType: federazione con organizzazioni esterne (chi puo' comunicare con
        chi al di fuori del tenant) + cosa possono fare gli ospiti (chat, riunioni, chiamate).
        Report di sicurezza classico - stesso spirito di Get-M365OpsSharePointSites per la
        condivisione esterna.
    .NOTES
        Verificato dal vivo il 18/08/2026 durante uno stress test: fallisce con "Access Denied"
        sul tenant di test, stesso permesso mancante di Get-M365OpsTeamsPolicies ("Skype and
        Teams Tenant Admin API", vedi sezione 4.4 della guida).

        BUG reale trovato dal vivo lo stesso giorno: mancava -ErrorAction Stop sui 4 cmdlet Cs*
        sotto (fix gia' applicato a Get-M365OpsTeamsPolicies il 17/08/2026 per lo STESSO motivo,
        mai riportato qui). Senza, "Access Denied" e' un errore NON terminante che produce un
        array vuoto invece di un'eccezione catturabile - il chiamante (teams_query in
        Invoke-M365OpsAgentTools) leggeva quindi "nessun dato" invece del vero errore di
        permesso, e l'AI riportava all'utente un fuorviante "strumento non disponibile" invece
        di spiegare la causa reale (mancanza del permesso, non un problema tecnico).
    #>
    Connect-M365OpsTeams

    $federation = Get-CsTenantFederationConfiguration -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            ConfigType         = 'Federazione esterna'
            Identity           = $_.Identity
            AllowFederatedUsers = $_.AllowFederatedUsers
            AllowPublicUsers   = $_.AllowPublicUsers
            AllowTeamsConsumer = $_.AllowTeamsConsumer
            BlockedDomains     = ($_.BlockedDomains | Out-String).Trim()
        }
    }
    $guestMessaging = Get-CsTeamsGuestMessagingConfiguration -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            ConfigType = 'Ospiti - messaggistica'
            Identity   = $_.Identity
            AllowUserChat      = $_.AllowUserChat
            AllowGiphy         = $_.AllowGiphy
            AllowUserEditMessage = $_.AllowUserEditMessage
        }
    }
    $guestMeeting = Get-CsTeamsGuestMeetingConfiguration -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            ConfigType = 'Ospiti - riunioni'
            Identity   = $_.Identity
            AllowIPVideo    = $_.AllowIPVideo
            AllowMeetNow    = $_.AllowMeetNow
            ScreenSharingMode = $_.ScreenSharingMode
        }
    }
    $guestCalling = Get-CsTeamsGuestCallingConfiguration -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            ConfigType = 'Ospiti - chiamate'
            Identity   = $_.Identity
            AllowPrivateCalling = $_.AllowPrivateCalling
        }
    }

    @($federation) + @($guestMessaging) + @($guestMeeting) + @($guestCalling)
}
