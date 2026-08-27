function Connect-M365Ops {
    <#
    .SYNOPSIS
        Attiva un profilo tenant salvato con Set-M365OpsTenant. Tutte le altre cmdlet del
        modulo operano sul tenant attivo finche' non richiami Connect-M365Ops con un altro nome.

    .EXAMPLE
        Connect-M365Ops -TenantProfile "contoso-test"
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantProfile
    )

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    if (-not (Test-Path $configPath)) {
        throw "Nessun profilo salvato. Usa prima Set-M365OpsTenant."
    }

    $raw = Get-Content $configPath -Raw | ConvertFrom-Json
    $entry = $raw.$TenantProfile
    if (-not $entry) {
        $available = ($raw.PSObject.Properties.Name -join ', ')
        throw "Profilo '$TenantProfile' non trovato. Profili disponibili: $available"
    }

    # Lokka (sottoprocesso), Exchange Online, Teams e SharePoint (tutti remoting implicito o
    # sessioni PnP) sono stato GLOBALE, non parametrizzato per singola chiamata: se non li
    # chiudessimo qui, un comando eseguito dopo il cambio tenant rischierebbe di colpire
    # ancora il tenant precedente. Vanno chiusi esplicitamente ad ogni cambio profilo, mai
    # lasciati sopravvivere - Teams e SharePoint aggiunti il 21/08/2026 (richiesto
    # esplicitamente dall'utente dopo un errore di conflitto assembly .NET passando da un
    # tenant App-only a uno Delegato nello stesso processo server: "Could not load type
    # 'Microsoft.IdentityModel.Telemetry.TelemetryClient'..." - disconnettere le sessioni
    # precedenti PRIMA di aprirne di nuove riduce il rischio che due percorsi di autenticazione
    # diversi (certificato vs interattivo) restino attivi insieme nello stesso processo).
    # NOTA IMPORTANTE, non falsa promessa: un conflitto di VERSIONE di una DLL gia' caricata nel
    # processo .NET non si annulla disconnettendo una sessione - solo un riavvio del processo
    # lo risolve davvero (vedi sezione 6.5 della guida). Questo e' comunque un guardrail utile
    # e corretto di per se' (mai lasciare stato di sessione del tenant precedente attivo), non
    # una soluzione completa al bug dei conflitti assembly.
    # I server MCP (Lokka, CLI-Microsoft365) NON vengono piu' fermati qui dal 26/08/2026
    # (prima si', tramite Disconnect-M365OpsAllMcpServers) - a differenza di
    # Exchange/Teams/SharePoint qui sotto (stato .NET realmente condiviso/globale nel
    # processo, nessun modo di isolarlo per tenant), i sottoprocessi MCP sono ORA isolati per
    # costruzione un processo OS distinto per ogni coppia tenant+server, mai condiviso, vedi
    # Connect-M365OpsMcpServer.ps1 - lasciarli vivi in background quando si cambia tenant
    # permette di tornare su un tenant gia' usato senza rifare login/handshake da capo, senza
    # alcun rischio di stato residuo perche' non c'e' nulla da "residuare": il processo di
    # QUESTO tenant non viene mai toccato da un cambio verso un ALTRO tenant.
    Disconnect-M365OpsExchange
    Disconnect-M365OpsTeams
    Disconnect-M365OpsSharePoint
    # BUG REALE trovato il 27/08/2026 durante l'implementazione di Disconnect-/Connect-
    # M365OpsAllConnections: Compliance (Purview, Connect-IPPSSession) non veniva MAI
    # disconnesso qui, nonostante la sua sessione reale muoia comunque insieme a quella
    # Exchange (Disconnect-ExchangeOnline chiude tutte le sessioni remote del modulo, incluse
    # le IPPS) - il flag $script:M365OpsComplianceConnected restava quindi "vero" anche a
    # sessione gia' morta dopo un cambio tenant, uno stato mentito della stessa classe gia'
    # corretta per Intune (vedi .NOTES di Connect-M365OpsIntune.ps1, verifica dal vivo invece
    # di fidarsi del flag). Aggiunta la chiamata mancante.
    Disconnect-M365OpsCompliance
    # IntuneWin32App non espone un vero "Disconnect" (nessuna sessione da chiudere come
    # Exchange) - resettiamo solo il nostro flag, cosi' Connect-M365OpsIntune richiede di
    # nuovo un connect esplicito (via -AllowInteractive) dopo un cambio tenant, invece di
    # riusare per sbaglio una connessione/cache del profilo precedente.
    $script:M365OpsIntuneConnected = $false
    $script:M365OpsIntuneConnectedAs = $null

    # Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore, audit statico poi
    # verificato leggendo il codice): $script:LastReportPath (valorizzato da
    # generate_report/generate_raw_export/generate_raw_graph_export in
    # Invoke-M365OpsAgentTools.ps1, letto da propose_send_report_email) NON veniva mai
    # resettato qui, a differenza di ogni altro stato per-tenant sopra - la sua descrizione
    # verso l'AI promette esplicitamente "l'ULTIMO report generato IN QUESTA SESSIONE", ma
    # essendo scope di MODULO (non per-tenant) il file restava raggiungibile anche dopo un
    # cambio tenant nello stesso processo server: un report generato per il Tenant A poteva
    # finire allegato a un'email inviata per il Tenant B, se l'operatore cambiava tenant e
    # chiedeva "invia il report" senza rigenerarlo prima - una fuga di dati reali tra tenant,
    # stessa gravita' della classe di bug gia' corretta piu' volte per lo stato Intune/
    # Exchange/Teams/SharePoint qui sopra.
    $script:LastReportPath = $null
    $script:M365OpsLastReportWarnings = $null

    $script:M365OpsContext = @{
        Name                   = $TenantProfile
        TenantId               = $entry.TenantId
        ClientId               = $entry.ClientId
        SecretEnvVar           = $entry.SecretEnvVar
        ExchangeCertThumbprint = $entry.ExchangeCertThumbprint
        EmailSender            = $entry.EmailSender
        AuthMode               = if ($entry.AuthMode) { $entry.AuthMode } else { 'AppOnly' }
        DelegatedUpn           = $entry.DelegatedUpn
        SharePointInteractiveClientId = $entry.SharePointInteractiveClientId
    }
    $script:M365OpsTokenCache.Remove($TenantProfile)

    # Ultimo tenant attivo salvato su file (best-effort, non deve mai bloccare il cambio
    # tenant se il file non e' scrivibile) - usato da Launch-M365Ops.ps1 per far ripartire
    # il server sull'ultimo profilo usato invece che sempre sul default, quando lo si avvia
    # da zero (es. dopo aver chiuso tutto e ricliccato l'icona).
    try {
        $lastTenantFile = Join-Path $script:M365OpsModuleRoot 'Config\last-active-tenant.txt'
        Set-Content -Path $lastTenantFile -Value $TenantProfile -Encoding UTF8 -NoNewline
    } catch {}

    Write-Host "Tenant attivo: $TenantProfile ($($entry.TenantId)) [$($script:M365OpsContext.AuthMode)]" -ForegroundColor Green
}
