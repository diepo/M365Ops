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
        Limite noto, dichiarato esplicitamente invece di tentare un percorso instabile:
        verificato su pnp.github.io/cli-microsoft365/cmd/login che 'm365 login --authType
        certificate' accetta --certificateFile o --certificateBase64Encoded (il CONTENUTO del
        certificato) - esiste anche un flag --thumbprint, ma la documentazione non chiarisce
        se da solo basti a referenziare un certificato gia' installato nel certificate store
        di Windows (il meccanismo usato ovunque in M365Ops per Exchange/Teams/SharePoint/
        Intune, vedi ExchangeCertThumbprint) o se serva comunque insieme al file/base64.
        Esportare automaticamente la chiave privata da un certificato gia' installato
        richiederebbe gestire una passphrase aggiuntiva per il .pfx esportato - un nuovo
        materiale segreto da introdurre solo per questo, non ancora giustificato senza aver
        prima verificato dal vivo il comportamento di --thumbprint da solo. Per questo, un
        profilo AppOnly SOLO a certificato (senza SecretEnvVar) non e' supportato da questa
        funzione - lancia un errore chiaro invece di un tentativo instabile. Un profilo
        AppOnly CON un SecretEnvVar configurato usa invece '--authType secret' (riusa lo
        stesso identico secret gia' usato per Lokka/Exchange/Graph, nessuna configurazione
        aggiuntiva).

        Tenant Delegato: non ancora supportato (vedi corpo della funzione) - 'm365 login
        --authType deviceCode' e' bloccante (nessun flusso a due passi come
        Start-/Complete-M365OpsExchangeDelegatedLogin esposto dalla CLI), da implementare in
        un giro successivo se serve davvero su tenant Delegati.

        LIMITE REALE scoperto testando dal vivo (26/08/2026, non documentato da nessuna
        parte prima di provarlo): con '--authType secret' i comandi del gruppo 'spo'
        (SharePoint) falliscono SEMPRE con "SharePoint does not support authentication using
        client ID and secret. Please use a different login type to use SharePoint commands."
        - verificato su 'm365 spo site list' con una connessione secret gia' autenticata e
        funzionante su Entra/Graph (stesso identico login, comandi diversi). Le altre aree
        (Entra, Outlook, Planner, verificate dal vivo con dati reali) funzionano correttamente
        con secret - SharePoint via CLI Microsoft 365 resta quindi utilizzabile SOLO su
        tenant configurati con login a certificato, non ancora supportato da questa funzione
        (vedi limite sopra). Documentato anche nel system prompt dello strumento
        (Invoke-M365OpsAgentTools.ps1) cosi' l'AI non propone comandi 'spo' su un tenant con
        solo secret configurato aspettandosi che funzionino.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    $mcpServerName = 'CLI-Microsoft365'
    $process = $script:M365OpsMcpProcesses[$mcpServerName]
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
        # 'm365 login --authType deviceCode' BLOCCA il comando finche' l'utente non completa
        # il login (nessun flusso a due passi come per Exchange/Graph e' esposto dalla CLI
        # stessa) - non implementato per ora, accettabile solo dietro un click esplicito
        # dell'utente in GUI, mai dentro un flusso composto automatico.
        throw "CLI Microsoft 365 su un tenant Delegato richiede un primo login interattivo (codice dispositivo) non ancora implementato in questa funzione - per ora disponibile solo su tenant App-only con un client secret configurato."
    }

    if (-not $script:M365OpsContext.SecretEnvVar) {
        throw "CLI Microsoft 365 richiede un client secret configurato per questo profilo ('$connectionName') - l'autenticazione a certificato non e' supportata da questa integrazione (vedi .NOTES di questa funzione). Usa Set-M365OpsTenant -SecretEnvVar per impostarne uno, oppure non collegare questo server MCP su questo profilo."
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
