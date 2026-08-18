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

    # Auto-installazione se manca (es. primo avvio su un PC nuovo) - stesso principio gia'
    # usato per ImportExcel in Export-M365OpsReport, cosi' non serve un prerequisito manuale.
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "Modulo ExchangeOnlineManagement non trovato, lo installo..." -ForegroundColor Yellow
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

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
