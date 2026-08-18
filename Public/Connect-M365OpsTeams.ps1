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
        # -UseDeviceAuthentication stampa il codice e BLOCCA il thread finche' l'utente non
        # completa il login - accettabile solo perche' arriva qui SOLO con -AllowInteractive
        # esplicito, da un click dedicato in GUI (vedi /api/teams-test), stesso principio gia'
        # usato per Intune e (dal 17/08/2026) per SharePoint. Bug reale evitato qui: la prima
        # versione usava un client_id "Skype and Teams Tenant Admin API" indovinato a memoria
        # per un flusso a codice dispositivo custom (Start-/Complete-M365OpsTeamsDelegatedLogin,
        # ora rimossi) - lo stesso errore (client_id indovinato) e' risultato REALE e verificato
        # su SharePoint (AADSTS700016), quindi rimosso anche qui prima di scoprirlo nello stesso
        # modo: -UseDeviceAuthentication lascia scegliere al modulo MicrosoftTeams il proprio
        # client interno corretto, invece di indovinarlo.
        Connect-MicrosoftTeams -TenantId $script:M365OpsContext.TenantId -UseDeviceAuthentication -ErrorAction Stop
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
