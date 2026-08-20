function Connect-M365OpsExchange {
    <#
    .SYNOPSIS
        Connette a Exchange Online PowerShell usando il tenant attivo. Su tenant AppOnly
        e' sempre silenziosa (certificato, nessuna interazione). Su tenant Delegated
        richiede un login interattivo (browser) che BLOCCA il processo finche' non viene
        completato - dato che il server di questo modulo gestisce le richieste una alla
        volta (single-threaded), un blocco qui congela l'intera app per chiunque, non solo
        per chi ha fatto la richiesta. Per questo, su un tenant Delegated senza sessione
        gia' attiva, questa funzione NON tenta il login da sola: lancia subito un errore
        chiaro, a meno che non venga chiamata esplicitamente con -AllowInteractive (uso
        riservato a un'azione dedicata e consapevole dell'utente - vedi il pulsante
        "Connetti Exchange (delegato)" nella GUI).
    #>
    param([switch]$Force, [switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsExchangeConnected -and -not $Force) { return }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated' -and -not $AllowInteractive) {
        throw "Sessione Exchange Online non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab Tenant (non MCP/Connettori), sezione 'Stato connessioni', Exchange Online, e clicca 'Connetti / Test connessione Exchange' per farlo esplicitamente, poi riprova."
    }

    # BUG STRUTTURALE DI TERZE PARTI, trovato e riprodotto dal vivo il 22/08/2026 (in
    # App-only, quindi indipendente dalla modalita' Delegata o dall'ambiente Sandbox - non
    # e' un bug di questo progetto): i moduli MicrosoftTeams e ExchangeOnlineManagement
    # portano con se' versioni INCOMPATIBILI delle stesse librerie condivise di
    # autenticazione (Microsoft.Identity.Client / Microsoft.IdentityModel.*) - una volta che
    # UN modulo le ha caricate nel processo, l'ALTRO fallisce sempre, in ENTRAMBE le
    # direzioni (riprodotto qui stesso: Teams poi Exchange fallisce su
    # Microsoft.IdentityModel.Abstractions, Exchange poi Teams fallisce su
    # Microsoft.Identity.Client - cambiare l'ordine non risolve nulla). Conflitto pubblico e
    # documentato da anni (es. "PowerShell Module Clash for Teams and Exchange Online",
    # office365itpros.com, 2023) - nessun fix lato Microsoft, l'unico modo reale di evitarlo
    # sarebbe isolare uno dei due moduli in un processo/job separato (refactoring
    # architetturale sostanzioso, non fatto qui). Controllato PRIMA di importare il modulo,
    # cosi' l'utente vede un errore chiaro invece del criptico ".NET FileLoadException"
    # nativo che aveva causato un blocco/crash apparente del server.
    if ($script:M365OpsTeamsModuleImported) {
        throw "Impossibile connettersi a Exchange Online: il modulo MicrosoftTeams e' gia' stato caricato in questo stesso processo server, e i due moduli portano versioni incompatibili delle stesse librerie di autenticazione - conflitto noto e documentato di Microsoft (non un bug di M365Ops), presente da anni, senza soluzione lato modulo. In QUESTA sessione del server puoi usare Teams OPPURE Exchange, non entrambi - riavvia il server (pulsante Manutenzione, o 'M365Ops - Termina e riavvia' sul Desktop se non risponde) per liberare il processo e usare Exchange da capo."
    }

    # Versione FISSATA a 3.9.0 (23/08/2026), non "l'ultima disponibile": l'utente ha fatto
    # notare giustamente che il conflitto con MicrosoftTeams (blocco commento sopra) non gli
    # tornava - "ieri ho connesso tutti i servizi uno dopo l'altro senza errori", ipotizzando
    # una dipendenza dalla versione dei moduli. Aveva ragione: verificato dal vivo (non a
    # memoria) con Connect-ExchangeOnline reale (credenziali finte, l'assembly conflict scatta
    # PRIMA di qualunque validazione di rete) che il conflitto NON dipende dalla versione di
    # MicrosoftTeams installata (riprodotto identico sia con 7.3.1 sia con 7.9.0), ma dalla
    # versione di ExchangeOnlineManagement: 3.9.0 non va MAI in conflitto con Teams (testato
    # con entrambe le versioni Teams sopra), 3.10.0+ va SEMPRE in conflitto (riprodotto anche
    # l'errore esatto dell'utente, stesso "Microsoft.Identity.Client.dll... manifest
    # definition does not match", con Teams 7.9.0 + Exchange 3.10.1). 3.9.0 supporta comunque
    # tutto cio' che serve a questo progetto: -CertificateThumbprint/-Certificate (App-only,
    # verificato) e -AccessToken (login delegato, verificato) sono entrambi presenti. Un
    # aggiornamento futuro a una versione piu' recente e conflict-free andrebbe verificato allo
    # stesso modo prima di cambiare questo numero, mai per assunzione.
    #
    # Assert-M365OpsExoSafeVersion (Private, aggiunta il 23/08/2026 su richiesta esplicita
    # dell'utente dopo il primo giro di questo fix: "se e' installata la 3.10 allora la
    # disinstalla e mette la 3.9") non si limita a installare la 3.9.0 se manca - disinstalla
    # ATTIVAMENTE qualunque versione >= 3.10.0 gia' presente sul disco, invece di lasciarla li'
    # accanto. Il pin -RequiredVersion qui sotto protegge gia' QUESTO progetto da solo, ma una
    # versione in conflitto lasciata sul disco resta un rischio per qualunque altro
    # script/Import-Module senza pin esplicito.
    $script:M365OpsExoSafeVersion = '3.9.0'
    Assert-M365OpsExoSafeVersion
    Import-Module ExchangeOnlineManagement -RequiredVersion $script:M365OpsExoSafeVersion -ErrorAction Stop
    $script:M365OpsExchangeModuleImported = $true

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        if (-not $script:M365OpsContext.DelegatedUpn) {
            throw "Il profilo '$($script:M365OpsContext.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
        }
        # Login interattivo con l'utenza reale - usa i ruoli admin delegati gia' assegnati a
        # quell'utente su questo tenant, nessuna App Registration necessaria. Arriva qui SOLO
        # se -AllowInteractive e' stato passato esplicitamente (vedi sopra).
        # -Device (device code, non un popup): il server gira come processo in background,
        # senza una sessione desktop interattiva propria - un popup non avrebbe dove
        # comparire e la chiamata resterebbe bloccata all'infinito senza che nessuno se ne
        # accorga (esattamente l'incidente di sezione 10.6, seconda occorrenza). Il device
        # code invece stampa sempre un codice+URL utilizzabile da QUALSIASI browser, e scade
        # da solo dopo un tempo limitato invece di restare appeso per sempre.
        Connect-ExchangeOnline -UserPrincipalName $script:M365OpsContext.DelegatedUpn -Device -ShowBanner:$false
        $script:M365OpsExchangeConnected = $true
        return
    }

    if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
        throw "Il profilo '$($script:M365OpsContext.Name)' non ha un ExchangeCertThumbprint configurato. Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarlo."
    }

    Connect-ExchangeOnline `
        -AppId $script:M365OpsContext.ClientId `
        -CertificateThumbprint $script:M365OpsContext.ExchangeCertThumbprint `
        -Organization $script:M365OpsContext.TenantId `
        -ShowBanner:$false

    $script:M365OpsExchangeConnected = $true
}
