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
    # Exchange fosse sempre sicuro col pin a 3.9.0; (3) ripristinata poche ore dopo quando una
    # matrice di test piu' ampia (Teams 7.1.0/7.3.1/7.9.0 x Exchange 2.0.5/3.9.0) ha mostrato che
    # NESSUN ordine era affidabilmente sicuro CON QUELLA VERSIONE - dipendeva da combinazioni di
    # versione non prevedibili; (4) rimossa di nuovo su richiesta esplicita dell'utente ("non
    # voglio il safe guard, nelle versioni vecchie funzionava"), sostituita con un messaggio
    # reattivo (Get-M365OpsModuleConflictHint) invece di un blocco preventivo; (5) FISSATA LA
    # COPPIA GIUSTA il 25/08/2026, dopo che l'utente ha insistito correttamente che "fino
    # all'altro giorno" tutto funzionava - Exchange 3.4.0 + Teams 6.5.0 (Exchange connesso
    # PRIMA) verificata dal vivo come priva del conflitto in ogni flusso del progetto (vedi
    # Assert-M365OpsExoSafeVersion.ps1 per il dettaglio completo di come si e' arrivati a questa
    # coppia). Il try/catch sotto resta comunque come rete di sicurezza per l'ordine inverso o
    # per PC con altre versioni residue - qualunque altro errore (incluso il successo) passa
    # inalterato.
    try {
        # Versione FISSATA a 3.4.0 - vedi Assert-M365OpsExoSafeVersion.ps1 per il dettaglio
        # completo del perche' questa versione specifica (in coppia con MicrosoftTeams 6.5.0,
        # connesso dopo). Dalla 3.10.0 in poi il conflitto e' SEMPRE presente, in entrambe le
        # direzioni, con ogni versione di Teams testata - quella soglia va sempre evitata. 3.4.0
        # supporta tutto cio' che serve a questo progetto: -CertificateThumbprint/-Certificate
        # (App-only), -AccessToken (login delegato device-code) e CertificateThumbprint su
        # Connect-IPPSSession (Purview) - tutti verificati dal vivo.
        # Assert-M365OpsExoSafeVersion (Private) disinstalla anche attivamente una eventuale
        # versione >= 3.10.0 gia' presente sul disco, installa la 3.4.0 se manca, la IMPORTA
        # (i chiamanti non lo fanno piu' separatamente) e ripara da sola un'installazione locale
        # corrotta se ne trova una - vedi quel file per il dettaglio completo.
        # | Out-Null aggiunto il 26/08/2026 (bug reale trovato dal vivo durante un bug-hunt:
        # stesso identico pipeline leak gia' corretto in v0.9.52 dentro
        # Complete-M365OpsExchangeDelegatedLogin.ps1, ma quel fix copriva solo QUELLA chiamata -
        # QUESTA, condivisa da ogni altro chiamante di Connect-M365OpsExchange, restava
        # scoperta) - il pscustomobject restituito da Assert-M365OpsExoSafeVersion, non
        # soppresso, finiva sul pipeline di OGNI funzione che chiama Connect-M365OpsExchange
        # come primo passo (praticamente ogni cmdlet Exchange del progetto), visibile SOLO alla
        # primissima connessione reale di un processo server (le successive fanno return
        # anticipato sopra, quindi non lo riproducono) - riprodotto dal vivo creando una
        # distribution list su un processo server appena avviato: la risposta "Fatto." mostrata
        # all'utente in chat conteneva un array con l'oggetto di diagnostica versione ANCHE
        # insieme al risultato vero della scrittura.
        Assert-M365OpsExoSafeVersion | Out-Null

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
            # Invoke-M365OpsWithExoRepairRetry (Private, 25/08/2026): se questa chiamata fallisce
            # con un errore tipico di installazione ExchangeOnlineManagement danneggiata (non il
            # conflitto Teams, escluso perche' controlla $script:M365OpsTeamsModuleImported da
            # solo), ripara la 3.9.0 da zero e riprova UNA volta - vedi quel file per il dettaglio
            # completo, incluso perche' la verifica non puo' vivere dentro Assert-M365OpsExoSafeVersion.
            Invoke-M365OpsWithExoRepairRetry { Connect-ExchangeOnline -UserPrincipalName $script:M365OpsContext.DelegatedUpn -Device -ShowBanner:$false }
            $script:M365OpsExchangeConnected = $true
            return
        }

        if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
            throw "Il profilo '$($script:M365OpsContext.Name)' non ha un ExchangeCertThumbprint configurato. Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarlo."
        }

        Invoke-M365OpsWithExoRepairRetry {
            Connect-ExchangeOnline `
                -AppId $script:M365OpsContext.ClientId `
                -CertificateThumbprint $script:M365OpsContext.ExchangeCertThumbprint `
                -Organization $script:M365OpsContext.TenantId `
                -ShowBanner:$false
        }

        $script:M365OpsExchangeConnected = $true
    }
    catch {
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Exchange Online' -OtherService 'Microsoft Teams'
        if ($hint) {
            # Isolamento reattivo (26/08/2026, richiesto esplicitamente dall'utente come
            # soluzione DEFINITIVA al conflitto - vedi Connect-M365OpsIsolatedModule.ps1 per
            # l'architettura completa): invece di limitarsi a mostrare il messaggio "riavvia
            # il server", si tenta di far funzionare DAVVERO questa connessione spostandola in
            # un processo separato - solo App-only per ora (un tenant Delegato continua a
            # vedere il messaggio classico, vedi Get-M365OpsIsolatedConnectParams.ps1).
            try {
                Connect-M365OpsIsolatedModule -ModuleType 'Exchange' -ConnectParams (Get-M365OpsIsolatedConnectParams -ModuleType 'Exchange')
                $script:M365OpsExchangeConnected = $true
                Write-M365OpsLog "Exchange Online: conflitto .NET reale rilevato, connessione riuscita tramite isolamento reattivo (processo separato) - nessun riavvio necessario."
                return
            }
            catch {
                # L'isolamento stesso e' fallito (es. tenant Delegato, o un problema distinto
                # nel processo isolato) - il messaggio classico resta la spiegazione piu'
                # utile, non l'errore tecnico dell'isolamento.
                throw $hint
            }
        }
        throw
    }
}
