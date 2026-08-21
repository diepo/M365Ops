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

    # BUG STRUTTURALE DI TERZE PARTI (22/08/2026), gestito con approcci diversi nel tempo -
    # storia completa perche' il ragionamento conta quanto il codice qui: (1) guardia
    # PREVENTIVA aggiunta il 22/08/2026 ("l'altro modulo e' gia' caricato, blocco a priori");
    # (2) rimossa il 24/08/2026 credendo, su due sole versioni Teams testate, che Teams-poi-
    # Exchange fosse sempre sicuro col pin a 3.9.0 sotto; (3) ripristinata poche ore dopo quando
    # una matrice di test piu' ampia (Teams 7.1.0/7.3.1/7.9.0 x Exchange 2.0.5/3.9.0) ha mostrato
    # che NESSUN ordine e' affidabilmente sicuro - dipende da combinazioni di versione non
    # prevedibili; (4) RIMOSSA DI NUOVO, stavolta in modo definitivo, su richiesta esplicita
    # dell'utente: "non voglio il safe guard, nelle versioni vecchie funzionava in qualunque
    # direzione". Aveva ragione sul principio, non solo sul ricordo specifico: dato che nessun
    # ordine si e' dimostrato ne' sempre sicuro ne' sempre rotto, bloccare A PRIORI un tentativo
    # che su QUESTO PC, con QUESTE versioni installate, magari funzionerebbe benissimo, e' un
    # danno certo per evitare un rischio incerto - l'esatto opposto di quello che vuole l'utente.
    # Il modulo NON viene piu' bloccato prima di provare: si prova sempre, e SOLO se l'eccezione
    # e' davvero quel conflitto specifico (Get-M365OpsModuleConflictHint, Private) viene
    # rivestita con un messaggio leggibile invece del criptico ".NET FileLoadException" nativo -
    # qualunque altro errore (incluso il successo) passa inalterato.
    $script:M365OpsExoSafeVersion = '3.9.0'
    try {
        # Versione FISSATA a 3.9.0, non "l'ultima disponibile": dalla 3.10.0 in poi il conflitto
        # sopra e' SEMPRE presente, in entrambe le direzioni, con ogni versione di Teams testata
        # (riprodotto l'errore esatto originariamente segnalato dall'utente con Teams 7.9.0 +
        # Exchange 3.10.1) - quella soglia e' certa e va sempre evitata, a differenza dell'esito
        # sotto la 3.10.0 che dipende dalla combinazione di versioni. 3.9.0 supporta comunque
        # tutto cio' che serve a questo progetto: -CertificateThumbprint/-Certificate (App-only,
        # verificato) e -AccessToken (login delegato, verificato) sono entrambi presenti.
        # Assert-M365OpsExoSafeVersion (Private) disinstalla anche attivamente una eventuale
        # versione >= 3.10.0 gia' presente sul disco, non solo installa la 3.9.0 se manca.
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
    catch {
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Exchange Online' -OtherService 'Microsoft Teams'
        if ($hint) { throw $hint }
        throw
    }
}
