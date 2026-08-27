function Connect-M365OpsCliMicrosoft365 {
    <#
    .SYNOPSIS
        Sincronizza l'autenticazione di CLI Microsoft 365 (npm @pnp/cli-microsoft365) col
        tenant M365Ops attivo, PRIMA che il suo server MCP possa essere usato in sicurezza.
        Chiamata automaticamente da Connect-M365OpsMcpServer quando il server e'
        'CLI-Microsoft365' - non richiamarla direttamente salvo test.

        PERCHE' SERVE (26/08/2026, valutazione richiesta esplicitamente dall'utente su
        pnp.github.io/cli-microsoft365): a differenza di Lokka (client credentials passate
        come env var al sottoprocesso, isolate per singola connessione), CLI Microsoft 365 si
        autentica con un comando 'm365 login' SEPARATO il cui stato persiste in un file di
        configurazione CLI condiviso per l'intero utente Windows, non per singola sessione -
        il server MCP stesso non fa mai login di sua iniziativa (lo dice la sua stessa
        documentazione). Login multipli restano salvati come "connessioni" nominate
        (m365 connection list/use), ma senza una sincronizzazione esplicita ad ogni cambio
        tenant M365Ops rischieremmo esattamente la stessa classe di bug gia' trovata e
        corretta due volte in questa sessione per Intune/Exchange: uno stato di sessione del
        tenant PRECEDENTE che sopravvive per sbaglio al cambio profilo.

        Il nome della connessione CLI M365 usato qui e' sempre il nome del profilo tenant
        M365Ops attivo ($script:M365OpsContext.Name, passato a 'm365 login' con
        --connectionName) - una corrispondenza 1:1 stabile, cosi' "esiste gia' una
        connessione per QUESTO profilo" e' una domanda con una risposta univoca, mai ambigua
        tra piu' tenant con lo stesso TenantId (es. un profilo AppOnly e uno Delegato sullo
        stesso tenant, gia' un caso reale in questo progetto - vedi "vnsys-test"/"vnsys
        delegata").

    .NOTES
        AUTENTICAZIONE A CERTIFICATO (27/08/2026, implementata dopo aver verificato dal vivo
        quanto sotto era solo un'ipotesi non confermata): 'm365 login --help' (CLI installata,
        v11.10.0) conferma che --thumbprint da solo NON basta a referenziare un certificato
        gia' installato nel certificate store di Windows - e' calcolato automaticamente DAL
        certificato fornito, non un modo per puntarne uno esistente. Serve quindi
        --certificateFile o --certificateBase64Encoded (il CONTENUTO del certificato, non solo
        il thumbprint) - stesso limite gia' sospettato ma non verificato in una versione
        precedente di questa funzione. Verificato inoltre dal vivo (autorizzazione esplicita
        dell'utente, trattandosi di materiale di chiave privata) che il certificato gia'
        configurato per Exchange su questo progetto (ExchangeCertThumbprint) HA la chiave
        privata esportabile - non scontato, molti certificati di produzione la marcano non
        esportabile per scelta. Implementato quindi: il certificato viene esportato in formato
        PFX **in memoria** (mai scritto su disco) con una password casuale generata per
        l'occasione (GUID, mai persistita, scartata subito dopo l'uso), poi codificato in
        base64 e passato a --certificateBase64Encoded/--password - stesso principio gia'
        accettato in questo progetto per --secret qui sotto (pattern di automazione
        documentato ufficialmente da CLI Microsoft 365 per questo scenario, nessuna
        alternativa esposta dal tool MCP). Se l'export fallisce (chiave non esportabile),
        l'errore lo dice chiaramente invece di un fallimento criptico piu' avanti.

        PRIORITA' certificato > secret quando ENTRAMBI sono configurati: il certificato copre
        esattamente lo stesso dominio del secret (Entra/Outlook/Planner, verificato) PIU'
        SharePoint (che il secret non copre mai, vedi limite sotto) - e' quindi strettamente
        preferibile quando disponibile, nessun motivo per restare sul secret in quel caso. Un
        profilo AppOnly senza ne' ExchangeCertThumbprint ne' SecretEnvVar configurati non e'
        supportato da questa funzione - lancia un errore chiaro invece di un tentativo
        instabile.

        Tenant Delegato (aggiunto il 26/08/2026, dopo un primo giro che lo escludeva del
        tutto): 'm365 login --authType browser' apre un vero browser di sistema e BLOCCA il
        comando finche' l'utente non completa il login - nessun flusso a due passi come
        Start-/Complete-M365OpsExchangeDelegatedLogin esposto dalla CLI. Non e' pero' un
        motivo per escluderlo: e' esattamente lo stesso identico limite gia' accettato in
        questo progetto per Teams/SharePoint/Intune su tenant Delegati (login interattivo
        bloccante, gestito dietro un parametro -AllowInteractive esplicito e un click
        consapevole dell'utente in GUI, mai dentro un flusso composto automatico che
        bloccherebbe il server senza preavviso). '--authType deviceCode' esiste anch'esso ma
        e' ANCH'ESSO bloccante sulla CLI (nessun flusso a due passi neanche li') - scelto
        browser sui due perche' e' l'esperienza gia' familiare all'utente per Teams/
        SharePoint/Intune, non per una differenza tecnica reale tra i due.

        LIMITE REALE scoperto testando dal vivo (26/08/2026, non documentato da nessuna
        parte prima di provarlo): con '--authType secret' i comandi del gruppo 'spo'
        (SharePoint) falliscono SEMPRE con "SharePoint does not support authentication using
        client ID and secret. Please use a different login type to use SharePoint commands."
        - verificato su 'm365 spo site list' con una connessione secret gia' autenticata e
        funzionante su Entra/Graph (stesso identico login, comandi diversi). Le altre aree
        (Entra, Outlook, Planner, verificate dal vivo con dati reali) funzionano correttamente
        con secret. RISOLTO il 27/08/2026 per i profili con un certificato configurato (vedi
        sopra): 'spo' via CLI Microsoft 365 funziona con --authType certificate, resta invece
        limitato al solo secret (quindi senza 'spo') per i profili senza alcun certificato
        configurato. Documentato anche nel system prompt dello strumento
        (Invoke-M365OpsAgentTools.ps1), che ora distingue i due casi invece di escludere
        sempre 'spo' su CLI365.
    #>
    param([switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    $mcpServerName = 'CLI-Microsoft365'
    $tenantName = $script:M365OpsContext.Name
    # Dizionario a due livelli, tenant poi nome server (26/08/2026, isolamento per tenant -
    # vedi Connect-M365OpsMcpServer.ps1), non piu' un solo livello per nome condiviso.
    $process = if ($script:M365OpsMcpProcesses -and $script:M365OpsMcpProcesses[$tenantName]) { $script:M365OpsMcpProcesses[$tenantName][$mcpServerName] } else { $null }
    if (-not $process -or $process.HasExited) {
        throw "Il processo del server MCP '$mcpServerName' non risulta attivo - questa funzione va chiamata solo da Connect-M365OpsMcpServer, a processo gia' avviato."
    }

    $connectionName = $script:M365OpsContext.Name

    # Interrogato DIRETTAMENTE sul processo gia' avviato (non tramite
    # Invoke-M365OpsMcpServerTool, che richiamerebbe ricorsivamente Connect-M365OpsMcpServer,
    # quindi di nuovo questa stessa funzione, se per qualunque motivo il processo non
    # risultasse ancora tracciato).
    $listResult = Invoke-M365OpsMcpRequest -Process $process -Method "tools/call" -Params @{
        name      = "m365_run_command"
        arguments = @{ command = "m365 connection list --output json" }
    }
    $listText = ($listResult.content | ForEach-Object { $_.text }) -join "`n"
    $connections = @()
    try { $connections = @($listText | ConvertFrom-Json -ErrorAction Stop) } catch { $connections = @() }

    # Verificato dal vivo il 26/08/2026 (non per assunzione dalla documentazione, che non lo
    # confermava): 'connection list --output json' restituisce il nome della connessione nel
    # campo 'name' (es. [{"name":"vnsys-test","connectedAs":"...","authType":"secret",
    # "active":true}]), NON 'connectionName' come invece fa l'output di 'login' - controllati
    # comunque entrambi i nomi per sicurezza, nel caso una versione futura della CLI cambi
    # convenzione.
    $existingConnection = $connections | Where-Object { $_.connectionName -eq $connectionName -or $_.name -eq $connectionName } | Select-Object -First 1

    if ($existingConnection) {
        Invoke-M365OpsMcpRequest -Process $process -Method "tools/call" -Params @{
            name      = "m365_run_command"
            arguments = @{ command = "m365 connection use --name `"$connectionName`"" }
        } | Out-Null
        Write-Host "CLI Microsoft 365: connessione esistente '$connectionName' attivata." -ForegroundColor Green
        return
    }

    # Nessuna connessione salvata per questo profilo - primo login.
    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        if (-not $AllowInteractive) {
            throw "Sessione CLI Microsoft 365 non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab MCP/Connettori (o Tenant, sezione Purview/CLI Microsoft 365) e clicca 'Connetti CLI Microsoft 365' per farlo esplicitamente, poi riprova."
        }
        # 'm365 login --authType browser' apre un vero browser di sistema e BLOCCA questo
        # comando finche' l'utente non completa il login - arriva qui SOLO con
        # -AllowInteractive esplicito (vedi sopra), stesso principio gia' usato per Teams/
        # SharePoint/Intune: un click diretto e consapevole dell'utente, mai dentro un flusso
        # composto automatico.
        #
        # BUG URGENTE trovato dal vivo il 23/08/2026 (segnalato in diretta dall'utente su un
        # tenant Delegato reale, "AlePiras"): l'assunzione originale qui sopra - che
        # '--authType browser' usasse un client pubblico integrato senza bisogno di --appId -
        # era corretta su versioni piu' vecchie della CLI ma NON lo e' piu' sulla versione
        # installata su questo PC (CLI for Microsoft 365 v11.10.0, verificato con
        # 'm365 login --help': "--appId ... This option is crucial and should be specified if
        # it isn't defined elsewhere"). Senza --appId, il comando entra in un prompt
        # INTERATTIVO ("? appId:") in attesa di input da tastiera - invisibile e irrecuperabile
        # in questo contesto (stdio e' il canale JSON-RPC verso il server MCP, non un vero
        # terminale), esattamente la stessa classe di bug gia' vista e corretta il 21/08/2026 su
        # Connect-M365OpsTeams (-UseDeviceAuthentication che stampava su una console nascosta) -
        # il server restava bloccato per sempre in attesa di una risposta che non poteva mai
        # arrivare, MAI un browser si apriva davvero. Corretto passando esplicitamente lo stesso
        # client pubblico multi-tenant di Microsoft "Microsoft Graph Command Line Tools" gia'
        # usato per il device-code Graph in questo stesso progetto (vedi
        # Invoke-M365OpsDeviceCodeFlow.ps1, $script:M365OpsDeviceCodeClientId) - un'app Microsoft
        # di primissima parte, presente per default in ogni tenant, nessuna App Registration
        # dedicata da creare. Verificato dal vivo (23/08/2026): con questo appId il comando
        # procede subito a "To sign in, use the web browser that just has been opened", nessun
        # prompt interattivo.
        $loginCommand = "m365 login --authType browser --appId `"$script:M365OpsDeviceCodeClientId`" --tenant `"$($script:M365OpsContext.TenantId)`" --connectionName `"$connectionName`" --output json"
    }
    elseif ($script:M365OpsContext.ExchangeCertThumbprint) {
        # Certificato preferito al secret quando disponibile (vedi .NOTES: copre lo stesso
        # dominio PIU' SharePoint). Stesso lookup a due store gia' usato ovunque nel progetto
        # per questo stesso certificato (Connect-M365OpsExchange/Teams/SharePoint/Intune,
        # New-M365OpsCertificateAssertion.ps1).
        $thumbprint = $script:M365OpsContext.ExchangeCertThumbprint
        $cert = Get-Item "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
        if (-not $cert) { $cert = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue }
        if (-not $cert) {
            throw "Certificato con thumbprint '$thumbprint' non trovato ne' in Cert:\CurrentUser\My ne' in Cert:\LocalMachine\My - stesso certificato gia' usato per Exchange deve essere installato su questo PC."
        }
        if (-not $cert.HasPrivateKey) {
            throw "Il certificato con thumbprint '$thumbprint' non ha una chiave privata su questo PC - impossibile usarlo per il login CLI Microsoft 365."
        }

        # Password casuale generata SOLO per questo export in memoria - un GUID (solo caratteri
        # esadecimali, nessuno speciale da fare l'escape quando finisce dentro la stringa di
        # comando passata al tool MCP) mai persistita, scartata subito dopo l'uso. Il PFX
        # risultante resta SEMPRE in memoria (array di byte -> base64), MAI scritto su disco -
        # a differenza di un file temporaneo, non c'e' nulla da ripulire ne' rischio che resti
        # li' per sbaglio.
        $pfxPassword = [guid]::NewGuid().ToString('N')
        $securePfxPassword = ConvertTo-SecureString -String $pfxPassword -AsPlainText -Force
        try {
            $pfxBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $securePfxPassword)
        } catch {
            throw "Impossibile esportare la chiave privata del certificato '$thumbprint' (verificato dal vivo il 27/08/2026 su un certificato di test: non tutti i certificati la consentono, dipende da come e' stato marcato all'importazione) - CLI Microsoft 365 richiede il contenuto del certificato, non solo il thumbprint (vedi .NOTES). Errore originale: $($_.Exception.Message)"
        }
        $pfxBase64 = [Convert]::ToBase64String($pfxBytes)

        # NOTA: stesso principio gia' accettato in questo progetto per --secret sotto - il
        # contenuto del certificato e la sua password transitano come argomenti verso il
        # processo figlio (nessuna alternativa esposta dal tool MCP), visibili solo per
        # l'istante di avvio del processo, mai scritti su disco.
        $loginCommand = "m365 login --authType certificate --certificateBase64Encoded `"$pfxBase64`" --password `"$pfxPassword`" --appId `"$($script:M365OpsContext.ClientId)`" --tenant `"$($script:M365OpsContext.TenantId)`" --connectionName `"$connectionName`" --output json"
    }
    else {
        if (-not $script:M365OpsContext.SecretEnvVar) {
            throw "CLI Microsoft 365 richiede un client secret o un certificato configurato per questo profilo ('$connectionName'). Usa Set-M365OpsTenant -SecretEnvVar o -ExchangeCertThumbprint per impostarne uno, oppure non collegare questo server MCP su questo profilo."
        }
        $secret = Get-M365OpsSecret -Name $script:M365OpsContext.SecretEnvVar
        if (-not $secret) { throw "Secret del tenant ('$($script:M365OpsContext.SecretEnvVar)') non trovato." }

        # NOTA: il secret transita come argomento di riga di comando verso il processo figlio
        # avviato dal server MCP (npx @pnp/cli-microsoft365-mcp-server, che a sua volta invoca
        # 'm365') - e' il pattern di automazione DOCUMENTATO ufficialmente da CLI Microsoft 365
        # per questo scenario (nessuna alternativa a env var esposta dal tool MCP, a differenza
        # di Lokka), quindi non una scelta nostra evitabile - il secret e' comunque visibile solo
        # per l'istante di avvio del processo, non scritto mai su disco.
        $loginCommand = "m365 login --authType secret --secret `"$secret`" --appId `"$($script:M365OpsContext.ClientId)`" --tenant `"$($script:M365OpsContext.TenantId)`" --connectionName `"$connectionName`" --output json"
    }
    $loginResult = Invoke-M365OpsMcpRequest -Process $process -Method "tools/call" -Params @{
        name      = "m365_run_command"
        arguments = @{ command = $loginCommand }
    }
    $loginText = ($loginResult.content | ForEach-Object { $_.text }) -join "`n"
    $loginParsed = $null
    try { $loginParsed = $loginText | ConvertFrom-Json -ErrorAction Stop } catch { }

    if (-not $loginParsed -or (-not $loginParsed.connectionName -and -not $loginParsed.connectedAs)) {
        # Errore reale trovato dal vivo il 26/08/2026 mentre si verificava questa funzione
        # attraverso il server GUI vero (non solo con un test PowerShell isolato, che invece
        # aveva funzionato): "'m365' is not recognized as an internal or external command" -
        # il pacchetto @pnp/cli-microsoft365-mcp-server RICHIEDE @pnp/cli-microsoft365
        # installato GLOBALMENTE (npm i -g @pnp/cli-microsoft365, vedi guida) per funzionare
        # - senza, ogni comando fallisce cosi'. Causa distinta pero' anche quando il pacchetto
        # E' gia' installato: su Windows, "npm install -g" aggiorna il PATH utente a livello
        # di registro, ma un processo GIA' IN ESECUZIONE (incluso il server M365Ops stesso,
        # se era gia' avviato prima dell'installazione) mantiene la propria copia del PATH
        # letta all'avvio - non se ne accorge finche' non viene riavviato per davvero (nuovo
        # processo, non solo "Riavvia server" se anche QUELLO discende da una shell/processo
        # avviato prima dell'installazione - serve chiudere tutto e ripartire da capo, es.
        # dal collegamento sul Desktop). Intercettato qui con un messaggio azionabile invece
        # del criptico errore della shell.
        if ($loginText -match "'?m365'? is not recognized|is not recognized as an internal or external command") {
            throw "CLI Microsoft 365 (comando 'm365') non risulta installato o non e' visibile a questo processo. Verifica: (1) hai eseguito 'npm install -g @pnp/cli-microsoft365' su questo PC? (2) se si', hai riavviato DAVVERO tutto (chiudi ogni finestra/terminale e riapri dal collegamento M365Ops sul Desktop, non basta il pulsante 'Riavvia server' se il processo attuale e' partito prima dell'installazione) - su Windows un programma npm installato globalmente non diventa visibile a un processo gia' in esecuzione."
        }
        throw "Login CLI Microsoft 365 fallito per il profilo '$connectionName': $loginText"
    }

    Write-Host "CLI Microsoft 365: nuovo login completato per '$connectionName' (connesso come $($loginParsed.connectedAs))." -ForegroundColor Green
}
