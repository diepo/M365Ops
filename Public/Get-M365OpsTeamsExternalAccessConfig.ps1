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

        Retry via isolamento reattivo aggiunto il 23/08/2026 (bug reale trovato dal vivo,
        bug-hunt di 16 ore): Connect-M365OpsTeams sotto ha gia' la SUA logica di recupero
        isolamento incorporata (vedi quel file), ma copre solo il SUO proprio tentativo di
        connessione - se il conflitto .NET di sezione 6.6 scatta invece QUI, sulle chiamate
        dirette ai cmdlet Cs* nativi (possibile anche con Connect-M365OpsTeams gia' riuscito
        senza conflitto: il conflitto dipende da QUALI assembly sono gia' stati caricati nel
        processo in quel momento, non solo dal momento della connessione), l'eccezione risaliva
        senza nessun tentativo di recupero locale. Riprodotto dal vivo: "quali policy di
        sicurezza per l'accesso esterno ha configurato teams" ha mostrato "riavvia M365Ops"
        all'utente nonostante il log del server mostri che l'isolamento reattivo si era GIA'
        attivato con successo pochi istanti prima (per la connessione di Connect-M365OpsTeams)
        - la richiesta di dati vera e propria non aveva pero' alcun modo di ritentare dopo che
        l'isolamento era pronto. Ora, se le chiamate sotto falliscono con lo stesso conflitto,
        si tenta un singolo retry esplicito dopo aver (ri)attivato l'isolamento per Teams -
        idempotente se gia' attivo (vedi Connect-M365OpsIsolatedModule). Il corpo vero e proprio
        vive in uno scriptblock invocato due volte (primo tentativo + eventuale retry) invece di
        essere duplicato per intero o spostato in una seconda funzione (che finirebbe esportata
        insieme a questa, violando la convenzione un-file-un-cmdlet pubblico del modulo).
    #>
    Connect-M365OpsTeams

    # BUG reale trovato dal vivo il 23/08/2026 su vnsys-test: le 4 righe sotto avevano
    # ciascuna il PROPRIO set di colonne (nessuno schema unificato), a differenza del
    # gemello Get-M365OpsTeamsPolicies (che unisce esplicitamente tutte le colonne con
    # $null per quelle non pertinenti, proprio per evitare questo problema - vedi le
    # NOTES di quella funzione). Risultato verificato dal vivo: ConvertTo-Csv/Export-Csv/
    # Format-Table (che usano le proprieta' del PRIMO oggetto per l'intera tabella) fanno
    # sparire silenziosamente dati reali - es. AllowUserChat=True per 'Ospiti -
    # messaggistica' spariva del tutto dal CSV, pur essendo presente e leggibile per
    # proprieta' diretta sull'oggetto. Corretto unendo tutte le colonne su ogni riga,
    # stesso schema di Get-M365OpsTeamsPolicies.
    $body = {
        $federation = Get-CsTenantFederationConfiguration -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                ConfigType         = 'Federazione esterna'
                Identity           = $_.Identity
                AllowFederatedUsers = $_.AllowFederatedUsers
                AllowPublicUsers   = $_.AllowPublicUsers
                AllowTeamsConsumer = $_.AllowTeamsConsumer
                BlockedDomains     = ($_.BlockedDomains | Out-String).Trim()
                AllowUserChat      = $null
                AllowGiphy         = $null
                AllowUserEditMessage = $null
                AllowIPVideo       = $null
                AllowMeetNow       = $null
                ScreenSharingMode  = $null
                AllowPrivateCalling = $null
            }
        }
        $guestMessaging = Get-CsTeamsGuestMessagingConfiguration -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                ConfigType = 'Ospiti - messaggistica'
                Identity   = $_.Identity
                AllowFederatedUsers = $null
                AllowPublicUsers   = $null
                AllowTeamsConsumer = $null
                BlockedDomains     = $null
                AllowUserChat      = $_.AllowUserChat
                AllowGiphy         = $_.AllowGiphy
                AllowUserEditMessage = $_.AllowUserEditMessage
                AllowIPVideo       = $null
                AllowMeetNow       = $null
                ScreenSharingMode  = $null
                AllowPrivateCalling = $null
            }
        }
        $guestMeeting = Get-CsTeamsGuestMeetingConfiguration -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                ConfigType = 'Ospiti - riunioni'
                Identity   = $_.Identity
                AllowFederatedUsers = $null
                AllowPublicUsers   = $null
                AllowTeamsConsumer = $null
                BlockedDomains     = $null
                AllowUserChat      = $null
                AllowGiphy         = $null
                AllowUserEditMessage = $null
                AllowIPVideo    = $_.AllowIPVideo
                AllowMeetNow    = $_.AllowMeetNow
                ScreenSharingMode = $_.ScreenSharingMode
                AllowPrivateCalling = $null
            }
        }
        $guestCalling = Get-CsTeamsGuestCallingConfiguration -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                ConfigType = 'Ospiti - chiamate'
                Identity   = $_.Identity
                AllowFederatedUsers = $null
                AllowPublicUsers   = $null
                AllowTeamsConsumer = $null
                BlockedDomains     = $null
                AllowUserChat      = $null
                AllowGiphy         = $null
                AllowUserEditMessage = $null
                AllowIPVideo       = $null
                AllowMeetNow       = $null
                ScreenSharingMode  = $null
                AllowPrivateCalling = $_.AllowPrivateCalling
            }
        }
        @($federation) + @($guestMessaging) + @($guestMeeting) + @($guestCalling)
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
