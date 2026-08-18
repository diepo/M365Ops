function Connect-M365OpsSharePoint {
    <#
    .SYNOPSIS
        Connette a SharePoint Online via PnP.PowerShell. Su AppOnly riusa lo STESSO certificato
        gia' configurato per Exchange (ExchangeCertThumbprint) - nessun secret/certificato nuovo
        da gestire, ma serve un permesso NUOVO sull'App Registration: a differenza di Exchange
        (che usa lo stesso certificato "cosi' com'e'"), SharePoint richiede un consenso separato
        sotto l'API "SharePoint" (non Microsoft Graph) - Application permission
        'Sites.FullControl.All'. Verificato dal vivo il 17/08/2026: l'handshake col certificato
        riesce comunque (nessun errore di autenticazione), ma OGNI chiamata reale fallisce con
        "Unauthorized" finche' quel permesso non e' concesso - vedi sezione 4.3 della guida.
    .NOTES
        Su Delegato usa Connect-PnPOnline -Interactive -PersistLogin. Storia reale (17/08/2026,
        tre bug in sequenza su Fabrikam-Prod prima di arrivare qui):
        1) Un primo tentativo con un client_id "PnP Management Shell" indovinato a memoria
           (device code custom, non bloccante) e' fallito con AADSTS700016 "Application ... was
           not found in the directory" - device code richiede che l'app abbia GIA' un service
           principal nel tenant, e il client_id non era comunque verificato con certezza.
        2) Sostituito con -Interactive (lascia scegliere a PnP il proprio client corretto) -
           fallito con "System.NotSupportedException: Specified method is not supported.",
           anche dopo aver avviato il processo del server con -STA (apartment threading NON era
           la causa reale, ipotesi scartata dopo verifica dal vivo).
        3) Confermato con Get-Job che Connect-PnPOnline -DeviceLogin (nativo di PnP, nessun
           client_id indovinato) NON lancia l'eccezione e resta in attesa come atteso - ma
           essendo un processo server headless (nessuna console interattiva attaccata), il
           codice stampato da -DeviceLogin non e' recuperabile in modo affidabile da qui.
        4) Anche -Interactive da un terminale NORMALE (non il server) falliva IDENTICO, con
           l'avviso "Please specify a valid client id for an Entra ID App Registration" -
           rivelando la causa vera: Microsoft ha ritirato il client pubblico condiviso "PnP
           Management Shell" dal 9 settembre 2024 (Register-PnPManagementShellAccess lo
           conferma con un errore esplicito). Non e' mai stato un problema di questo modulo,
           di STA, o di processo headless - PnP.PowerShell semplicemente non ha piu' un client
           di default utilizzabile, va registrata un'App Registration dedicata per tenant.
        Soluzione definitiva: -ClientId esplicito, letto da
        $script:M365OpsContext.SharePointInteractiveClientId (sezione 17.10 della guida) -
        popolato in automatico da Sync-M365OpsSharePointAppRegistration se l'app
        "M365Ops SharePoint" (creata una tantum con Register-PnPEntraIDAppForInteractiveLogin)
        esiste nel tenant. -PersistLogin resta comunque utile: dopo il primo login riuscito con
        questo client, le connessioni successive non richiedono piu' nessuna UI.
    .PARAMETER SiteUrl
        Se omesso, connette al centro di amministrazione (https://<tenant>-admin.sharepoint.com,
        serve per le operazioni tenant-wide come l'elenco siti). Se specificato, connette a
        QUEL sito (serve per leggerne i permessi/gruppi, che PnP puo' leggere solo con una
        connessione al sito stesso, non dall'admin center).
    #>
    param([string]$SiteUrl, [switch]$Force, [switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    # A differenza di Exchange (una sola sessione condivisa per tutto), qui la connessione e'
    # per URL: cambiare sito (o passare da un sito all'admin center) richiede riconnettersi -
    # la cache ricorda quindi l'ULTIMO SiteUrl connesso, non solo "connesso si/no".
    $targetUrl = if ($SiteUrl) { $SiteUrl } else { Get-M365OpsSharePointAdminUrl }
    if ($script:M365OpsSharePointConnectedUrl -eq $targetUrl -and -not $Force) { return }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated' -and -not $AllowInteractive) {
        throw "Sessione SharePoint non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab Tenant (non MCP/Connettori), sezione 'Stato connessioni', SharePoint / OneDrive, e clicca 'Connetti / Test connessione SharePoint' per farlo esplicitamente (si apre un browser, il server resta bloccato per tutti finche' non completi il login - fallo PRIMA di chiedere un report in chat, mai durante una richiesta composta)."
    }

    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        Write-Host "Modulo PnP.PowerShell non trovato, lo installo..." -ForegroundColor Yellow
        Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module PnP.PowerShell -ErrorAction Stop

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        if (-not $script:M365OpsContext.DelegatedUpn) {
            throw "Il profilo '$($script:M365OpsContext.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
        }
        if (-not $script:M365OpsContext.SharePointInteractiveClientId) {
            # Discovery automatico (17/08/2026, richiesto esplicitamente): prima di arrendersi,
            # prova a scoprire se l'app esiste gia' nel tenant e a salvarne da sola il Client ID -
            # l'utente non deve mai copiare/incollare un GUID a mano se non strettamente necessario.
            $sync = Sync-M365OpsSharePointAppRegistration
            if (-not $sync.Found) {
                throw $sync.Message
            }
        }
        # -ClientId esplicito (vedi NOTES per il perche') + -PersistLogin: dopo il primo login
        # riuscito con questo client, le connessioni successive riusano la cache su disco senza
        # mostrare piu' nessuna UI, nemmeno dal processo server headless.
        Connect-PnPOnline -Url $targetUrl -ClientId $script:M365OpsContext.SharePointInteractiveClientId -Interactive -PersistLogin -ErrorAction Stop
        $script:M365OpsSharePointConnectedUrl = $targetUrl
        return
    }

    if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
        throw "Il profilo '$($script:M365OpsContext.Name)' non ha un ExchangeCertThumbprint configurato (lo stesso certificato serve anche per SharePoint). Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarlo."
    }

    Connect-PnPOnline -Url $targetUrl `
        -ClientId $script:M365OpsContext.ClientId `
        -Thumbprint $script:M365OpsContext.ExchangeCertThumbprint `
        -Tenant $script:M365OpsContext.TenantId `
        -ErrorAction Stop

    $script:M365OpsSharePointConnectedUrl = $targetUrl
}
