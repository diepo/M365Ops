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
        throw "Sessione Teams non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab Tenant (non MCP/Connettori), sezione 'Stato connessioni', Microsoft Teams, e clicca 'Connetti / Test connessione Teams' per farlo esplicitamente (si apre una finestra per il codice, il server resta bloccato per tutti finche' non completi il login - fallo PRIMA di chiedere dati in chat, mai durante una richiesta composta)."
    }

    if (-not (Get-Module -ListAvailable -Name MicrosoftTeams)) {
        Write-Host "Modulo MicrosoftTeams non trovato, lo installo..." -ForegroundColor Yellow
        Install-Module MicrosoftTeams -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module MicrosoftTeams -ErrorAction Stop

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
        Connect-MicrosoftTeams -TenantId $script:M365OpsContext.TenantId -ErrorAction Stop
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
