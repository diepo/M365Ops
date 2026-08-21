function Connect-M365OpsTeams {
    <#
    .SYNOPSIS
        Connette a Microsoft Teams via il modulo MicrosoftTeams, riusando lo STESSO certificato
        app-only gia' configurato per Exchange (ExchangeCertThumbprint) - nessun secret/
        certificato nuovo da gestire. A differenza di SharePoint, i dati BASE (elenco Team,
        canali, membri: Get-Team/Get-TeamChannel/Get-TeamUser) funzionano SUBITO con questo
        stesso certificato, verificato dal vivo il 17/08/2026 - nessun permesso aggiuntivo
        necessario per quelli. Le cmdlet di POLICY (Get-CsTeams*Policy, configurazione accesso
        esterno) invece falliscono con "Access Denied" finche' non si aggiunge il permesso
        Application 'application_access' sotto l'API "Skype and Teams Tenant Admin API" - vedi
        sezione 4.4 della guida. Una sola connessione copre entrambi i casi: la differenza e'
        solo su QUALI cmdlet funzionano dopo, non su come ci si connette.
    #>
    param([switch]$Force, [switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsTeamsConnected -and -not $Force) { return }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated' -and -not $AllowInteractive) {
        throw "Sessione Teams non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab Tenant (non MCP/Connettori), sezione 'Stato connessioni', Microsoft Teams, e clicca 'Connetti / Test connessione Teams' per farlo esplicitamente (si apre una finestra per il login, il server resta bloccato per tutti finche' non completi il login - fallo PRIMA di chiedere dati in chat, mai durante una richiesta composta). Se sembra che non succeda nulla dopo il click, la finestra di login potrebbe essersi aperta DIETRO il browser invece che in primo piano - controlla con Alt+Tab o la barra delle applicazioni prima di pensare che sia bloccato (bug reale segnalato dal vivo il 22/08/2026)."
    }

    # BUG STRUTTURALE DI TERZE PARTI, trovato il 22/08/2026 - vedi Connect-M365OpsExchange.ps1
    # per la storia completa dei tentativi. Conclusione finale (25/08/2026): fissate ENTRAMBE le
    # versioni dei due moduli come coppia verificata (ExchangeOnlineManagement 3.4.0 +
    # MicrosoftTeams 6.5.0, Exchange connesso PRIMA) - vedi Assert-M365OpsTeamsSafeVersion.ps1 e
    # Assert-M365OpsExoSafeVersion.ps1 per il dettaglio completo di come si e' arrivati a questa
    # coppia specifica. Il try/catch sotto resta comunque come rete di sicurezza per l'ordine
    # inverso (Teams connesso senza Exchange gia' connesso prima) o per PC con altre versioni
    # residue - riveste l'eventuale conflitto con un messaggio chiaro invece del criptico errore
    # .NET nativo (Get-M365OpsModuleConflictHint, Private).
    try {
    # Assert-M365OpsTeamsSafeVersion (Private) disinstalla/reinstalla se danneggiata, installa se
    # mancante, la IMPORTA (i chiamanti non lo fanno piu' separatamente) e imposta
    # $script:M365OpsTeamsModuleImported - stesso pattern di Assert-M365OpsExoSafeVersion.ps1,
    # incluso il controllo di integrita' dei file (non solo la presenza del manifest) aggiunto
    # dopo il bug reale "The given assembly name was invalid" trovato sul lato Exchange.
    Assert-M365OpsTeamsSafeVersion

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        if (-not $script:M365OpsContext.DelegatedUpn) {
            throw "Il profilo '$($script:M365OpsContext.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
        }
        # BUG STRUTTURALE trovato dal vivo il 21/08/2026, segnalato dall'utente (successo DUE
        # volte): -UseDeviceAuthentication stampa il codice dispositivo con Write-Host sulla
        # CONSOLE DEL PROCESSO SERVER, non nella GUI - invisibile e irrecuperabile nell'uso
        # normale dell'app (il launcher avvia il server con finestra nascosta, sezione 17.14/
        # Launch-M365Ops.ps1). L'utente vedeva solo "login in corso" bloccato per sempre, senza
        # nessun popup ne' codice da nessuna parte (comportamento CORRETTO per un device-code
        # flow, che non apre mai un browser da solo - il problema e' che il codice stesso non
        # arrivava mai all'utente). A differenza di Exchange/Graph (sezioni 6.5/10, che hanno un
        # vero flusso non bloccante start/poll con codice mostrato in GUI), il modulo
        # MicrosoftTeams non espone cmdlet separati per "inizia" e "completa" un device code -
        # Connect-MicrosoftTeams -UseDeviceAuthentication e' un'unica chiamata atomica bloccante,
        # non costruibile come start/poll senza intercettare la sua console (fragile). Corretto
        # rimuovendo -UseDeviceAuthentication: senza, il modulo usa il proprio flusso interattivo
        # di default (popup browser reale, come gia' visto funzionare per SharePoint via
        # Connect-PnPOnline -Interactive) - il motivo per cui -UseDeviceAuthentication era stato
        # scelto in origine (lasciare al modulo la scelta del proprio client_id interno corretto,
        # per evitare un client_id indovinato a memoria, bug reale gia' visto su SharePoint) resta
        # valido: e' una proprieta' del modulo stesso, non del parametro -UseDeviceAuthentication
        # specificamente - il modulo sceglie il client corretto in ENTRAMBI i flussi.
        # BUG STRUTTURALE reale, causa vera trovata il 22/08/2026 dopo che l'utente ha
        # confermato dal vivo il blocco completo (persino il tab Log smetteva di rispondere,
        # confermando un vero blocco a thread singolo, non solo un rallentamento) e ha
        # suggerito di confrontare con Intune, che funziona: dal modulo MicrosoftTeams
        # v7.8.1-preview (giugno 2026), Connect-MicrosoftTeams usa di DEFAULT Web Account
        # Manager (WAM) come broker di autenticazione su Windows per il login interattivo -
        # verificato su Microsoft Learn, non a memoria. WAM richiede una sessione Windows
        # interattiva con una UI reale a cui agganciarsi; in un contesto "RunAs"/senza
        # finestra visibile come questo server (avviato con -WindowStyle Hidden da
        # Launch-M365Ops.ps1), WAM non ha dove mostrare la propria interfaccia e la chiamata
        # resta bloccata per sempre in attesa di una risposta che non arrivera' mai - stessa
        # classe di bug del device-code (sezione 17.14), causa diversa e piu' recente (WAM e'
        # diventato default DOPO che quel primo fix era stato scritto, il modulo si e'
        # aggiornato sotto silenzio). Corretto con -DisableWAM (switch ufficiale del modulo,
        # introdotto proprio in v7.8.1-preview "per scenari come contesti RunAs dove WAM non
        # e' supportato" - la descrizione ufficiale Microsoft corrisponde esattamente a questo
        # caso) - forza il modulo a tornare al flusso browser+redirect precedente, lo stesso
        # gia' funzionante per SharePoint/PnP.
        #
        # -DisableWAM esiste SOLO da 7.8.1-preview in poi (verificato: su questa stessa
        # macchina di sviluppo il modulo installato e' ancora 7.3.1, dove quel parametro non
        # esiste affatto - passarlo comunque avrebbe rotto QUEL caso con un errore di
        # parameter binding, un bug diverso ma reale che avrei introdotto io stesso).
        # Controllato dinamicamente invece di assumere una versione minima.
        $teamsModuleVersion = (Get-Module -Name MicrosoftTeams).Version
        $connectTeamsParams = @{ TenantId = $script:M365OpsContext.TenantId; ErrorAction = 'Stop' }
        $supportsDisableWam = $teamsModuleVersion -and $teamsModuleVersion -ge [version]'7.8.1'
        if ($supportsDisableWam) { $connectTeamsParams.DisableWAM = $true }
        Write-M365OpsLog "Connect-MicrosoftTeams (delegato, interattivo, modulo v$teamsModuleVersion, DisableWAM=$supportsDisableWam) avviato - in attesa del popup di login..."
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Connect-MicrosoftTeams @connectTeamsParams
        } catch {
            Write-M365OpsLog "Connect-MicrosoftTeams (delegato) FALLITO dopo $([int]$sw.Elapsed.TotalSeconds)s: $($_.Exception.Message)" -Level Error
            throw
        }
        Write-M365OpsLog "Connect-MicrosoftTeams (delegato) completato con successo in $([int]$sw.Elapsed.TotalSeconds)s."
        $script:M365OpsTeamsConnected = $true
        return
    }

    if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
        throw "Il profilo '$($script:M365OpsContext.Name)' non ha un ExchangeCertThumbprint configurato (lo stesso certificato serve anche per Teams). Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarlo."
    }

    Connect-MicrosoftTeams `
        -ApplicationId $script:M365OpsContext.ClientId `
        -Certificate $script:M365OpsContext.ExchangeCertThumbprint `
        -TenantId $script:M365OpsContext.TenantId `
        -ErrorAction Stop

    $script:M365OpsTeamsConnected = $true
    }
    catch {
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Microsoft Teams' -OtherService 'Exchange Online'
        if ($hint) { throw $hint }
        throw
    }
}
