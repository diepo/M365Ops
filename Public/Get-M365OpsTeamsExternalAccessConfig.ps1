function Get-M365OpsTeamsExternalAccessConfig {
    <#
    .SYNOPSIS
        Configurazione di accesso esterno/guest di Teams in un'unica lista, distinta dalla
        colonna ConfigType: federazione con organizzazioni esterne (chi puo' comunicare con
        chi al di fuori del tenant) + cosa possono fare gli ospiti (chat, riunioni, chiamate).
        Report di sicurezza classico - stesso spirito di Get-M365OpsSharePointSites per la
        condivisione esterna.
    .NOTES
        NON ANCORA VERIFICATO DAL VIVO - stesso permesso mancante di Get-M365OpsTeamsPolicies
        (vedi le sue NOTES e la sezione 4.4 della guida).
    #>
    Connect-M365OpsTeams

    $federation = Get-CsTenantFederationConfiguration | ForEach-Object {
        [pscustomobject]@{
            ConfigType         = 'Federazione esterna'
            Identity           = $_.Identity
            AllowFederatedUsers = $_.AllowFederatedUsers
            AllowPublicUsers   = $_.AllowPublicUsers
            AllowTeamsConsumer = $_.AllowTeamsConsumer
            BlockedDomains     = ($_.BlockedDomains | Out-String).Trim()
        }
    }
    $guestMessaging = Get-CsTeamsGuestMessagingConfiguration | ForEach-Object {
        [pscustomobject]@{
            ConfigType = 'Ospiti - messaggistica'
            Identity   = $_.Identity
            AllowUserChat      = $_.AllowUserChat
            AllowGiphy         = $_.AllowGiphy
            AllowUserEditMessage = $_.AllowUserEditMessage
        }
    }
    $guestMeeting = Get-CsTeamsGuestMeetingConfiguration | ForEach-Object {
        [pscustomobject]@{
            ConfigType = 'Ospiti - riunioni'
            Identity   = $_.Identity
            AllowIPVideo    = $_.AllowIPVideo
            AllowMeetNow    = $_.AllowMeetNow
            ScreenSharingMode = $_.ScreenSharingMode
        }
    }
    $guestCalling = Get-CsTeamsGuestCallingConfiguration | ForEach-Object {
        [pscustomobject]@{
            ConfigType = 'Ospiti - chiamate'
            Identity   = $_.Identity
            AllowPrivateCalling = $_.AllowPrivateCalling
        }
    }

    @($federation) + @($guestMessaging) + @($guestMeeting) + @($guestCalling)
}
