function Get-M365OpsAppPermissionsCheck {
    <#
    .SYNOPSIS
        Verifica quali permessi sono REALMENTE concessi (con consenso admin) all'App
        Registration del tenant App-only attivo, interrogando Microsoft Graph invece di
        fidarsi di cosa "dovrebbe" essere stato configurato - e li traduce in una tabella
        per AREA funzionale (Intune, Entra ID, Teams, SharePoint, Exchange...) con stato
        lettura/scrittura, cosi' un problema di permessi si vede PRIMA di incontrarlo come
        errore durante un'operazione reale (21/08/2026, richiesto esplicitamente dall'utente:
        "vorrei fare una sezione check permessi app... l'interfaccia scrive all'utente se
        puo' usare Teams, SharePoint, Exchange etc, in lettura o anche in scrittura").
    .OUTPUTS
        Un array di pscustomobject, uno per area: Area, Resource, Status
        ('nessun accesso'/'lettura'/'lettura+scrittura'), MissingForRead, MissingForWrite,
        Note (facoltativa, spiegazione/avvertenza).
    .NOTES
        Quattro "aree di concessione" Microsoft DISTINTE, non solo Microsoft Graph, ognuna
        con un proprio "Grant admin consent" separato nel portale Entra ID: Microsoft Graph,
        "Office 365 Exchange Online" (Exchange.ManageAsApp, sezione 4.1/6), "SharePoint
        Online" (Sites.FullControl.All, sezione 4.3) e "Skype and Teams Tenant Admin API"
        (solo per i cmdlet di POLICY Teams, sezione 4.4). Verificabile SOLO controllando le
        app role assignment REALI del service principal (GET .../appRoleAssignments), non un
        elenco statico - un permesso "aggiunto" in Entra ID ma senza Grant admin consent non
        compare qui, esattamente come nella realta' non funziona.
        Teams e SharePoint "di base" (via i moduli MicrosoftTeams/PnP, non via queste API)
        NON dipendono da nessuno di questi permessi: funzionano gia' con lo stesso
        certificato/secret usato per l'autenticazione stessa (verificato dal vivo il
        17/08/2026, vedi Connect-M365OpsTeams) - segnalati qui come tali, non come "permesso
        mancante" quando l'app ha comunque una credenziale funzionante.
        Il livello RBAC REALE di Exchange Online (quali cmdlet funzionano davvero, sezione 6
        della guida) dipende anche dal ruolo assegnato al service principal DENTRO Exchange -
        non verificabile da qui senza una connessione Exchange live: questa funzione verifica
        solo se l'autenticazione verso Exchange Online e' abilitata (Exchange.ManageAsApp).
    #>
    param()

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $ctx = $script:M365OpsContext
    if ($ctx.AuthMode -eq 'Delegated') {
        throw "Il check permessi si applica solo ai tenant App-only: su un tenant Delegato non esiste un'App Registration da verificare, l'accesso dipende dal ruolo Entra ID dell'utente con cui hai fatto login."
    }

    $spResp = Invoke-M365OpsGraphRequest -Method GET -Path "/servicePrincipals?`$filter=appId eq '$($ctx.ClientId)'"
    $sp = $spResp.value | Select-Object -First 1
    if (-not $sp) {
        throw "Nessun service principal trovato in Entra ID per l'AppId '$($ctx.ClientId)' su questo tenant - l'App Registration esiste davvero su QUESTO tenant?"
    }

    $assignments = @()
    $next = "/servicePrincipals/$($sp.id)/appRoleAssignments"
    while ($next) {
        $page = Invoke-M365OpsGraphRequest -Method GET -Path $next
        $assignments += @($page.value)
        $next = if ($page.'@odata.nextLink') { ($page.'@odata.nextLink' -replace '^https://graph\.microsoft\.com/(v1\.0|beta)', '') } else { $null }
    }

    # resourceId -> nome leggibile della risorsa (es. "Microsoft Graph") - gia' incluso
    # nell'assegnazione stessa, nessuna chiamata extra per questo.
    $resourceNames = @{}
    foreach ($a in $assignments) { $resourceNames[$a.resourceId] = $a.resourceDisplayName }

    # Per ogni risorsa distinta con almeno un'assegnazione, risolvi appRoleId -> stringa
    # permesso (es. "Exchange.ManageAsApp") leggendo gli appRoles del service principal DELLA
    # RISORSA - le assegnazioni riportano solo un GUID (appRoleId), mai il nome leggibile.
    $grantedByResource = @{}
    foreach ($resourceId in @($resourceNames.Keys)) {
        $roleDefs = Invoke-M365OpsGraphRequest -Method GET -Path "/servicePrincipals/$resourceId`?`$select=appRoles"
        $roleMap = @{}
        foreach ($r in @($roleDefs.appRoles)) { $roleMap[$r.id] = $r.value }
        $grantedIds = @($assignments | Where-Object { $_.resourceId -eq $resourceId } | ForEach-Object { $_.appRoleId })
        $grantedByResource[$resourceNames[$resourceId]] = @($grantedIds | ForEach-Object { $roleMap[$_] } | Where-Object { $_ })
    }

    function Test-M365OpsPermSubset {
        param($Required, $Granted)
        if (-not $Required -or $Required.Count -eq 0) { return $true }
        foreach ($r in $Required) { if ($Granted -notcontains $r) { return $false } }
        return $true
    }

    # Tabella di mappatura area->permessi, radicata in cio' che il codice REALMENTE chiama
    # (sezioni 4.2/4.3/4.4/6 della guida, gia' verificate dal vivo li' dove annotato) - non
    # un elenco a memoria.
    $areaDefs = @(
        @{ Area = 'Intune (dispositivi, app, configurazioni)'; Resource = 'Microsoft Graph'
           Read = @('DeviceManagementManagedDevices.Read.All')
           Write = @('DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementApps.ReadWrite.All', 'DeviceManagementScripts.ReadWrite.All', 'DeviceManagementServiceConfig.ReadWrite.All', 'DeviceManagementRBAC.ReadWrite.All') }
        @{ Area = 'Entra ID (utenti, gruppi)'; Resource = 'Microsoft Graph'
           Read = @('User.Read.All')
           Write = @('User.ReadWrite.All', 'Group.ReadWrite.All') }
        @{ Area = 'Report (licenze, sign-in log)'; Resource = 'Microsoft Graph'
           Read = @('Organization.Read.All', 'AuditLog.Read.All')
           Write = @() }
        @{ Area = 'MFA (stato e reset metodi)'; Resource = 'Microsoft Graph'
           Read = @('UserAuthenticationMethod.ReadWrite.All')
           Write = @('UserAuthenticationMethod.ReadWrite.All')
           Note = "Un solo scope Graph copre sia lettura sia scrittura per l'MFA - non esiste una versione 'solo lettura' separata." }
        @{ Area = 'Sicurezza / Defender (opzionale)'; Resource = 'Microsoft Graph'
           Read = @('SecurityAlert.Read.All', 'SecurityIncident.Read.All', 'ThreatHunting.Read.All')
           Write = @() }
        @{ Area = 'Teams (report via Graph diretto: elenco Team/canali)'; Resource = 'Microsoft Graph'
           Read = @('Team.ReadBasic.All', 'Channel.ReadBasic.All')
           Write = @() }
        @{ Area = 'SharePoint (lettura diretta via Graph)'; Resource = 'Microsoft Graph'
           Read = @('Sites.Read.All')
           Write = @() }
        # Nome risorsa verificato dal vivo il 21/08/2026 leggendo le assegnazioni REALI di
        # vnsys-test: e' "Office 365 SharePoint Online", NON "SharePoint Online" come si potrebbe
        # supporre dal nome mostrato nel selettore del portale Entra ID ("SharePoint") - un primo
        # tentativo con quel nome produceva sempre "nessun accesso" anche quando il permesso era
        # presente (mismatch di stringa, non un vero permesso mancante), corretto prima di
        # consegnare la funzione.
        @{ Area = 'SharePoint/OneDrive (siti, permessi, storage - via PnP)'; Resource = 'Office 365 SharePoint Online'
           Read = @('Sites.FullControl.All')
           Write = @('Sites.FullControl.All')
           Note = "Sites.FullControl.All e' l'unico permesso usato qui: concede sempre sia lettura sia scrittura insieme, non esiste una versione solo-lettura in questa API separata (sezione 4.3)." }
        @{ Area = 'Exchange Online (mailbox, gruppi distribuzione, mail flow)'; Resource = 'Office 365 Exchange Online'
           Read = @('Exchange.ManageAsApp')
           Write = @('Exchange.ManageAsApp')
           Note = "Concede la CONNESSIONE a Exchange Online. Quali cmdlet funzionano davvero dipende ANCHE dal ruolo RBAC assegnato al service principal dentro Exchange (sezione 6 della guida) - non verificabile da qui senza una connessione Exchange live." }
        # Nome risorsa NON ancora verificato dal vivo (nessun tenant di test ha questo permesso
        # concesso finora, quindi non compare mai nelle assegnazioni reali osservate) - assunto
        # dal nome standard mostrato nel selettore "APIs my organization uses" del portale Entra
        # ID. Se il nome reale differisse, l'unico effetto sarebbe un falso "nessun accesso" anche
        # a permesso concesso (mai un falso positivo) - da confermare la prima volta che un tenant
        # con questo permesso granted sara' disponibile per il test.
        @{ Area = 'Teams - Policy (accesso esterno, criteri)'; Resource = 'Skype and Teams Tenant Admin API'
           Read = @('application_access')
           Write = @('application_access') }
    )

    $results = foreach ($def in $areaDefs) {
        $granted = if ($grantedByResource.ContainsKey($def.Resource)) { $grantedByResource[$def.Resource] } else { @() }
        $readOk = Test-M365OpsPermSubset -Required $def.Read -Granted $granted
        $writeOk = Test-M365OpsPermSubset -Required $def.Write -Granted $granted
        $status = if ($writeOk -and $def.Write.Count -gt 0) { 'lettura+scrittura' }
        elseif ($readOk -and $def.Read.Count -gt 0) { 'lettura' }
        else { 'nessun accesso' }
        [pscustomobject]@{
            Area            = $def.Area
            Resource        = $def.Resource
            Status          = $status
            MissingForRead  = @($def.Read | Where-Object { $granted -notcontains $_ })
            MissingForWrite = @($def.Write | Where-Object { $granted -notcontains $_ })
            Note            = $def.Note
        }
    }

    # Teams "di base" (elenco/canali/membri/modifica) non passa da NESSUno di questi permessi:
    # dipende solo dal certificato/secret gia' verificato per l'autenticazione stessa (vedi
    # Connect-M365OpsTeams) - se siamo arrivati fin qui, quella credenziale funziona gia'.
    $results += [pscustomobject]@{
        Area            = 'Teams (elenco, canali, membri, modifica base)'
        Resource        = "(nessuno - stesso certificato/secret dell'autenticazione)"
        Status          = 'lettura+scrittura'
        MissingForRead  = @()
        MissingForWrite = @()
        Note            = "Non richiede un permesso Graph/API separato: funziona gia' con lo stesso certificato o secret usato per l'autenticazione (verificato dal vivo il 17/08/2026, vedi Connect-M365OpsTeams)."
    }

    return $results
}
