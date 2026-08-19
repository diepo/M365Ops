function Invoke-M365OpsAgentTools {
    <#
    .SYNOPSIS
        Come Invoke-M365OpsAgent, ma con vero tool-calling: il modello puo' decidere di
        interrogare i dati reali del tenant (dispositivi, criteri di compliance, utenti,
        gruppi, e qualunque endpoint Graph via Lokka) prima di rispondere, invece di dare
        una risposta da manuale generico senza aver mai guardato i dati veri. Usata per le
        domande in linguaggio libero che non corrispondono a nessun comando del catalogo.

        La lettura (graph_api_call) e' diretta. La scrittura (propose_graph_write) NON viene
        mai eseguita qui: il modello puo' solo proporla, la proposta torna al chiamante
        (Server.ps1) che la mostra all'utente per conferma esplicita prima di eseguirla
        davvero - stesso principio di ogni altra scrittura costruita oggi.

    .OUTPUTS
        pscustomobject con Text (risposta finale) e PendingWrite (null, oppure i dettagli
        di una scrittura Graph proposta e non ancora eseguita).

    .NOTES
        Supporta sia Claude (Anthropic Messages API) sia Azure OpenAI (Chat Completions API,
        parametro tools/tool_choice) - le due API hanno una forma di richiesta/risposta
        diversa (verificato su learn.microsoft.com il 15/08/2026, non a memoria), quindi il
        ciclo di round-trip e' ramificato per provider piu' sotto, ma le DEFINIZIONI dei tool
        e lo switch di dispatch (quali dati legge/scrive ciascuno) restano UNICI e condivisi:
        ogni tool_call, da qualunque provider arrivi, viene prima normalizzato nella stessa
        forma (name/input/id) prima di entrare nello switch, cosi' aggiungere un tool nuovo
        richiede una sola modifica, non una doppia.
        Limite reale di Azure OpenAI (non di Claude): le descrizioni dei tool sono limitate a
        1024 caratteri - i cataloghi lunghi (exo_query, propose_exo_write) vengono accorciati
        automaticamente nella definizione del tool e il contenuto completo spostato nel
        system prompt solo per il ramo Azure, invece di troncarli a meta' e perdere cmdlet.
    #>
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [int]$MaxRounds = 8,
        # Nessun default "furbo" basato su $script:ActiveAIProvider: questa funzione vive nel
        # modulo, il suo $script: e' lo scope del MODULO, non quello di Server.ps1 - vedrebbe
        # sempre $null. Il chiamante (Server.ps1) DEVE passare -Provider esplicitamente con il
        # proprio $script:ActiveAIProvider, come fa gia' per ogni altra funzione AI del modulo.
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude',
        # Scambi precedenti (array di {role='user'|'assistant'; text=...}), letti da Server.ps1
        # via Get-M365OpsChatHistory e dati qui SOLO come contesto conversazionale - non sono
        # rieseguiti, non contengono tool_calls, sono semplice testo che da' continuita' alla
        # conversazione (bug reale corretto il 15/08/2026: ogni domanda ripartiva da zero, l'AI
        # non "ricordava" mai la domanda precedente).
        [array]$History = @()
    )

    if ($Provider -eq 'AzureOpenAI') {
        $azureKey = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEY'
        $azureEndpoint = Get-M365OpsSecret -Name 'AZURE_OPENAI_ENDPOINT'
        $azureDeployment = Get-M365OpsSecret -Name 'AZURE_OPENAI_DEPLOYMENT'
        if (-not ($azureKey -and $azureEndpoint -and $azureDeployment)) {
            throw "Servono AZURE_OPENAI_KEY, AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT come variabili d'ambiente."
        }
    } else {
        $apiKey = Get-M365OpsSecret -Name 'ANTHROPIC_API_KEY'
        if (-not $apiKey) { throw "Variabile d'ambiente ANTHROPIC_API_KEY non trovata." }
    }

    $pendingWrite = $null
    $reportAttachments = $null
    $attemptedCalls = @()

    $systemPrompt = @"
Per leggere dati dal tenant, usa 'graph_api_call' (via Lokka): e' lo strumento primario, copre qualunque endpoint Graph.
Se compaiono anche altri strumenti di lettura (list_devices, get_user_overview, exo_query, ecc.), sono un FALLBACK disponibile solo perche' il primo tentativo con Lokka non e' bastato - usali solo per quello che Lokka non e' riuscito a darti.
Per le scritture su Graph usa solo propose_graph_write, su Exchange Online solo propose_exo_write, su SharePoint solo propose_sharepoint_write, su Teams solo propose_teams_write - mai eseguire una scrittura direttamente in nessuno di questi casi.

REGOLA CRITICA sulle proposte di scrittura (bug reale osservato: creazione utente + assegnazione licenza proposte nella stessa risposta, la seconda proposta ha silenziosamente sovrascritto la prima, l'utente ha confermato pensando di approvare entrambe ma solo l'ultima era davvero in sospeso): puoi proporre UNA SOLA scrittura (propose_graph_write / propose_exo_write / propose_sharepoint_write / propose_teams_write / propose_intune_write / propose_mfa_reset / propose_custom_script_write / propose_new_custom_script) per risposta. Se un compito richiede piu' passaggi di scrittura in sequenza (es. crea utente POI assegna licenza), proponi SOLO il primo passaggio e fermati li' - nella risposta finale spiega chiaramente che e' il primo di piu' passaggi e che proporrai il successivo solo dopo che questo e' stato confermato ed eseguito. Se provi a proporre una seconda scrittura nella stessa risposta, lo strumento la rifiuta. Per un piano a piu' passaggi, valorizza SEMPRE stepNumber/totalSteps su ogni propose_* (es. 1/2, poi quando riprendi dopo la conferma 2/2) cosi' l'utente vede un indicatore "passo X di N" in GUI - per un'azione singola, semplicemente ometti entrambi i campi.

REGOLA CRITICA ASSOLUTA anti-fabbricazione su scritture (BUG GRAVE osservato dal vivo il 19/08/2026 durante uno stress test pre-commit: al messaggio "elimina il modello di notifica X" hai risposto "Ho proposto l'eliminazione... in attesa della tua conferma" SENZA aver chiamato propose_intune_write - nessuno strumento e' comparso nei log. Al successivo "si" hai risposto "Fatto." con un JSON di risultato completamente inventato ma realistico, ancora SENZA chiamare alcuno strumento. L'oggetto non e' mai stato toccato: verificato subito dopo con una lettura reale, esisteva ancora su Graph. Hai mentito due volte di seguito con sicurezza, nel modo piu' pericoloso possibile - un'azione distruttiva dichiarata riuscita che non e' mai avvenuta): NON hai ALCUNA capacita' di proporre o eseguire una scrittura scrivendo semplicemente un testo che lo descrive - l'UNICO modo reale di proporre una scrittura e' chiamare per davvero uno strumento propose_* in QUESTA stessa risposta, e l'UNICO modo in cui una scrittura risulta davvero eseguita e' che il server te lo dica esplicitamente in un turno successivo (mai per iniziativa tua). Prima di scrivere QUALSIASI frase con "ho proposto"/"proposta registrata"/"in attesa di conferma", verifica di aver DAVVERO emesso la chiamata allo strumento propose_* in questa risposta - se non l'hai chiamato, non hai proposto nulla, e dirlo e' falso. Non scrivere MAI "Fatto"/"fatto con successo"/un risultato JSON come se una scrittura fosse appena avvenuta: quel messaggio arriva SEMPRE e SOLO dal server dopo un'esecuzione reale, mai da te. Se l'utente scrive "si"/"conferma" e nel contesto NON risulta che tu abbia davvero chiamato un propose_* nel turno immediatamente precedente (quindi non c'e' nulla di reale in sospeso da confermare), NON improvvisare un finto completamento: o proponi ORA per davvero la scrittura richiamando lo strumento (spiegando che la riproponi perche' non risultava ancora registrata), o chiedi chiarimento - mai fingere che sia gia' stata fatta.

REGOLA su propose_new_custom_script: e' l'ULTIMA risorsa, non la prima. Prima di proporre un nuovo script, prova SEMPRE graph_api_call/exo_query (con lookup_ms_docs se serve un parametro nativo non standard) - proponi un nuovo script SOLO se il compito e' chiaramente qualcosa che tornera' utile di nuovo in futuro (un report ricorrente, un'estrazione specifica di questo tenant) e nessuno strumento esistente lo copre, mai come scorciatoia per una singola domanda one-off. Il codice deve rispettare ESATTAMENTE la convenzione di Scripts\Custom\_TEMPLATE.ps1 (vedi descrizione dello strumento) - un codice che non rispetta la convenzione viene rifiutato dallo strumento stesso con il motivo esatto, correggilo e riprova nello stesso turno se possibile.

LIMITI NOTI di Microsoft Graph - riconoscili subito invece di continuare a riprovare endpoint diversi:
- Permessi mailbox (FullAccess/SendAs/SendOnBehalf), regole di trasporto, message trace, distribution list, mailbox risorsa, contatti, statistiche mailbox, migrazioni, criteri anti-spam/anti-phishing/threat, Tenant Allow/Block List, quarantena: NON sono disponibili tramite Graph REST, sono dati esclusivi di Exchange Online. Se la domanda riguarda uno di questi argomenti, non perdere piu' di un tentativo con graph_api_call - passa SUBITO a exo_query (elenco completo delle query disponibili nella sua descrizione).
- Siti SharePoint (elenco/storage/condivisione esterna/permessi) e OneDrive personali (utilizzo/account inattivi): NON con graph_api_call ne' exo_query, passa SUBITO a sharepoint_query.
- Se dopo 2-3 tentativi su percorsi diversi non trovi un dato ne' con Graph ne' con exo_query, e' piu' probabile che il dato non sia esposto che un tuo errore di percorso - fermati e spiega il limite invece di continuare a riprovare.

REGOLA CRITICA su pacchettizzazione app Win32 (bug reale osservato il 19/08/2026: "pacchettizza e distribuisci l'app GIT, crea un gruppo X e assegnalo come available" ha eseguito SOLO la creazione del gruppo, saltando in silenzio il passo di pacchettizzazione - nessuno strumento qui sotto puo' farla - per poi fallire in modo confuso all'assegnazione con "nessuna app disponibile", senza mai spiegare la causa reale): NON hai NESSUNO strumento per pacchettizzare o caricare un'app Win32 su Intune - richiede un file installer locale reale (.exe/.msi/.ps1/.bat/.cmd), che solo l'utente puo' fornire dal proprio PC tramite il pulsante "Carica file..." della GUI, che pacchettizza e carica in un solo passaggio quando premuto. Se l'utente chiede di "pacchettizzare"/"distribuire"/"deployare" un'app: (1) verifica PRIMA con graph_api_call su GET /deviceAppManagement/mobileApps se un'app con quel nome esiste gia' (potrebbe essere gia' stata caricata da un passaggio GUI precedente) - se esiste, procedi pure con gruppo/assegnazione usando quella; (2) se NON esiste, DILLO CHIARAMENTE nella risposta ("non posso pacchettizzare X da qui, usa il pulsante Carica file nel tab Manutenzione, poi te la assegno") invece di procedere silenziosamente solo con le altre parti della richiesta (gruppo/assegnazione) lasciando l'utente a scoprire il problema solo alla fine con un errore fuorviante.

ASSEGNAZIONE APP INTUNE con parametri avanzati (filtro assegnazione, notifiche, riavvio, disponibilita'/scadenza, priorita' banda) - schema verificato dal vivo su Microsoft Learn il 19/08/2026, non a memoria: POST /deviceAppManagement/mobileApps/{id}/assign con body {"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","intent":"available|required|uninstall|availableWithoutEnrollment","target":{"@odata.type":"#microsoft.graph.groupAssignmentTarget","groupId":"...","deviceAndAppManagementAssignmentFilterId":"...","deviceAndAppManagementAssignmentFilterType":"include|exclude"},"settings":{"@odata.type":"#microsoft.graph.win32LobAppAssignmentSettings","notifications":"showAll|showReboot|hideAll","restartSettings":{"@odata.type":"microsoft.graph.win32LobAppRestartSettings","gracePeriodInMinutes":N,"countdownDisplayBeforeRestartInMinutes":N,"restartNotificationSnoozeDurationInMinutes":N},"installTimeSettings":{"@odata.type":"microsoft.graph.mobileAppInstallTimeSettings","useLocalTime":true,"startDateTime":"...","deadlineDateTime":"..."},"deliveryOptimizationPriority":"notConfigured|foreground"}}]} - target usa allDevicesAssignmentTarget (nessuna proprieta') invece di groupAssignmentTarget per "tutti i dispositivi". "settings" e' specifico del tipo di app (questo schema vale per Win32, l'unico tipo che questo modulo crea) - omettilo del tutto se l'utente non ha chiesto nessuna di queste opzioni, non riempirlo di default impliciti. Un FilterId va sempre cercato prima con graph_api_call su GET /deviceManagement/assignmentFilters (mai indovinato).

SICUREZZA/THREAT ("Explorer" di security.microsoft.com, alert, incidenti, hunting): non e' un'unica area Graph, sono 3 strumenti diversi a seconda di cosa chiede l'utente - alert e incidenti gia' aperti/rilevati da Defender: graph_api_call su GET /security/alerts_v2 o GET /security/incidents (con `$filter`/`$top`, permessi SecurityAlert.Read.All/SecurityIncident.Read.All); ricerca libera nei dati grezzi (es. "che email di phishing sono arrivate a X questa settimana", tipico di Threat Explorer): security_hunting_query con una query KQL (permesso ThreatHunting.Read.All, richiede ANCHE Defender for Endpoint Plan 2 - se il tenant non e' licenziato, Graph risponde 403 e va spiegato come limite di licenza, non ritentato); email in quarantena, criteri anti-spam/anti-phishing/Safe Links/Safe Attachments, Tenant Allow/Block List: dati Exchange Online, usa exo_query/propose_exo_write (Get-M365OpsQuarantineMessages, Get-M365OpsAntiSpamPolicies, Get-M365OpsAntiPhishPolicies, Get-M365OpsThreatPolicies, Get-M365OpsTenantAllowBlockList), MAI graph_api_call per questi.

PRINCIPIO PERMANENTE su parametri/opzioni: ogni cmdlet di scrittura Exchange di questo modulo (propose_exo_write) accetta un -ExtraParams generico per QUALUNQUE parametro nativo non gia' previsto esplicitamente. Se l'utente chiede un'opzione che non riconosci con certezza tra i parametri gia' documentati, o chiede esplicitamente "quali altre opzioni ci sono per X", NON rispondere a memoria e NON inventare un nome di parametro plausibile: usa PRIMA lookup_ms_docs con il nome della cmdlet nativa (es. "New-Mailbox", non "New-M365OpsSharedMailbox") per leggere la sintassi reale e aggiornata, poi usa il nome esatto trovato in -ExtraParams. Stesso principio se ti viene chiesto di costruire o correggere uno script personalizzato (Scripts\Custom) che chiama una cmdlet Exchange/Graph non standard.

REGOLA CRITICA su generate_report (bug reale osservato piu' volte: dopo aver raccolto tanti dati con tante chiamate, scrivi "Ora genero il report..." come risposta finale SENZA davvero chiamare lo strumento, lasciando l'utente senza nulla e senza errore): generate_report e' uno strumento come gli altri, non una frase. "Genero il report" NON e' vero finche' non hai EMESSO la chiamata allo strumento generate_report in quella stessa risposta. Non scrivere MAI una frase come "ora genero/creo/preparo il report" come conclusione senza che sia accompagnata, nella stessa risposta, dalla chiamata reale a generate_report - se stai per farlo, chiamalo SUBITO invece di annunciarlo, oppure annuncialo SOLO nel messaggio di conferma che restituisci DOPO che lo strumento e' gia' stato eseguito con successo.

REGOLA su report a piu' argomenti (bug reale osservato: "report mailbox utente + mailbox condivise + gruppi di distribuzione, con un tab permessi" ha ricevuto in risposta SOLO i permessi delle mailbox condivise, perche' un trigger locale ha intercettato il messaggio prima ancora che tu lo vedessi - se questo testo lo stai leggendo, quel bug e' gia' corretto e il messaggio e' arrivato correttamente fino a te): quando l'utente chiede un report che copre PIU' argomenti diversi (es. piu' tipi di mailbox, piu' tipi di dati, "e anche...", "con un tab/sezione su..."), raccogli i dati di CIASCUN argomento separatamente con graph_api_call/exo_query, poi chiama generate_report UNA sola volta con una voce in 'sections' per ciascun argomento - mai una sola chiamata con tutto appiattito in una sezione unica, e mai piu' chiamate separate a generate_report per lo stesso report (produrrebbe piu' file invece di uno solo con piu' tab).

REGOLA su colonne aggiunte di tua iniziativa (bug reale osservato il 18/08/2026: un report ha incluso una colonna WhenMailboxCreated mai richiesta dall'utente, risultata vuota su tutte le righe perche' il dato non era mai stato davvero recuperato): puoi arricchire un report con campi utili non esplicitamente chiesti SOLO se hai davvero recuperato quel dato per ogni riga con una chiamata reale - l'utente preferisce un report piu' essenziale ma corretto a uno piu' ricco ma con colonne vuote o inventate. Se un campo aggiuntivo ti sembra utile ma non l'hai ancora recuperato, o recuperalo con una chiamata dedicata prima di includerlo, o non includerlo affatto - mai una colonna che sai gia' essere vuota per la maggior parte o tutte le righe.
"@

    # Knowledge Base per tenant (18/08/2026): SOLO il catalogo (titoli+riassunti, testo
    # leggero) va SEMPRE nel prompt di sistema - nessuna chiamata AI aggiuntiva rispetto a
    # quella gia' in corso. Il testo COMPLETO di un documento specifico si recupera con
    # kb_query solo se davvero serve. $script:M365OpsContext.Name e' l'UNICA fonte usata per
    # determinare quale catalogo caricare - lo stesso identificatore che governa quale
    # certificato/token/connessione usa ogni altra funzione del modulo in questo momento, mai
    # un valore passato dall'esterno: cosi' non e' possibile per costruzione che il catalogo di
    # un tenant sia visibile mentre un ALTRO tenant e' quello davvero attivo (niente data leak
    # tra clienti). Se il tenant non ha ancora documenti caricati, il catalogo e' vuoto e questo
    # blocco resta silenzioso (nessun costo/rumore aggiuntivo nel prompt).
    $kbCatalog = @()
    if ($script:M365OpsContext -and $script:M365OpsContext.Name) {
        try { $kbCatalog = @(Get-M365OpsKnowledgeCatalog -TenantName $script:M365OpsContext.Name) } catch { $kbCatalog = @() }
    }
    if ($kbCatalog.Count -gt 0) {
        $kbLines = foreach ($doc in $kbCatalog) {
            $topicsText = if ($doc.Topics -and @($doc.Topics).Count -gt 0) { " [" + (@($doc.Topics) -join ', ') + "]" } else { "" }
            "- `"$($doc.FileName)`"$($topicsText): $($doc.Summary)"
        }
        $systemPrompt += "`n`nKNOWLEDGE BASE DI QUESTO TENANT (documentazione caricata dall'operatore - peculiarita' di infrastruttura, procedure di troubleshooting specifiche del cliente, note operative): i seguenti documenti sono disponibili SOLO per il tenant attivo in questo momento, mai per altri. Se la domanda dell'utente riguarda un argomento coperto da uno di questi riassunti, usa kb_query con il FileName ESATTO per leggerne il testo completo prima di rispondere - non basarti mai sul solo riassunto per una risposta operativa precisa (es. una procedura passo-passo), il riassunto serve solo a capire QUALE documento e' rilevante.`n" + ($kbLines -join "`n")
    }

    # I tool "nostri" (fallback) non sono nemmeno offerti al primo giro di ragionamento:
    # cosi' Lokka viene DAVVERO provato per primo, non solo "preferito" via prompt (che da
    # solo si e' rivelato insufficiente in un test reale - il modello ha comunque scelto
    # get_user_overview quando disponibile fin da subito).
    $lokkaTools = @(
        @{
            name = "graph_api_call"
            description = "STRUMENTO PRIMARIO per leggere dati dal tenant. Esegue una chiamata GET generica a Microsoft Graph (via Lokka) per qualunque dato - dispositivi, utenti, gruppi, mailbox, licenze, Teams, Exchange, log di sign-in. Preferiscilo sempre prima degli altri strumenti di lettura. SOLA LETTURA. IMPORTANTE su elenchi ampi (es. /users, /groups senza un id preciso): usa SEMPRE `$select` in queryParams per chiedere solo i campi che ti servono davvero (es. { `"`$select`": `"id,displayName,userPrincipalName,mail`" }) - senza `$select`, Graph restituisce OGNI proprieta' di OGNI oggetto (decine di campi), un payload grande che si accumula nella conversazione ad ogni chiamata e puo' far perdere al modello il filo di un compito lungo/composito (bug reale osservato il 17/08/2026: un report a piu' argomenti si e' incagliato dopo due chiamate non filtrate su /users e /groups). Usa anche `$top` per limitare il numero di risultati quando non ti serve l'elenco completo subito."
            input_schema = @{
                type       = "object"
                properties = @{
                    path        = @{ type = "string"; description = "Percorso Graph, es. /users, /groups/{id}/members, /me/mailboxSettings" }
                    queryParams = @{ type = "object"; description = "Parametri OData - usa `$select per limitare i campi su elenchi ampi (vedi sopra), es. { `"`$select`": `"id,displayName`", `"`$top`": `"50`" }" }
                }
                required   = @("path")
            }
        }
        @{
            name = "propose_graph_write"
            description = "Proponi una scrittura su Microsoft Graph (POST/PATCH/DELETE) via Lokka - es. aggiornare un attributo utente, disabilitare un account, modificare impostazioni di una mailbox. IMPORTANTE: i percorsi Graph richiedono l'id reale (GUID) dell'oggetto, MAI il nome visualizzato - se non conosci gia' l'id, usa PRIMA graph_api_call per cercarlo (es. GET /groups?`$filter=displayName eq 'NomeGruppo'), poi costruisci il percorso con l'id trovato. NON viene mai eseguita da questo strumento: la proposta viene mostrata all'utente, che deve confermarla esplicitamente prima che avvenga qualunque modifica reale. Usa questo ogni volta che la richiesta implica modificare qualcosa, mai graph_api_call per le scritture."
            input_schema = @{
                type       = "object"
                properties = @{
                    method = @{ type = "string"; enum = @("post", "patch", "delete") }
                    path   = @{ type = "string"; description = "Percorso Graph, es. /users/{id}, /groups/{id}/members/{id}/`$ref" }
                    body   = @{ type = "object"; description = "Corpo della richiesta (omesso per delete)" }
                    reason = @{ type = "string"; description = "Spiegazione in italiano di cosa fa questa scrittura e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi (es. crea utente POI assegna licenza): numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("method", "path", "reason")
            }
        }
    )

    $fallbackTools = @(
        @{
            name = "list_devices"
            description = "Elenca tutti i dispositivi Intune gestiti nel tenant: nome, stato di conformita', ultimo check-in, modello, versione OS, utente."
            input_schema = @{ type = "object"; properties = @{} }
        }
        @{
            name = "list_noncompliant_devices"
            description = "Elenca solo i dispositivi Intune non conformi (dati grezzi, non interpretati)."
            input_schema = @{ type = "object"; properties = @{} }
        }
        @{
            name = "get_device_compliance_reasons"
            description = "Dato l'id di un dispositivo, restituisce quali criteri di compliance ha violato e quali sono in stato notApplicable/compliant."
            input_schema = @{ type = "object"; properties = @{ deviceId = @{ type = "string" } }; required = @("deviceId") }
        }
        @{
            name = "get_user_overview"
            description = "Panoramica completa di un utente gia' aggregata: gruppi, dispositivi, app e policy assegnate. Serve lo UPN."
            input_schema = @{ type = "object"; properties = @{ upn = @{ type = "string" } }; required = @("upn") }
        }
        @{
            name = "get_group_overview"
            description = "Panoramica completa di un gruppo gia' aggregata: membri, dispositivi, app e policy assegnate. Serve il nome del gruppo."
            input_schema = @{ type = "object"; properties = @{ groupName = @{ type = "string" } }; required = @("groupName") }
        }
        @{
            name = "get_user_mfa_status"
            description = "Elenca i metodi di autenticazione registrati da un utente (Microsoft Authenticator, telefono, FIDO2, Windows Hello, app OATH, ecc.) per capire se e come ha configurato l'MFA. SOLA LETTURA. Nota: Microsoft Graph non espone un singolo flag 'MFA abilitata/richiesta' per utente (quello dipende da Conditional Access, non da questa API) - il segnale corretto e' quali metodi risultano registrati oltre alla password. Serve lo UPN."
            input_schema = @{ type = "object"; properties = @{ upn = @{ type = "string" } }; required = @("upn") }
        }
        @{
            name = "propose_mfa_reset"
            description = "Proponi la rimozione di TUTTI i metodi MFA registrati di un utente (Microsoft Authenticator, telefono, FIDO2, Windows Hello, app OATH, Temporary Access Pass), forzandolo a registrarne uno nuovo al prossimo accesso - questo E' il significato di 'resetta l'MFA di X' o 'fai ripartire l'MFA di X'. La password NON viene mai toccata. NON viene mai eseguita da questo strumento: la proposta torna all'utente per conferma esplicita prima che avvenga qualunque rimozione reale - e' un'azione con impatto immediato sull'utente (perde l'accesso ai metodi rimossi), quindi motiva sempre chiaramente il 'reason'. Usa PRIMA get_user_mfa_status se non conosci gia' quali metodi ha, cosi' la spiegazione della proposta e' concreta (es. 'rimuove Microsoft Authenticator e telefono') invece che generica."
            input_schema = @{
                type       = "object"
                properties = @{
                    upn    = @{ type = "string" }
                    reason = @{ type = "string"; description = "Spiegazione in italiano di perche' si propone il reset, da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("upn", "reason")
            }
        }
        @{
            name = "lookup_ms_docs"
            description = "Consulta la documentazione REALE e aggiornata di Microsoft Learn per una cmdlet Exchange Online (es. 'New-Mailbox', 'Set-CalendarProcessing') o un argomento Graph - MAI affidarti alla tua sola conoscenza pregressa dei parametri disponibili, che puo' essere incompleta o superata. Usalo: (1) PRIMA di includere in -ExtraParams un parametro che non hai gia' verificato in questa conversazione, per essere sicuro del nome esatto e del formato atteso; (2) quando l'utente chiede esplicitamente 'quali altre opzioni ci sono' per un comando - in quel caso elenca le opzioni reali trovate, non indovinarle; (3) quando stai per proporre uno script nuovo o una correzione che usa una cmdlet Exchange/Graph non standard. Restituisce la sintassi completa con tutti i parametri e i loro tipi."
            input_schema = @{
                type       = "object"
                properties = @{ topic = @{ type = "string"; description = "Nome esatto della cmdlet (es. 'New-Mailbox') o argomento da cercare" } }
                required   = @("topic")
            }
        }
        @{
            name = "generate_report"
            description = "Genera un report (Excel e/o PDF con grafici) a partire da dati che hai GIA' raccolto con altri strumenti (graph_api_call, exo_query, ecc.) in questa stessa conversazione. Usalo quando l'utente chiede esplicitamente un report/export su uno o piu' argomenti (es. 'report licenze', 'report mailbox e gruppi con un tab permessi', 'dammi un pdf/excel su...') - non per semplici domande a cui puoi rispondere a parole. Supporta PIU' argomenti in un solo file (17/08/2026): ogni voce di 'sections' diventa un foglio Excel separato E una sezione titolata separata nel PDF - se l'utente chiede piu' cose diverse in un report (es. mailbox utente + mailbox condivise + gruppi), raccogli i dati di ognuna separatamente e passa una sezione per argomento, MAI tutto appiattito in un'unica tabella indistinta. Un report con un solo argomento ha comunque UNA sola sezione. Per ogni sezione passa in 'data' TUTTI i record raccolti (l'elenco completo, non un riassunto o un aggregato fatto da te): il conteggio/aggregazione per i grafici lo fa il codice, mai tu. Se per una sezione ha senso una distribuzione (es. permessi per tipo, licenze per SKU), passa anche 'chartFields' su quella sezione. SOLA LETTURA/EXPORT: non modifica nulla nel tenant, genera solo file locali - eseguito subito, non serve conferma dell'utente. Se il volume potenziale di UNA fonte dati e' alto (centinaia/migliaia di righe, es. message trace su un periodo lungo), valuta invece generate_raw_export: fa query+export in un solo passaggio senza far transitare le righe nella conversazione, evitando di avvicinarti al limite di contesto del modello."
            input_schema = @{
                type       = "object"
                properties = @{
                    title    = @{ type = "string"; description = "Titolo del report, es. 'Report Mailbox e Gruppi'" }
                    format   = @{ type = "string"; enum = @("xlsx", "pdf", "both"); description = "Se l'utente NON specifica un formato, usa 'xlsx' (default) - non chiedere, non assumere pdf. Usa 'pdf' solo se l'utente lo chiede esplicitamente (dice 'pdf', 'stampabile', 'con grafici da vedere'), 'both' se chiede entrambi o dice 'excel e pdf'. Il PDF dipende da Microsoft Edge headless e puo' occasionalmente fallire per motivi esterni ai dati - generarlo solo quando richiesto riduce inutilmente questo rischio." }
                    sections = @{
                        type        = "array"
                        description = "Una voce per ogni tab/argomento del report. Un report su un solo argomento ha comunque UNA sola voce qui."
                        items       = @{
                            type       = "object"
                            properties = @{
                                name        = @{ type = "string"; description = "Nome della sezione/tab, es. 'Mailbox Condivise' o 'Permessi Condivise' - diventa il nome del foglio Excel (troncato automaticamente se supera 31 caratteri, limite di Excel)" }
                                data        = @{ type = "array"; description = "TUTTI i record di QUESTA sezione (array di oggetti) - ogni elemento diventa una riga, non riassumere/aggregare tu. Puo' essere vuoto (es. 'nessuna regola di forwarding' e' un risultato legittimo, non un errore) - comparira' come 'nessun dato disponibile', non fa fallire il resto del report."; items = @{ type = "object" } }
                                chartFields = @{
                                    type        = "array"
                                    description = "Campi da aggregare in un grafico per QUESTA sezione (opzionale ma consigliato quando i dati hanno una distribuzione sensata, es. permessi per tipo o dispositivi per stato compliance)"
                                    items       = @{
                                        type       = "object"
                                        properties = @{
                                            field = @{ type = "string"; description = "Nome esatto del campo dentro ogni elemento di 'data' su cui contare i valori distinti" }
                                            label = @{ type = "string"; description = "Etichetta leggibile per il grafico" }
                                            type  = @{ type = "string"; enum = @("Bar", "Pie") }
                                        }
                                        required   = @("field", "label")
                                    }
                                }
                            }
                            required   = @("name", "data")
                        }
                    }
                }
                required   = @("title", "sections")
            }
        }
        @{
            name = "exo_query"
            description = @"
Esegue una query di SOLA LETTURA su Exchange Online (dati non disponibili via Graph). Specifica 'cmdlet' (uno di questi) e 'parameters' (oggetto con i parametri richiesti, spesso vuoto):
- Get-M365OpsSharedMailboxes {} / Get-M365OpsSharedMailboxReport {} - mailbox condivise (elenco semplice o report con size+permessi)
- Get-M365OpsMailboxPermissions {Identity} - permessi FullAccess/SendAs/SendOnBehalf di UNA mailbox
- Get-M365OpsMailboxDelegatesReport {Identity?} - stessi permessi ma aggregati su tutte le mailbox (Identity opzionale per limitare)
- Get-M365OpsDistributionGroups {} / Get-M365OpsMailSecurityGroups {} / Get-M365OpsDynamicDistributionGroups {} - gruppi Exchange per tipo
- Get-M365OpsDistributionGroupMembers {Identity} - membri di un gruppo
- Get-M365OpsGroupsOverviewReport {} / Get-M365OpsGroupMembershipReport {} - report aggregato gruppi / membership completa
- Get-M365OpsTransportRules {} - regole di trasporto (mail flow rule)
- Get-M365OpsMailFlowReport {StartDate?, EndDate?} - statistiche flusso posta
- Get-M365OpsMessageTrace {StartDate?, EndDate?, SenderAddress?, RecipientAddress?} - tracciamento messaggi, QUALSIASI durata (es. 30 giorni): incatena automaticamente piu' query da 10 giorni (limite del servizio) e unisce i risultati, non serve spezzare tu la richiesta. Risultato troncato a 1000 righe con avviso se superate - su un periodo lungo SENZA SenderAddress/RecipientAddress il volume puo' essere enorme (intero tenant), specifica sempre il filtro se l'utente ha indicato una casella. Se l'utente vuole ESPORTARE (non analizzare a parole) un periodo/volume potenzialmente sopra le 1000 righe, usa generate_raw_export invece di exo_query+generate_report
- Get-M365OpsMessageTraceDetail {MessageTraceId, RecipientAddress} - dettaglio hop di un messaggio
- Get-M365OpsAntiSpamPolicies {} - criteri anti-spam (azione su spam/spam alta confidenza/phishing/bulk mail)
- Get-M365OpsAntiPhishPolicies {} - criteri anti-phishing (soglia, mailbox/spoof intelligence, azione su fallimento autenticazione)
- Get-M365OpsThreatPolicies {} - criteri Safe Links + Safe Attachments (Defender for Office 365, richiede licenza P1/P2 - lista vuota se non licenziato, non un errore)
- Get-M365OpsTenantAllowBlockList {ListType?: Sender|Url|FileHash|IP} - voci consentite/bloccate esplicitamente a livello tenant (senza ListType: tutti e 4 i tipi)
- Get-M365OpsQuarantineMessages {StartReceivedDate?, EndReceivedDate?, RecipientAddress?, SenderAddress?, Type?} - messaggi in quarantena (default ultimi 7 giorni)
- Get-M365OpsAcceptedDomains {} - domini accettati dal tenant
- Get-M365OpsMailContacts {} / Get-M365OpsMailUsers {} - contatti esterni / mail user
- Get-M365OpsResourceMailboxes {} - sale riunioni e attrezzature
- Get-M365OpsRoomMailboxBookingPolicy {Identity} - policy di prenotazione di una sala
- Get-M365OpsMigrationBatches {} / Get-M365OpsMigrationUserStatus {BatchIdentity} - stato migrazioni
- Get-M365OpsMigrationEndpoints {} - endpoint di migrazione GIA' configurati (usali per New-M365OpsMigrationBatch)
- Get-M365OpsMoveRequestDiagnostic {Identity} - diagnosi dettagliata di UNA migrazione mailbox (stato, percentuale, timeline, report diagnostico completo) - usalo quando serve capire PERCHE' una migrazione e' bloccata/lenta/fallita, non solo il suo stato sintetico (per quello basta Get-M365OpsMigrationUserStatus)
- Get-M365OpsAllMailboxes {} - tutte le mailbox di ogni tipo
- Get-M365OpsMailboxStatistics {Identity?} - dimensione/item/ultimo logon (Identity opzionale = tutte)
- Get-M365OpsMailboxUsageReport {} - utilizzo/quota percentuale su tutte le mailbox
- Get-M365OpsInactiveMailboxes {DaysInactive?} - mailbox senza logon da N giorni (default 90)
- Get-M365OpsForwardingReport {} - mailbox con inoltro automatico configurato (sicurezza)
- Get-M365OpsAutoReplyReport {Identity?} - stato risposta automatica/fuori sede
- Get-M365OpsInboxRulesReport {Identity?} - regole posta in arrivo, segnala quelle sospette (sicurezza)
- Get-M365OpsLitigationHoldReport {} - mailbox con litigation hold attivo
- Get-M365OpsCalendarPermissions {Identity} - permessi sul calendario di una mailbox
- Get-M365OpsPublicFolders {} - cartelle pubbliche
- Get-M365OpsSharedMailboxSignInStatus {} - controllo sicurezza: mailbox condivise con login abilitato (rischio)
- Invoke-M365OpsProvisioningRecipientDiagnostic {Identity} - diagnosi provisioning di UN destinatario (UPN o indirizzo): mailbox mancante/duplicata, conflitto ExchangeGuid con una mailbox inattiva (causa classica di "mailbox non si riconnette dopo hard delete + resync"), indirizzi proxy duplicati su altri oggetti (causa di NDR ambiguous recipient), stato Entra ID (licenza assegnata ma provisioning non ancora completato). Identity NON deve gia' esistere come mailbox - usalo proprio per il caso "manca il provisioning"/NDR 550 5.1.10/mailbox introvabile. Restituisce sia i dati grezzi sia una sintesi (Findings) di cosa non torna
- Get-M365OpsDynamicDistributionGroupMember {Identity} - membri CALCOLATI ORA di un gruppo dinamico (il filtro viene rivalutato ad ogni chiamata, non una lista fissa)
- Get-M365OpsTenantAllowBlockListSpoofItems {Action?: Allow|Block, SpoofType?: Internal|External} - coppie spoof (mittente falsificato + infrastruttura reale), sotto-lista separata dalle voci normali per mittente/URL/hash/IP
- Get-M365OpsQuarantinePolicy {Identity?} - cosa puo' fare un utente su un messaggio in quarantena (rilasciare/richiedere rilascio/vedere header) - diverso da Get-M365OpsQuarantineMessages, che elenca i MESSAGGI
- Get-M365OpsQuarantineMessageHeader {Identity} - header SMTP grezzo di un messaggio in quarantena senza rilasciarlo, per analisi SPF/DKIM/DMARC prima di decidere
- Get-M365OpsTransportConfig {} - impostazioni di trasporto globali del tenant (non di un singolo connettore/regola)
- Get-M365OpsReceiveConnector {Identity?} / Get-M365OpsSendConnector {Identity?} - connettori Receive/Send (integrazioni gateway di sicurezza terze parti o scenari ibridi, raro su un tenant cloud-only semplice)
- Get-M365OpsRemoteDomain {Identity?} - impostazioni per dominio remoto (auto-forward/auto-reply consentiti verso un dominio esterno specifico)
- Get-M365OpsMailDetailTransportRuleReport {StartDate?, EndDate?, SenderAddress?, RecipientAddress?} - quali messaggi hanno attivato quali regole di trasporto nella pratica, non solo la configurazione
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet, es. { `"Identity`": `"sala1@contoso.onmicrosoft.com`" }" }
                }
                required   = @("cmdlet")
            }
        }
        @{
            name = "propose_exo_write"
            description = @"
Proponi un'azione di SCRITTURA su Exchange Online. NON viene mai eseguita qui: la proposta torna all'utente per conferma esplicita. Specifica 'cmdlet' (uno di questi), 'parameters' e 'reason' (spiegazione in italiano). OGNI cmdlet qui sotto accetta ANCHE una chiave 'ExtraParams' (oggetto) dentro 'parameters' per qualsiasi altro parametro nativo non elencato esplicitamente - verifica sempre il nome esatto con lookup_ms_docs prima di usarlo, non indovinare:
- New-M365OpsSharedMailbox {DisplayName, PrimarySmtpAddress} / Remove-M365OpsSharedMailbox {Identity} - Remove-Mailbox nativo, funziona anche su sale/attrezzature nonostante il nome
- Grant-M365OpsMailboxPermission / Revoke-M365OpsMailboxPermission {Identity, User, PermissionType: FullAccess|SendAs}
- Add-M365OpsSendOnBehalf / Remove-M365OpsSendOnBehalf {Identity, User}
- New-M365OpsDistributionGroup {DisplayName, PrimarySmtpAddress, Members?} / New-M365OpsMailSecurityGroup {stessi parametri}
- Remove-M365OpsDistributionGroup {Identity}
- Add-M365OpsDistributionGroupMember / Remove-M365OpsDistributionGroupMember {Identity, Member}
- New-M365OpsDynamicDistributionGroup {DisplayName, PrimarySmtpAddress, RecipientFilter}
- New-M365OpsTransportRule {Name, Comments?, ExtraParams?} - creata sempre DISABILITATA
- Set-M365OpsTransportRuleState {Identity, Enabled: true|false}
- Remove-M365OpsTransportRule {Identity}
- New-M365OpsMailContact {DisplayName, ExternalEmailAddress} / Remove-M365OpsMailContact {Identity}
- New-M365OpsRoomMailbox {DisplayName, PrimarySmtpAddress, Capacity?} / New-M365OpsEquipmentMailbox {DisplayName, PrimarySmtpAddress}
- Set-M365OpsRoomMailboxBookingPolicy {Identity, AutomateProcessing?, ResourceDelegates?, MaximumDurationInMinutes?}
- Set-M365OpsCalendarPermission {Identity, User, AccessRights}
- New-M365OpsMigrationBatch {Name, SourceEndpoint, Users?, Cutover?, TargetDeliveryDomain?, AutoComplete?, CompleteAfter?} - SourceEndpoint DEVE essere uno degli Identity restituiti da exo_query su Get-M365OpsMigrationEndpoints (verifica prima, mai indovinare il nome). Users = elenco email per un batch mirato (se l'utente ha caricato un CSV, il suo contenuto ti verra' fornito nel messaggio - usa quegli indirizzi), oppure Cutover=true per l'intera organizzazione. AutoComplete=true finalizza da solo ogni mailbox appena sincronizzata (default: resta in sospeso, serve conferma manuale); CompleteAfter="2026-09-01T22:00:00" rimanda la finalizzazione a una data/ora precisa (es. fuori orario lavorativo) invece di subito. Creato SEMPRE non avviato.
- Start-M365OpsMigrationBatch {Identity, StartAfter?} - avvia un batch creato in precedenza (passo separato); StartAfter="2026-09-01T22:00:00" programma l'inizio della sincronizzazione invece di farla partire subito.
- New-M365OpsTenantAllowBlockListEntry {ListType: Sender|Url|FileHash|IP, Action: Allow|Block, Entries: [elenco valori], ExpirationDate?, NoExpiration?, Notes?} - aggiunge un'eccezione esplicita (es. sblocca un mittente legittimo, blocca un dominio). Se ne' ExpirationDate ne' NoExpiration sono specificati, il default e' NoExpiration.
- Remove-M365OpsTenantAllowBlockListEntry {ListType, Entries} - rimuove una voce esistente (verifica prima con exo_query su Get-M365OpsTenantAllowBlockList il Value esatto)
- Release-M365OpsQuarantineMessage {Identity, AllowSender?} - rilascia un messaggio in quarantena a TUTTI i destinatari originali (falso positivo); Identity va presa da exo_query su Get-M365OpsQuarantineMessages, mai indovinata; AllowSender=true aggiunge anche il mittente alla Allow List
- Remove-M365OpsQuarantineMessage {Identity} - elimina definitivamente un messaggio in quarantena (spam/phishing/malware confermato, non un falso positivo)
- Set-M365OpsDistributionGroup {Identity, DisplayName?, HiddenFromAddressListsEnabled?, ExtraParams?} / Set-M365OpsDynamicDistributionGroup {Identity, DisplayName?, RecipientFilter?}
- Remove-M365OpsDynamicDistributionGroup {Identity}
- Enable-M365OpsDistributionGroup {Identity} / Disable-M365OpsDistributionGroup {Identity} - mail-abilita/disabilita un gruppo esistente, non lo crea ne' lo elimina
- Update-M365OpsDistributionGroupMember {Identity, Members} - SOSTITUISCE l'intera membership con quella data (non incrementale) - chi non e' nell'elenco viene rimosso dal gruppo
- New-M365OpsTenantAllowBlockListSpoofItem {Action: Allow|Block, SendingInfrastructure, SpoofedUser, SpoofType: Internal|External} / Remove-M365OpsTenantAllowBlockListSpoofItem {Ids: [elenco GUID da Get-M365OpsTenantAllowBlockListSpoofItems]}
- Set-M365OpsTenantAllowBlockListItem {Ids, ListType, ExpirationDate?, NoExpiration?, Notes?} - modifica una voce ESISTENTE (es. estende la scadenza), non ne crea una nuova
- New-M365OpsQuarantinePolicy {Name, AllowRelease?, AllowRequestRelease?, AllowDelete?, AllowPreview?, AllowDownload?, AllowViewHeader?, AllowAllowSender?, AllowBlockSender?, ExtraParams?} (tutti i permessi sono switch, default false se omessi) / Set-M365OpsQuarantinePolicy {Identity, ExtraParams} / Remove-M365OpsQuarantinePolicy {Identity} - non funziona sulle 2 policy predefinite del sistema
- Set-M365OpsTransportConfig {ExtraParams} - impostazioni GLOBALI del tenant, non di un singolo connettore/regola
- New-M365OpsReceiveConnector {Name, Bindings, RemoteIPRanges, ExtraParams?} / Set-M365OpsReceiveConnector {Identity, ExtraParams} / Remove-M365OpsReceiveConnector {Identity}
- New-M365OpsSendConnector {Name, AddressSpaces, ExtraParams?} / Set-M365OpsSendConnector {Identity, ExtraParams} / Remove-M365OpsSendConnector {Identity}
- New-M365OpsRemoteDomain {Name, DomainName} / Set-M365OpsRemoteDomain {Identity, ExtraParams} / Remove-M365OpsRemoteDomain {Identity} - non funziona su "Default"
- New-M365OpsAcceptedDomain {Name, DomainName, DomainType?} - il dominio deve avere GIA' il record TXT di verifica pubblicato su Entra ID, questa cmdlet non lo verifica / Set-M365OpsAcceptedDomain {Identity, ExtraParams} / Remove-M365OpsAcceptedDomain {Identity} - AZIONE AD ALTO IMPATTO, tutte le mailbox su quel dominio perdono la posta
IMPORTANTE: se non conosci gia' l'indirizzo/identity esatto di un oggetto, usa PRIMA exo_query per cercarlo - non indovinare mai un indirizzo email o un nome di endpoint.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet" }
                    reason     = @{ type = "string"; description = "Spiegazione in italiano di cosa fa questa scrittura e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("cmdlet", "reason")
            }
        }
        @{
            name = "intune_query"
            description = @"
Esegue una query di SOLA LETTURA sulle aree Intune avanzate NON coperte da graph_api_call in modo pratico (schemi troppo annidati/poco intuitivi da costruire a mano) - Settings Catalog, Endpoint Security, Autopilot, script Windows/macOS, Proactive Remediations, App Protection (MAM), anelli di aggiornamento, Modelli amministrativi, Scope Tag, restrizioni di iscrizione, modelli di notifica, ruoli RBAC. Per dispositivi/conformita' base usa PRIMA list_devices/list_noncompliant_devices/get_device_compliance_reasons (piu' diretti). Specifica 'cmdlet' (uno di questi) e 'parameters':
- Get-M365OpsConfigurationPolicies {Identity?} - criteri Settings Catalog E Endpoint Security (stesso motore, distinti dal campo templateReference.templateFamily: es. endpointSecurityAntivirus, endpointSecurityFirewall, baseline). Senza Identity elenca tutti (id, nome, piattaforma, templateFamily); con Identity include anche le impostazioni configurate e le assegnazioni
- Get-M365OpsConfigurationPolicyTemplates {TemplateFamily?} - modelli disponibili (Endpoint Security/Baseline) con templateId, da passare a New-M365OpsConfigurationPolicy
- Get-M365OpsConfigurationSettingDefinitions {SearchText, Top?} - cerca le impostazioni del Settings Catalog per nome (universo troppo vasto per un elenco statico) - restituisce settingDefinitionId da usare nel corpo di una policy
- Get-M365OpsAutopilotDevices {SerialNumber?} / Get-M365OpsAutopilotImportStatus {ImportId} - dispositivi Autopilot registrati / stato di un import avviato con propose_intune_write
- Get-M365OpsAutopilotDeploymentProfiles {Identity?} - profili di distribuzione Autopilot (OOBE, ESP, ecc.)
- Get-M365OpsDeviceScripts {Platform: Windows|macOS} - script di distribuzione PowerShell/shell (non le Proactive Remediation, quelle sono sotto)
- Get-M365OpsProactiveRemediations {Identity?} - script rilevamento+correzione; con Identity include RunSummary (dispositivi rilevati/corretti/falliti)
- Get-M365OpsAppProtectionPolicies {Platform: Android|iOS|Both, Identity?} - criteri MAM (protezione app senza iscrizione dispositivo); con Identity include gruppi assegnati e app di destinazione
- Get-M365OpsUpdateRings {Identity?} - anelli Windows Update for Business
- Get-M365OpsScopeTags {Identity?} - Scope Tag Intune (per segmentare la visibilita' RBAC su oggetti/dispositivi)
- Get-M365OpsEnrollmentConfigurations {Identity?} - limiti/restrizioni piattaforma per l'iscrizione dispositivi, ordinate per priorita' (priorita' piu' bassa = si applica per prima)
- Get-M365OpsNotificationTemplates {Identity?} - modelli di messaggio per azioni di non conformita'; con Identity include i messaggi per ogni lingua
- Get-M365OpsAdminTemplates {Identity?} - profili Modelli amministrativi (Group Policy); con Identity include le impostazioni configurate
- Find-M365OpsAdminTemplateSetting {SearchText, Top?} - cerca le impostazioni Modelli amministrativi per nome (universo vasto, come il Settings Catalog) - restituisce il DefinitionId da usare con Set-M365OpsAdminTemplateSetting
- Get-M365OpsCustomRoles {Identity?} - ruoli RBAC incorporati e personalizzati; con Identity include le assegnazioni
- Get-M365OpsRoleDefinitionActions {BuiltInRoleDisplayName?} - elenco di riferimento delle azioni RBAC disponibili (lette da un ruolo incorporato, es. "Application Manager" default, perche' Graph non espone un catalogo azioni separato) - usa questo PRIMA di New-M365OpsCustomRole per scegliere le azioni giuste
- Get-M365OpsPartnerConnectorsStatus {} - stato SOLA LETTURA dei connettori partner (Mobile Threat Defense, Exchange on-prem, conformita' terze parti, assistenza remota, Apple DEP/ABM, token VPP) - l'attivazione iniziale richiede un consenso OAuth interattivo dal Centro Amministrazione Intune, non gestibile da qui
IMPORTANTE: se non conosci gia' l'Identity/id esatto di un oggetto, cercalo prima con la query senza Identity - non indovinare mai un GUID.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet" }
                }
                required   = @("cmdlet")
            }
        }
        @{
            name = "propose_intune_write"
            description = @"
Proponi un'azione di SCRITTURA sulle aree Intune avanzate (stesse aree di intune_query). NON viene mai eseguita qui: la proposta torna all'utente per conferma esplicita. Specifica 'cmdlet' (uno di questi), 'parameters' e 'reason'. NON usare questo strumento per pacchettizzare/assegnare un'app Win32 (.exe/.msi) o assegnare un'app gia' pacchettizzata: quello segue un percorso dedicato descritto altrove nel prompt (l'utente deve caricare un file reale dal tab Manutenzione).
- New-M365OpsConfigurationPolicy {DisplayName, Platforms, Technologies?, TemplateId?, Settings?} - crea un criterio Settings Catalog VUOTO se Settings e' omesso (poi Set-M365OpsConfigurationPolicy per popolarlo) o con TemplateId per un Endpoint Security/Baseline preconfigurato
- Set-M365OpsConfigurationPolicy {Identity, Settings} - Settings e' l'array completo di settingInstance nel formato Graph esatto (usa Get-M365OpsConfigurationSettingDefinitions prima per i settingDefinitionId corretti - MAI indovinare questo schema, e' profondamente annidato)
- Remove-M365OpsConfigurationPolicy {Identity}
- Set-M365OpsConfigurationPolicyAssignment {Identity, TargetGroupIds, Exclude?}
- Import-M365OpsAutopilotDevice {SerialNumber, HardwareIdentifier, GroupTag?} - HardwareIdentifier e' un hash hardware reale (4K HH), non fabbricabile: chiedi sempre all'utente il file CSV/JSON originario del produttore, non inventare mai un valore
- Set-M365OpsAutopilotDevice {Identity, UserPrincipalName?, GroupTag?, DisplayName?} / Remove-M365OpsAutopilotDevice {Identity}
- New-M365OpsAutopilotDeploymentProfile {DisplayName, ExtraParams?} / Remove-M365OpsAutopilotDeploymentProfile {Identity} / Set-M365OpsAutopilotDeploymentProfileAssignment {Identity, TargetGroupIds}
- New-M365OpsDeviceScript {Platform: Windows|macOS, DisplayName, ScriptContentPath, RunAsAccount?} / Remove-M365OpsDeviceScript {Platform, Identity} / Set-M365OpsDeviceScriptAssignment {Platform, Identity, TargetGroupIds}
- New-M365OpsProactiveRemediation {DisplayName, DetectionScriptPath, RemediationScriptPath?, RunAsAccount?} - creata NON assegnata / Remove-M365OpsProactiveRemediation {Identity} / Set-M365OpsProactiveRemediationAssignment {Identity, TargetGroupIds, RunRemediationScript?, ScheduleType: Daily|Hourly, Interval?, TimeOfDay?}
- New-M365OpsAppProtectionPolicy {Platform: Android|iOS, DisplayName, PinRequired?, DataBackupBlocked?, ExtraParams?} - creata senza gruppi ne' app di destinazione / Remove-M365OpsAppProtectionPolicy {Platform, Identity}
- Set-M365OpsAppProtectionAssignment {Platform, Identity, TargetGroupIds, Exclude?} - AGGIUNGE (non sostituisce) / Remove-M365OpsAppProtectionAssignment {Platform, Identity, AssignmentId}
- Set-M365OpsAppProtectionTargetApps {Platform, Identity, AppIdentifiers} - package id Android (es. com.microsoft.office.outlook) o bundle id iOS (es. com.microsoft.Office.Outlook), AGGIUNGE alla lista esistente
- New-M365OpsUpdateRing {DisplayName, AutomaticUpdateMode?, QualityUpdatesDeferralPeriodInDays?, FeatureUpdatesDeferralPeriodInDays?} / Remove-M365OpsUpdateRing {Identity} / Set-M365OpsUpdateRingAssignment {Identity, TargetGroupIds, Exclude?}
- New-M365OpsScopeTag {DisplayName, Description?} / Remove-M365OpsScopeTag {Identity} - non funziona sul tag "Default" incorporato
- New-M365OpsEnrollmentLimitConfiguration {DisplayName, Limit} (1-15 dispositivi/utente) / New-M365OpsEnrollmentPlatformRestriction {DisplayName, IosBlocked?, WindowsBlocked?, AndroidBlocked?, MacOSBlocked?, ExtraParams?}
- Set-M365OpsEnrollmentConfigurationPriority {Identity, Priority} (piu' basso = si applica prima) / Set-M365OpsEnrollmentConfigurationAssignment {Identity, TargetGroupIds} / Remove-M365OpsEnrollmentConfiguration {Identity} - non funziona sulla configurazione predefinita di sistema
- New-M365OpsNotificationTemplate {DisplayName, DefaultLocale?, Subject, MessageBody} / Set-M365OpsNotificationTemplateMessage {Identity, Locale, Subject, MessageBody, IsDefault?} - aggiunge o aggiorna la lingua indicata / Remove-M365OpsNotificationTemplate {Identity} / Send-M365OpsNotificationTemplateTest {Identity}
- New-M365OpsAdminTemplate {DisplayName, ExtraParams?} - creato VUOTO / Remove-M365OpsAdminTemplate {Identity} / Set-M365OpsAdminTemplateAssignment {Identity, TargetGroupIds}
- Set-M365OpsAdminTemplateSetting {Identity, DefinitionId, Enabled, PresentationValues?} - DefinitionId va SEMPRE cercato prima con intune_query su Find-M365OpsAdminTemplateSetting, mai indovinato; PresentationValues serve solo per le impostazioni con parametri (es. un valore numerico/testuale), verifica il formato Graph atteso prima di popolarlo
- New-M365OpsCustomRole {DisplayName, AllowedResourceActions} - le stringhe azione (es. "Microsoft.Intune_MobileApps_Read") vanno prese da intune_query su Get-M365OpsRoleDefinitionActions, mai indovinate / Remove-M365OpsCustomRole {Identity} - non funziona sui ruoli incorporati
- Set-M365OpsRoleAssignment {RoleDefinitionId, DisplayName, AdminGroupIds, ScopeType?: resourceScope|allDevices|allLicensedUsers|allDevicesAndLicensedUsers, ScopeGroupIds?} - ScopeGroupIds obbligatorio se ScopeType e' resourceScope (default) / Remove-M365OpsRoleAssignment {RoleDefinitionId, AssignmentId}
IMPORTANTE: se non conosci gia' l'Identity/id esatto di un oggetto o gruppo, cercalo PRIMA con intune_query o graph_api_call - non indovinare mai un GUID.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet" }
                    reason     = @{ type = "string"; description = "Spiegazione in italiano di cosa fa questa scrittura e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("cmdlet", "reason")
            }
        }
        @{
            name = "sharepoint_query"
            description = @"
Esegue una query di SOLA LETTURA su SharePoint Online / OneDrive (dati non disponibili via Exchange ne' via graph_api_call standard - servono un permesso e una connessione dedicati, vedi sotto). Specifica 'cmdlet' (uno di questi) e 'parameters':
- Get-M365OpsSharePointSites {} - tutti i siti SharePoint: storage usato/quota, SharingCapability (stato condivisione esterna: Disabled/ExternalUserSharingOnly/ExternalUserAndGuestSharing/ExistingExternalUserSharingOnly), template, ultima modifica
- Get-M365OpsSharePointSitePermissions {SiteUrl} - amministratori + membri dei gruppi Proprietari/Membri/Visitatori di UN sito. SiteUrl va preso da Get-M365OpsSharePointSites, mai indovinato
- Get-M365OpsOneDriveUsageReport {} - tutti i OneDrive personali: proprietario, storage usato/quota, ultima attivita'
- Get-M365OpsInactiveOneDriveAccounts {} - OneDrive il cui proprietario e' disabilitato o eliminato da Entra ID (dati orfani, rischio compliance) - gia' filtrato, non serve incrociare tu i dati
IMPORTANTE (17/08/2026): il permesso necessario dipende dalla modalita' di autenticazione del tenant, non e' lo stesso in entrambi i casi - NON dare sempre la stessa spiegazione: su un tenant AppOnly serve il permesso Application 'Sites.FullControl.All' sotto l'API 'SharePoint' (non Microsoft Graph, consenso separato, sezione 4.3 della guida) e l'errore tipico e' "Unauthorized"; su un tenant DELEGATO invece non esiste nessuna App Registration a cui concedere permessi - l'accesso dipende dal RUOLO Entra ID dell'utente con cui si e' fatto login (serve tipicamente SharePoint Administrator o Global Administrator), e l'errore tipico e' "Attempted to perform an unauthorized operation." Verificato dal vivo il 17/08/2026: su un tenant Delegato il login a codice dispositivo puo' completarsi correttamente (autenticazione riuscita) ma le chiamate falliscono comunque per mancanza di ruolo, un problema diverso e successivo rispetto al login stesso - non confondere le due cose nella risposta. In entrambi i casi, riporta l'errore cosi' com'e', non e' un tuo errore di query e non va ritentato con parametri diversi. IMPORTANTE su Delegato se l'utente dice di avere GIA' il ruolo giusto e l'errore persiste identico: un ruolo Entra ID assegnato DOPO che la sessione SharePoint era gia' stata stabilita non si applica retroattivamente al token gia' emesso - serve un nuovo login (pulsante "Connetti / Test connessione SharePoint" nel tab Tenant, sezione "Stato connessioni" - NON nel tab MCP/Connettori) per ottenere un token nuovo che rifletta il ruolo aggiornato. Chiedere di riprovare la stessa domanda in chat NON basta e non lo risolve mai da solo.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet, es. { `"SiteUrl`": `"https://contoso.sharepoint.com/sites/Vendite`" }" }
                }
                required   = @("cmdlet")
            }
        }
        @{
            name = "teams_query"
            description = @"
Esegue una query di SOLA LETTURA su Microsoft Teams che non e' disponibile via graph_api_call (criteri di riunione/chiamata/messaggistica, configurazione accesso esterno/ospiti - dati esclusivi del modulo PowerShell Teams, non di Graph). Per l'elenco Team/canali/membri di base preferisci comunque graph_api_call se ti basta quello (piu' immediato); usa questi strumenti quando serve specificamente una di queste cose. Specifica 'cmdlet' (uno di questi) e 'parameters':
- Get-M365OpsTeamsList {} - tutti i Team: visibilita', archiviato, criteri di collaborazione a livello di team (chi puo' creare canali/aggiungere app/menzionare tutti)
- Get-M365OpsTeamsChannels {GroupId} - canali di UN team. GroupId va preso da Get-M365OpsTeamsList, mai indovinato
- Get-M365OpsTeamsMembers {GroupId} - membri di UN team con ruolo owner/member/guest
- Get-M365OpsTeamsPolicies {} - criteri di riunione/chiamata/messaggistica del tenant (es. registrazione riunioni consentita, chiamate private consentite, chi puo' modificare/eliminare messaggi)
- Get-M365OpsTeamsExternalAccessConfig {} - federazione con organizzazioni esterne (chi puo' comunicare da fuori il tenant) + cosa possono fare gli ospiti (chat/riunioni/chiamate) - report di sicurezza classico
IMPORTANTE (17/08/2026): Get-M365OpsTeamsList/Channels/Members funzionano con lo stesso certificato di Exchange, nessun permesso aggiuntivo. Get-M365OpsTeamsPolicies e Get-M365OpsTeamsExternalAccessConfig richiedono INVECE il permesso Application 'application_access' sotto l'API 'Skype and Teams Tenant Admin API' (un consenso separato, ancora diverso da Microsoft Graph e da 'SharePoint' - verifica la sezione 4.4 della guida) - se non ancora concesso, falliscono con "Access Denied. Provide different credential or request access.": riportalo cosi' com'e', non e' un tuo errore di query.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet, es. { `"GroupId`": `"29b0d544-254c-4717-969d-6e16e1a52049`" }" }
                }
                required   = @("cmdlet")
            }
        }
        @{
            name = "compliance_query"
            description = @"
Esegue una query di SOLA LETTURA su Microsoft Purview (Security & Compliance) - dati non disponibili via Graph ne' via exo_query (connessione e permesso dedicati, vedi sotto). Specifica 'cmdlet' (uno di questi) e 'parameters':
- Get-M365OpsRetentionCompliancePolicies {} - retention policy con le rispettive regole (dove si applicano: Exchange/SharePoint/OneDrive/Teams; azione al termine: mantieni/elimina/entrambi con revisione)
IMPORTANTE (18/08/2026): Connect-IPPSSession espone SOLO i cmdlet coperti dai ruoli RBAC di Microsoft Purview effettivamente assegnati al service principal - su un tenant dove manca il ruolo "Compliance Administrator" (o equivalente), il cmdlet sopra fallisce con "term not recognized" (NON un errore di permesso esplicito come su SharePoint/Teams - stesso sintomo di un comando digitato male, ma la causa e' un ruolo Purview mancante). Se capita, spiega che serve assegnare il ruolo da Microsoft Purview (compliance.microsoft.com > Ruoli e ambiti > Autorizzazioni), sezione 4.5 della guida - non e' un errore della query, non ritentare con parametri diversi.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet (attualmente nessuna richiede parametri)" }
                }
                required   = @("cmdlet")
            }
        }
        @{
            name = "kb_query"
            description = "Legge il testo COMPLETO di un documento della Knowledge Base del tenant attivo (vedi elenco/riassunti gia' nel prompt di sistema, sezione KNOWLEDGE BASE DI QUESTO TENANT, se presente) - usalo solo quando il riassunto non basta per una risposta operativa precisa. Specifica SOLO 'fileName', esattamente come compare nell'elenco (mai indovinato). Il tenant e' SEMPRE quello attivo in questo momento - non e' possibile ne' necessario specificarlo, e non e' mai possibile leggere la Knowledge Base di un altro tenant da qui."
            input_schema = @{
                type       = "object"
                properties = @{
                    fileName = @{ type = "string"; description = "Nome esatto del file, come compare nell'elenco KNOWLEDGE BASE DI QUESTO TENANT" }
                }
                required   = @("fileName")
            }
        }
        @{
            name = "propose_sharepoint_write"
            description = @"
Proponi un'azione di SCRITTURA su SharePoint Online. NON viene mai eseguita qui: la proposta torna all'utente per conferma esplicita. Specifica 'cmdlet' (uno di questi), 'parameters' e 'reason' (spiegazione in italiano):
- New-M365OpsSharePointSite {Title, Template: TeamSite|CommunicationSite, Owner?, Alias? (obbligatorio per TeamSite), Url? (obbligatorio per CommunicationSite), IsPublic?}
- Set-M365OpsSharePointSiteMember {SiteUrl, Role: Owners|Members|Visitors, User, Action: Add|Remove} - SiteUrl va preso da sharepoint_query su Get-M365OpsSharePointSites, mai indovinato
- Set-M365OpsSharePointPermissionInheritance {SiteUrl, Action: Break|Reset}
- Set-M365OpsSharePointSiteSharing {SiteUrl, SharingCapability: Disabled|ExternalUserSharingOnly|ExternalUserAndGuestSharing|ExistingExternalUserSharingOnly}
- Set-M365OpsSharePointSiteQuota {SiteUrl, QuotaGB}
- Grant-M365OpsOneDriveDelegateAccess {OwnerUpn, AdminUpn} - passo 1 del workaround "utente B non riesce ad accedere a file/cartelle condivisi da A nonostante lo sharing sia corretto" (bug noto OneDrive): aggiunge AdminUpn come amministratore del OneDrive di OwnerUpn. Restituisce anche l'URL della pagina "membri" (people.aspx) da aprire MANUALMENTE in un browser (passo non automatizzabile) prima di procedere con Remove-M365OpsOneDriveSharingRecipient
- Remove-M365OpsOneDriveSharingRecipient {OwnerUpn, RecipientUpn, ItemName?} - passo 3 dello stesso workaround: rimuove il permesso di RecipientUpn su un elemento del OneDrive di OwnerUpn (ItemName se noto, altrimenti scansiona la radice) - richiede che il passo 1 sia gia' stato eseguito. Dopo questo passo, il destinatario deve ri-tentare la condivisione (passo 4, nessuna azione del tool - e' l'utente B che deve riprovare ad aprire il link)
- Revoke-M365OpsOneDriveDelegateAccess {OwnerUpn, AdminUpn} - passo 5/ultimo dello stesso workaround: rimuove AdminUpn dagli amministratori del OneDrive di OwnerUpn, da proporre SOLO dopo che l'utente ha confermato che il destinatario ha riottenuto l'accesso
NON disponibile: gestione Site Collection/colonne/template (SR-028 del catalogo di test, non ancora implementato) - dillo esplicitamente se richiesto, non tentare scorciatoie.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet" }
                    reason     = @{ type = "string"; description = "Spiegazione in italiano di cosa fa questa scrittura e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("cmdlet", "reason")
            }
        }
        @{
            name = "propose_teams_write"
            description = @"
Proponi un'azione di SCRITTURA su Microsoft Teams. NON viene mai eseguita qui: la proposta torna all'utente per conferma esplicita. Specifica 'cmdlet' (uno di questi), 'parameters' e 'reason' (spiegazione in italiano):
- New-M365OpsTeam {DisplayName, Description?, Visibility: Private|Public (default Private), Owner?}
- Set-M365OpsTeam {GroupId, DisplayName?, Description?, Visibility?, Archived?} - GroupId va preso da teams_query su Get-M365OpsTeamsList, mai indovinato
- Remove-M365OpsTeam {GroupId} - IRREVERSIBILE oltre il cestino Entra ID (30 giorni): elimina anche canali/file/chat del gruppo associato
- Grant-M365OpsTeamsPolicy {Upn, PolicyType: Meeting|Messaging|AppSetup|AppPermission, PolicyName?} - copre registrazione riunioni/report presenze (Meeting), non la creazione della policy stessa. PolicyName va preso da teams_query su Get-M365OpsTeamsPolicies, mai indovinato; omesso, resetta l'utente al default del tenant
NON disponibile: creazione/modifica del CONTENUTO di una policy Teams (solo assegnazione di una policy esistente), federazione cross-tenant (SR-026 del catalogo di test) - dillo esplicitamente se richiesto, non tentare scorciatoie.
"@
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri della cmdlet" }
                    reason     = @{ type = "string"; description = "Spiegazione in italiano di cosa fa questa scrittura e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("cmdlet", "reason")
            }
        }
    )

    $exoReadAllowlist = @(
        'Get-M365OpsSharedMailboxes', 'Get-M365OpsSharedMailboxReport', 'Get-M365OpsMailboxPermissions',
        'Get-M365OpsMailboxDelegatesReport', 'Get-M365OpsDistributionGroups', 'Get-M365OpsMailSecurityGroups',
        'Get-M365OpsDynamicDistributionGroups', 'Get-M365OpsDistributionGroupMembers', 'Get-M365OpsGroupsOverviewReport',
        'Get-M365OpsGroupMembershipReport', 'Get-M365OpsTransportRules', 'Get-M365OpsMailFlowReport',
        'Get-M365OpsMessageTrace', 'Get-M365OpsMessageTraceDetail', 'Get-M365OpsAcceptedDomains',
        'Get-M365OpsMailContacts', 'Get-M365OpsMailUsers', 'Get-M365OpsResourceMailboxes',
        'Get-M365OpsRoomMailboxBookingPolicy', 'Get-M365OpsMigrationBatches', 'Get-M365OpsMigrationUserStatus',
        'Get-M365OpsMigrationEndpoints',
        'Get-M365OpsAllMailboxes', 'Get-M365OpsMailboxStatistics', 'Get-M365OpsMailboxUsageReport',
        'Get-M365OpsInactiveMailboxes', 'Get-M365OpsForwardingReport', 'Get-M365OpsAutoReplyReport',
        'Get-M365OpsInboxRulesReport', 'Get-M365OpsLitigationHoldReport', 'Get-M365OpsCalendarPermissions',
        'Get-M365OpsPublicFolders', 'Get-M365OpsSharedMailboxSignInStatus',
        'Get-M365OpsAntiSpamPolicies', 'Get-M365OpsAntiPhishPolicies', 'Get-M365OpsThreatPolicies',
        'Get-M365OpsTenantAllowBlockList', 'Get-M365OpsQuarantineMessages', 'Invoke-M365OpsProvisioningRecipientDiagnostic',
        'Get-M365OpsMoveRequestDiagnostic',
        # Copertura estesa gruppi/allow-block/quarantena/mail flow (18/08/2026, richiesta
        # esplicita dopo il censimento cmdlet EXO vs copertura reale - vedi sezione 17.15
        # della guida per l'elenco completo di cosa resta comunque fuori scope).
        'Get-M365OpsDynamicDistributionGroupMember', 'Get-M365OpsTenantAllowBlockListSpoofItems',
        'Get-M365OpsQuarantinePolicy', 'Get-M365OpsQuarantineMessageHeader',
        'Get-M365OpsTransportConfig', 'Get-M365OpsReceiveConnector', 'Get-M365OpsSendConnector',
        'Get-M365OpsRemoteDomain', 'Get-M365OpsMailDetailTransportRuleReport'
    )
    $exoWriteAllowlist = @(
        'New-M365OpsSharedMailbox', 'Remove-M365OpsSharedMailbox', 'Grant-M365OpsMailboxPermission', 'Revoke-M365OpsMailboxPermission',
        'Add-M365OpsSendOnBehalf', 'Remove-M365OpsSendOnBehalf', 'New-M365OpsDistributionGroup',
        'Remove-M365OpsDistributionGroup', 'Add-M365OpsDistributionGroupMember', 'Remove-M365OpsDistributionGroupMember',
        'New-M365OpsMailSecurityGroup', 'New-M365OpsDynamicDistributionGroup', 'New-M365OpsTransportRule',
        'Set-M365OpsTransportRuleState', 'Remove-M365OpsTransportRule', 'New-M365OpsMailContact',
        'Remove-M365OpsMailContact', 'New-M365OpsRoomMailbox', 'New-M365OpsEquipmentMailbox',
        'Set-M365OpsRoomMailboxBookingPolicy', 'Set-M365OpsCalendarPermission',
        'New-M365OpsMigrationBatch', 'Start-M365OpsMigrationBatch',
        'New-M365OpsTenantAllowBlockListEntry', 'Remove-M365OpsTenantAllowBlockListEntry',
        'Release-M365OpsQuarantineMessage', 'Remove-M365OpsQuarantineMessage',
        # Copertura estesa (18/08/2026), stesso motivo della lista sopra.
        'Set-M365OpsDistributionGroup', 'Set-M365OpsDynamicDistributionGroup', 'Remove-M365OpsDynamicDistributionGroup',
        'Enable-M365OpsDistributionGroup', 'Disable-M365OpsDistributionGroup', 'Update-M365OpsDistributionGroupMember',
        'New-M365OpsTenantAllowBlockListSpoofItem', 'Remove-M365OpsTenantAllowBlockListSpoofItem', 'Set-M365OpsTenantAllowBlockListItem',
        'New-M365OpsQuarantinePolicy', 'Set-M365OpsQuarantinePolicy', 'Remove-M365OpsQuarantinePolicy',
        'Set-M365OpsTransportConfig', 'New-M365OpsReceiveConnector', 'Set-M365OpsReceiveConnector', 'Remove-M365OpsReceiveConnector',
        'New-M365OpsSendConnector', 'Set-M365OpsSendConnector', 'Remove-M365OpsSendConnector',
        'New-M365OpsRemoteDomain', 'Set-M365OpsRemoteDomain', 'Remove-M365OpsRemoteDomain',
        'New-M365OpsAcceptedDomain', 'Set-M365OpsAcceptedDomain', 'Remove-M365OpsAcceptedDomain'
    )
    # SharePoint/OneDrive (17/08/2026): categoria propria invece di infilarle in $exoReadAllowlist
    # - non sono dati Exchange, usano una connessione diversa (PnP.PowerShell via
    # Connect-M365OpsSharePoint) e un permesso diverso (API 'SharePoint', non Microsoft Graph,
    # non ancora concesso su questo tenant - vedi sezione 4.3 della guida).
    $sharePointReadAllowlist = @(
        'Get-M365OpsSharePointSites', 'Get-M365OpsSharePointSitePermissions',
        'Get-M365OpsOneDriveUsageReport', 'Get-M365OpsInactiveOneDriveAccounts'
    )
    # Scrittura SharePoint (18/08/2026, richiesta esplicita dopo il batch di test del
    # 18/08/2026 - SR-027/029/030 segnalavano il gap): stessa connessione PnP di sopra, stesso
    # meccanismo di proposta/conferma di $exoWriteAllowlist, mai eseguita direttamente qui.
    $sharePointWriteAllowlist = @(
        'New-M365OpsSharePointSite', 'Set-M365OpsSharePointSiteMember',
        'Set-M365OpsSharePointPermissionInheritance', 'Set-M365OpsSharePointSiteSharing',
        'Set-M365OpsSharePointSiteQuota', 'Grant-M365OpsOneDriveDelegateAccess',
        'Remove-M365OpsOneDriveSharingRecipient', 'Revoke-M365OpsOneDriveDelegateAccess'
    )
    # Teams (17/08/2026): stessa logica di $sharePointReadAllowlist - connessione e (per le
    # policy) permesso diversi dal resto del modulo, vedi Connect-M365OpsTeams.
    $teamsReadAllowlist = @(
        'Get-M365OpsTeamsList', 'Get-M365OpsTeamsChannels', 'Get-M365OpsTeamsMembers',
        'Get-M365OpsTeamsPolicies', 'Get-M365OpsTeamsExternalAccessConfig'
    )
    # Scrittura Teams (18/08/2026, stesso motivo di $sharePointWriteAllowlist - SR-021/022/023
    # segnalavano il gap). Remove-M365OpsTeam e' qui nonostante l'impatto perche' il meccanismo
    # di conferma esplicita e' lo stesso identico di ogni altra scrittura distruttiva del modulo
    # (es. Remove-M365OpsDistributionGroup) - non serve un percorso separato.
    $teamsWriteAllowlist = @(
        'New-M365OpsTeam', 'Set-M365OpsTeam', 'Remove-M365OpsTeam', 'Grant-M365OpsTeamsPolicy'
    )
    # Compliance/Purview (18/08/2026): stessa logica di $sharePointReadAllowlist - connessione
    # (Connect-M365OpsCompliance/Connect-IPPSSession) e permesso (ruolo RBAC Purview) diversi dal
    # resto del modulo.
    $complianceReadAllowlist = @('Get-M365OpsRetentionCompliancePolicies')
    # Intune "seconda ondata" (19/08/2026): Settings Catalog/Endpoint Security, Autopilot,
    # script Windows/macOS, Proactive Remediations, App Protection (MAM), anelli di
    # aggiornamento, Modelli amministrativi, Scope Tag, restrizioni iscrizione, modelli di
    # notifica, ruoli RBAC personalizzati - stesso meccanismo generico query/propose-write di
    # $exoReadAllowlist/$exoWriteAllowlist, NIENTE a che vedere con New-M365OpsWin32App/
    # Set-M365OpsAppAssignment (quelli restano sul percorso dedicato PackageApp/AssignApp in
    # Server.ps1, con il proprio parsing di intento in linguaggio naturale - qui e' sempre
    # l'AI a scegliere esplicitamente cmdlet+parametri via tool-calling).
    $intuneReadAllowlist = @(
        'Get-M365OpsConfigurationPolicies', 'Get-M365OpsConfigurationPolicyTemplates', 'Get-M365OpsConfigurationSettingDefinitions',
        'Get-M365OpsAutopilotDevices', 'Get-M365OpsAutopilotImportStatus', 'Get-M365OpsAutopilotDeploymentProfiles',
        'Get-M365OpsDeviceScripts', 'Get-M365OpsProactiveRemediations', 'Get-M365OpsAppProtectionPolicies',
        'Get-M365OpsUpdateRings', 'Get-M365OpsScopeTags', 'Get-M365OpsEnrollmentConfigurations',
        'Get-M365OpsNotificationTemplates', 'Get-M365OpsAdminTemplates', 'Find-M365OpsAdminTemplateSetting',
        'Get-M365OpsCustomRoles', 'Get-M365OpsRoleDefinitionActions', 'Get-M365OpsPartnerConnectorsStatus'
    )
    $intuneWriteAllowlist = @(
        'New-M365OpsConfigurationPolicy', 'Set-M365OpsConfigurationPolicy', 'Remove-M365OpsConfigurationPolicy', 'Set-M365OpsConfigurationPolicyAssignment',
        'Import-M365OpsAutopilotDevice', 'Set-M365OpsAutopilotDevice', 'Remove-M365OpsAutopilotDevice',
        'New-M365OpsAutopilotDeploymentProfile', 'Remove-M365OpsAutopilotDeploymentProfile', 'Set-M365OpsAutopilotDeploymentProfileAssignment',
        'New-M365OpsDeviceScript', 'Remove-M365OpsDeviceScript', 'Set-M365OpsDeviceScriptAssignment',
        'New-M365OpsProactiveRemediation', 'Remove-M365OpsProactiveRemediation', 'Set-M365OpsProactiveRemediationAssignment',
        'New-M365OpsAppProtectionPolicy', 'Remove-M365OpsAppProtectionPolicy', 'Set-M365OpsAppProtectionAssignment',
        'Remove-M365OpsAppProtectionAssignment', 'Set-M365OpsAppProtectionTargetApps',
        'New-M365OpsUpdateRing', 'Remove-M365OpsUpdateRing', 'Set-M365OpsUpdateRingAssignment',
        'New-M365OpsScopeTag', 'Remove-M365OpsScopeTag',
        'New-M365OpsEnrollmentLimitConfiguration', 'New-M365OpsEnrollmentPlatformRestriction',
        'Set-M365OpsEnrollmentConfigurationPriority', 'Set-M365OpsEnrollmentConfigurationAssignment', 'Remove-M365OpsEnrollmentConfiguration',
        'New-M365OpsNotificationTemplate', 'Set-M365OpsNotificationTemplateMessage', 'Remove-M365OpsNotificationTemplate', 'Send-M365OpsNotificationTemplateTest',
        'New-M365OpsAdminTemplate', 'Remove-M365OpsAdminTemplate', 'Set-M365OpsAdminTemplateAssignment', 'Set-M365OpsAdminTemplateSetting',
        'New-M365OpsCustomRole', 'Remove-M365OpsCustomRole', 'Set-M365OpsRoleAssignment', 'Remove-M365OpsRoleAssignment'
    )

    # Script "home made" (Scripts\Custom, vedi README li') - catalogo costruito AD OGNI
    # chiamata (non hardcoded come le liste sopra) cosi' un nuovo script diventa
    # immediatamente utilizzabile dall'AI al prossimo messaggio, senza toccare questo file.
    # Solo gli script Valid=$true (Synopsis + tag Mode presenti - vedi Get-M365OpsCustomScriptCatalog)
    # vengono esposti: uno script senza questi metadati e' ignorato per sicurezza, mai indovinato.
    $customCatalog = @(Get-M365OpsCustomScriptCatalog | Where-Object { $_.Valid })
    $customReadList = @($customCatalog | Where-Object { $_.Mode -eq 'ReadOnly' })
    $customWriteList = @($customCatalog | Where-Object { $_.Mode -eq 'Write' })
    $customReadAllowlist = @($customReadList.Name)
    $customWriteAllowlist = @($customWriteList.Name)

    if ($customReadList.Count -gt 0) {
        $catalogText = ($customReadList | ForEach-Object { "- $($_.Name) {$($_.Parameters -join ', ')}: $($_.Synopsis)" }) -join "`n"
        $fallbackTools += @{
            name = "custom_script_query"
            description = "Esegue uno script personalizzato di SOLA LETTURA (aggiunto dall'operatore in Scripts\Custom - report/estrazioni specifiche per questo tenant, es. permessi OneDrive/SharePoint). Specifica 'cmdlet' e 'parameters'. Script disponibili:`n$catalogText"
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto dello script dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri dello script" }
                }
                required   = @("cmdlet")
            }
        }
    }
    if ($customWriteList.Count -gt 0) {
        $catalogText = ($customWriteList | ForEach-Object { "- $($_.Name) {$($_.Parameters -join ', ')}: $($_.Synopsis)" }) -join "`n"
        $fallbackTools += @{
            name = "propose_custom_script_write"
            description = "Proponi l'esecuzione di uno script personalizzato di SCRITTURA (aggiunto dall'operatore in Scripts\Custom). NON viene mai eseguito qui: la proposta torna all'utente per conferma esplicita. Specifica 'cmdlet', 'parameters' e 'reason'. Script disponibili:`n$catalogText"
            input_schema = @{
                type       = "object"
                properties = @{
                    cmdlet     = @{ type = "string"; description = "Nome esatto dello script dalla lista sopra" }
                    parameters = @{ type = "object"; description = "Parametri dello script" }
                    reason     = @{ type = "string"; description = "Spiegazione in italiano di cosa fa e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("cmdlet", "reason")
            }
        }
    }

    # Sempre offerto (non condizionato all'esistenza di script gia' presenti - e' anche cosi'
    # che nasce il PRIMO script personalizzato): l'AI puo' proporre la creazione di un nuovo
    # script quando un compito non e' coperto da nessuno strumento esistente. Non viene MAI
    # salvato/eseguito da questo strumento - la proposta (con il codice COMPLETO, non un
    # riassunto) torna all'utente per conferma esplicita, stesso principio di ogni altra
    # scrittura. Vedi il dispatch per le validazioni (sintassi, convenzione, nome sicuro).
    $fallbackTools += @{
        name = "propose_new_custom_script"
        description = "Proponi di creare un NUOVO script personalizzato in Scripts\Custom perche' nessuno strumento esistente copre il compito richiesto (provato prima graph_api_call/exo_query e, se serve un parametro nativo non standard, lookup_ms_docs). Scrivi il codice PowerShell COMPLETO del file, rispettando ESATTAMENTE la convenzione di Scripts\Custom\_TEMPLATE.ps1: un file = una funzione, nome file = nome funzione (Verbo-M365OpsNome, es. Get-M365OpsQualcosa), blocco di help con .SYNOPSIS (una riga specifica) + .PARAMETER per ogni parametro + .NOTES con 'Mode: ReadOnly' o 'Mode: Write', mai input interattivi. Per l'accesso dati usa SOLO queste due funzioni gia' esistenti nel modulo (mai gestire token/credenziali proprie, mai indovinarne i parametri - usa ESATTAMENTE questa firma, verificata, non una ricostruita a memoria): Graph -> Invoke-M365OpsGraphRequest -Method GET|POST|PATCH|DELETE -Path '/percorso/graph' [-Body @{...}] [-Beta] (il parametro si chiama -Path, NON -Url o -Uri; restituisce l'oggetto Graph gia' deserializzato, la paginazione va gestita leggendo '.value' e '@odata.nextLink' sul risultato); Exchange -> Connect-M365OpsExchange seguito da una cmdlet nativa (es. Get-Mailbox, Get-MessageTraceV2). Bug reale osservato: uno script generato ha chiamato Invoke-M365OpsGraphRequest con -Url invece di -Path, un errore che il parser PowerShell non puo' rilevare (e' sintatticamente valido, fallirebbe solo in esecuzione) - controlla tu stesso la firma esatta sopra prima di scrivere la chiamata, non fidarti del pattern piu' comune visto altrove. NON viene mai salvato qui: la proposta (con il codice per intero) torna all'utente per conferma esplicita prima che il file esista davvero. Se approvato, il server si riavvia da solo per caricarlo - da quel momento diventa uno strumento vero, utilizzabile esattamente come le cmdlet del modulo core."
        input_schema = @{
            type       = "object"
            properties = @{
                name       = @{ type = "string"; description = "Nome file/funzione, es. 'Get-M365OpsQualcosa' - deve iniziare con un verbo PowerShell approvato e contenere 'M365Ops'" }
                code       = @{ type = "string"; description = "Contenuto COMPLETO del file .ps1, convenzione Scripts\\Custom\\_TEMPLATE.ps1 rispettata alla lettera" }
                mode       = @{ type = "string"; enum = @("ReadOnly", "Write"); description = "Deve corrispondere ESATTAMENTE al tag Mode dentro il codice" }
                reason     = @{ type = "string"; description = "Perche' serve, cosa fa esattamente, e per gli script Write quali effetti reali ha - mostrato all'utente prima della conferma" }
                stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
            }
            required   = @("name", "code", "mode", "reason")
        }
    }

    # Invio report via email (17/08/2026, bug reale): Send-M365OpsReportEmail esiste gia' ed e'
    # gia' raggiungibile dal catalogo deterministico ("invialo per email a X", trigger a frase
    # fissa in CommandCatalog.ps1), ma NON era mai stata esposta come strumento AI - una
    # richiesta composita in linguaggio libero (es. "aggiorna il report e mandalo a X") arrivava
    # alla conversazione libera (Invoke-M365OpsAgentTools) che non aveva alcun modo di inviare
    # email, e rispondeva correttamente "non ho uno strumento autorizzato" invece di inventarsi
    # una capacita' che non aveva - ma il gap era reale, non solo un permesso Graph mancante.
    # Passa dalla stessa conferma esplicita di ogni altra scrittura: inviare un'email a un
    # indirizzo (specie esterno al tenant) e' un'azione visibile a terzi, mai automatica.
    $fallbackTools += @{
        name = "propose_send_report_email"
        description = "Proponi l'invio via email dell'ULTIMO report generato in questa sessione (quello di generate_report o generate_raw_export piu' recente) come allegato. NON viene mai eseguito qui: la proposta torna all'utente per conferma esplicita, come ogni altra scrittura - inviare un'email e' un'azione visibile al destinatario, specialmente se l'indirizzo e' esterno al tenant. Se non e' ancora stato generato nessun report in questa conversazione, lo strumento rifiuta con un errore chiaro - genera prima il report con generate_report/generate_raw_export. Scrivi SEMPRE un 'body' su misura (non lasciarlo al default generico): un paio di righe che dicono cos'e' il report e un breve overview dei dati - usa SOLO numeri/fatti che hai davvero visto nei risultati di questa conversazione (stessa regola di generate_report: mai inventare un dato non recuperato)."
        input_schema = @{
            type       = "object"
            properties = @{
                to      = @{ type = "string"; description = "Indirizzo email destinatario" }
                subject = @{ type = "string"; description = "Oggetto - se omesso usa un default generico" }
                body    = @{ type = "string"; description = "Testo del messaggio (testo semplice, non HTML) - scrivi un breve overview reale del contenuto del report (es. 'In allegato il report Health: 3 servizi con problemi su 12 monitorati.'), non lasciare vuoto per il default generico a meno che l'utente non abbia chiesto esplicitamente un messaggio minimale"; }
                reason  = @{ type = "string"; description = "Spiegazione in italiano di cosa si sta inviando e a chi, da mostrare all'utente" }
                stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
            }
            required   = @("to")
        }
    }

    # Export diretto senza far transitare i dati grezzi nella conversazione (17/08/2026, bug
    # reale): il percorso normale exo_query -> generate_report fa passare OGNI riga due volte
    # nel contesto del modello (una come risultato di exo_query, una dentro l'input di
    # generate_report) - anche con il tetto di 1000 righe gia' aggiunto a Get-M365OpsMessageTrace,
    # un dataset grande resta comunque costoso/rischioso per il contesto. Questo strumento
    # invece esegue query+export in un solo passaggio lato server: il modello non vede MAI le
    # righe, solo un riepilogo finale (stesso testo restituito da generate_report). Aggiunto
    # apposta per i casi dove il volume e' alto (es. message trace su tenant/mailbox molto
    # attivi) - per un'analisi puntuale su poche righe resta piu' comodo exo_query normale.
    $fallbackTools += @{
        name = "generate_raw_export"
        description = "Genera un export (Excel/PDF) eseguendo query+scrittura file in un solo passaggio lato server, SENZA far transitare i dati grezzi nella conversazione - usa questo invece della sequenza exo_query poi generate_report quando il volume potenziale e' alto (es. message trace su un periodo lungo o senza filtro stretto, elenchi tenant-wide) perche' quella sequenza fa passare ogni riga due volte nel contesto del modello e puo' avvicinarsi al limite di contesto anche con poche migliaia di righe. Specifica SOLO 'cmdlet' (uno qualsiasi dell'elenco di exo_query), 'parameters' e 'title': il server esegue la query SENZA il tetto di righe pensato per proteggere la conversazione (fino a un tetto assoluto di sicurezza molto piu' alto) e scrive il file direttamente. La risposta che ricevi e' solo un riepilogo (conteggio righe + eventuali avvisi) - MAI i dati stessi: se dopo devi analizzare il contenuto nel dettaglio, fai una exo_query separata con un filtro piu' stretto (es. un singolo utente/periodo breve) per restare su un volume che puoi davvero vedere. SOLA LETTURA/EXPORT, eseguito subito, non serve conferma dell'utente."
        input_schema = @{
            type       = "object"
            properties = @{
                cmdlet     = @{ type = "string"; description = "Nome esatto della cmdlet, stesso elenco di exo_query" }
                parameters = @{ type = "object"; description = "Parametri della cmdlet, come per exo_query" }
                title      = @{ type = "string"; description = "Titolo del report/nome sezione, es. 'Message Trace 30 giorni - diego@contoso.com'" }
                format     = @{ type = "string"; enum = @("xlsx", "pdf", "both"); description = "Come in generate_report: default 'xlsx' se omesso" }
            }
            required   = @("cmdlet", "parameters", "title")
        }
    }

    # Equivalente Graph di "Explorer"/Threat Hunting (security.microsoft.com): a differenza di
    # /security/alerts_v2 e /security/incidents (letti benissimo con graph_api_call, che e' GET-
    # only), l'API di hunting query e' un POST anche se e' concettualmente SOLA LETTURA (esegue
    # una query KQL, non modifica nulla) - da qui uno strumento dedicato invece di forzarlo dentro
    # graph_api_call o passare da propose_graph_write (che tratterebbe una lettura come una
    # scrittura da confermare, inutile per l'utente). Richiede ThreatHunting.Read.All e Microsoft
    # Defender for Endpoint Plan 2 - su un tenant senza quella licenza restituisce un 403 che va
    # spiegato chiaramente all'utente, non ritentato con altri percorsi.
    $fallbackTools += @{
        name = "security_hunting_query"
        description = "Esegue una query KQL di SOLA LETTURA su Microsoft Defender (Advanced Hunting / 'Explorer' in security.microsoft.com) - dati di sicurezza su email, identita', dispositivi, cloud app (es. email in quarantena per tipo di minaccia, alert su un utente, IP di provenienza di un attacco). Richiede il permesso applicativo ThreatHunting.Read.All E la licenza Microsoft Defender for Endpoint Plan 2 sul tenant - se manca uno dei due, Graph risponde 403 con un messaggio che indica esattamente cosa manca: riportalo all'utente cosi' com'e' (spesso e' un problema di permesso/licenza mancante, non un tuo errore di query), non ritentare query diverse sperando che funzionino. Tabelle KQL principali disponibili: EmailEvents, EmailAttachmentInfo, EmailUrlInfo, AlertInfo, AlertEvidence, IdentityLogonEvents, DeviceEvents. Esempio di query: EmailEvents | where Timestamp > ago(7d) and ThreatTypes has 'Phish' | project Timestamp, SenderFromAddress, RecipientEmailAddress, Subject | take 50. Per alert/incidenti gia' aperti (piu' semplice, permessi diversi: SecurityAlert.Read.All / SecurityIncident.Read.All) usa invece graph_api_call su /security/alerts_v2 o /security/incidents."
        input_schema = @{
            type       = "object"
            properties = @{
                query = @{ type = "string"; description = "Query KQL completa, es. 'EmailEvents | where Timestamp > ago(7d) | take 50'" }
            }
            required   = @("query")
        }
    }

    # Lokka (il sottoprocesso MCP) richiede client credentials: sui tenant AuthMode='Delegated'
    # non e' mai disponibile. Questo NON significa pero' che graph_api_call sia indisponibile -
    # abbiamo comunque un token Graph valido (delegato) tramite Get-M365OpsToken, usato da tutte
    # le altre cmdlet Graph del modulo. Quindi graph_api_call/propose_graph_write restano offerti
    # SEMPRE: sotto, a runtime, scelgono da soli se passare da Lokka o da una chiamata diretta
    # con Invoke-M365OpsGraphRequest - il modello non deve saperlo ne' preoccuparsene.
    $isDelegatedTenant = $script:M365OpsContext -and $script:M365OpsContext.AuthMode -eq 'Delegated'
    if ($isDelegatedTenant) {
        $systemPrompt += "`n`nQuesto tenant e' in modalita' DELEGATA (login utente, nessuna App Registration): graph_api_call funziona comunque (chiamata diretta con lo stesso token delegato usato dagli altri strumenti), solo Lokka come processo esterno non e' in uso - per te come modello non cambia nulla nell'uso dello strumento."
    }

    # Storico prima del messaggio corrente: semplici turni di testo (mai tool_calls, quelli
    # esistono solo dentro un round di questa stessa chiamata) - validi cosi' come sono sia per
    # Claude sia per Azure, che accettano entrambi content=stringa per un turno senza strumenti.
    $messages = @($History | ForEach-Object { @{ role = $_.role; content = $_.text } })
    $messages += @{ role = "user"; content = $Prompt }

    # Solo questi restano fuori dal primo giro: si sovrappongono ai dati che graph_api_call
    # puo' gia' dare (motivo storico del gating - un test reale ha mostrato il modello
    # scegliere get_user_overview invece di graph_api_call quando disponibile fin da subito).
    # Tutti gli ALTRI strumenti "fallback" (Exchange, report, MFA, script personalizzati) NON
    # si sovrappongono a graph_api_call - tenerli fuori dal primo giro era un bug reale del
    # 17/08/2026: il modello concludeva "gli strumenti EXO/generate_report non sono disponibili
    # in questa sessione" invece di capire che sarebbero comparsi al giro successivo, e si
    # arrendeva subito con un messaggio che sembra una limitazione tecnica ma non lo e'.
    $roundOneShortcutNames = @('list_devices', 'list_noncompliant_devices', 'get_device_compliance_reasons', 'get_user_overview', 'get_group_overview', 'get_user_mfa_status')

    for ($round = 0; $round -lt $MaxRounds; $round++) {
        # Primo giro: Graph (via Lokka se disponibile, altrimenti diretto) PIU' ogni strumento
        # fallback che non compete con graph_api_call sugli stessi dati (Exchange, report, MFA,
        # script). Dal secondo giro in poi, anche le scorciatoie Graph-overlap sopra - cosi'
        # Graph resta garantito il primo tentativo SOLO dove davvero si sovrappongono.
        $currentTools = if ($round -eq 0) { $lokkaTools + @($fallbackTools | Where-Object { $_.name -notin $roundOneShortcutNames }) } else { $lokkaTools + $fallbackTools }

        if ($Provider -eq 'AzureOpenAI') {
            # --- Ramo Azure OpenAI (Chat Completions, tools/tool_choice) ---
            # Le stesse definizioni $currentTools (forma Claude, input_schema) vengono
            # riadattate qui alla forma OpenAI (type=function, function.parameters) invece
            # di mantenere due elenchi di tool separati e rischiare che si disallineino.
            $azureLongAppendix = ""
            $azureTools = @()
            foreach ($t in $currentTools) {
                $desc = $t.description
                if ($desc.Length -gt 1000) {
                    # Limite reale Azure: 1024 caratteri per descrizione tool (vedi .NOTES) -
                    # il contenuto integrale va nel system prompt, mai troncato a meta' cmdlet.
                    $azureLongAppendix += "`n`n--- Elenco completo per lo strumento '$($t.name)' ---`n$desc"
                    $shortDesc = $desc.Substring(0, 150) + "... (elenco completo qui sotto, sezione '$($t.name)')"
                } else {
                    $shortDesc = $desc
                }
                $azureTools += @{ type = "function"; function = @{ name = $t.name; description = $shortDesc; parameters = $t.input_schema } }
            }

            # Rete di sicurezza (18/08/2026, bug reale): un messaggio con 'role' mancante/nullo
            # in QUALSIASI punto dell'array fa rifiutare da Azure l'INTERA richiesta con 400
            # "Invalid type for messages[N].role... got null instead" - gia' successo una volta
            # per uno storico persistito corrotto (mitigato in Get-M365OpsChatHistory), ma
            # ripresentatosi su un tenant con storico pulito (probabilmente un'origine diversa,
            # non ancora individuata con certezza). Invece di continuare a inseguire ogni
            # possibile origine, si filtra qui, all'ultimo punto prima della chiamata reale,
            # cosi' un'eventuale voce malformata da QUALSIASI causa futura degrada a "quel turno
            # manca dal contesto" invece di far fallire l'intera risposta.
            $sanitizedMessages = @($messages | Where-Object { $_.role })
            if ($sanitizedMessages.Count -ne $messages.Count) {
                Write-M365OpsLog "Filtrate $($messages.Count - $sanitizedMessages.Count) voci messages con 'role' mancante prima della chiamata Azure OpenAI." -Level Error
            }
            $azureBodyObj = @{
                messages    = @(@{ role = "system"; content = ($systemPrompt + $azureLongAppendix) }) + $sanitizedMessages
                tools       = $azureTools
                tool_choice = "auto"
            }
            # I modelli piu' recenti (serie reasoning: o1/o3/o4 e famiglia gpt-5.x) rifiutano
            # "max_tokens" con un 400 e vogliono "max_completion_tokens" - non deducibile dal
            # nome del deployment (bug reale con gpt-5.4-mini). $azureUseMaxCompletionTokens
            # ricorda la scelta giusta tra un giro di tool-calling e il successivo, cosi' non
            # si ritenta e fallisce ad ogni round dello stesso ciclo.
            # 4000, non 2000: da quando propose_new_custom_script esiste, un round puo' dover
            # generare il codice completo di uno script PowerShell come argomento di un tool
            # call, non solo un breve JSON - sui modelli reasoning (gpt-5.x) i token di
            # ragionamento interno condividono lo stesso budget di max_completion_tokens, quindi
            # con 2000 il modello poteva esaurirlo TUTTO in ragionamento e restituire un
            # contenuto vuoto senza errore (bug reale osservato il 17/08/2026 - vedi il
            # controllo su content vuoto piu' sotto, che lo rende visibile invece di un
            # messaggio bianco silenzioso).
            if ($azureUseMaxCompletionTokens) { $azureBodyObj.max_completion_tokens = 4000 } else { $azureBodyObj.max_tokens = 4000 }

            # Normalizzazione endpoint: stesso bug reale di Invoke-M365OpsAgent.ps1 - il
            # portale Azure mostra sia l'endpoint "classico" della risorsa
            # (https://risorsa.openai.azure.com/) sia il piu' recente "Project endpoint" di
            # Azure AI Foundry (https://risorsa.services.ai.azure.com/openai/v1) - senza
            # normalizzare, la seconda forma produce un URL con "/openai/" duplicato.
            $azureEndpointRoot = $azureEndpoint.TrimEnd('/') -replace '/openai/v1$', '' -replace '/openai$', ''
            $azureUri = "$azureEndpointRoot/openai/deployments/$azureDeployment/chat/completions?api-version=2024-06-01"
            $azureHeaders = @{ "api-key" = $azureKey; "Content-Type" = "application/json" }
            # -Depth 20, non 12: bug reale del 17/08/2026, Azure ha rifiutato l'intero schema
            # strumenti con "'Bar Pie' is not of type 'array'" - lo schema di generate_report
            # (sections -> items -> chartFields -> items -> type -> enum) supera la profondita'
            # 12, e ConvertTo-Json senza avviso visibile in produzione serializza un array oltre
            # il limite chiamando .ToString() invece di ricorrere - per un array di stringhe
            # questo le unisce con uno spazio (@("Bar","Pie") diventa la stringa "Bar Pie"),
            # uno schema JSON invalido che Azure rifiuta in blocco. Riprodotto e verificato
            # localmente prima di alzare il limite: con -Depth 12 il bug si riproduce sempre,
            # con -Depth 20 mai. Vale anche per il ramo Claude sotto, stesso motivo.
            try {
                $response = Invoke-RestMethod -Method POST -Uri $azureUri -Headers $azureHeaders -Body ($azureBodyObj | ConvertTo-Json -Depth 20) -ErrorAction Stop
            }
            catch {
                $azureErrDetail = $_.ErrorDetails.Message
                if (-not $azureUseMaxCompletionTokens -and $azureErrDetail -match 'max_tokens' -and $azureErrDetail -match 'max_completion_tokens') {
                    $azureUseMaxCompletionTokens = $true
                    $azureBodyObj.Remove('max_tokens')
                    $azureBodyObj.max_completion_tokens = 4000
                    $response = Invoke-RestMethod -Method POST -Uri $azureUri -Headers $azureHeaders -Body ($azureBodyObj | ConvertTo-Json -Depth 20) -ErrorAction Stop
                } else {
                    throw "Azure OpenAI: richiesta fallita: $($_.Exception.Message)`n$azureErrDetail"
                }
            }
            $script:M365OpsAiCallCount.AzureOpenAI++

            # Visibilita' sul prompt caching automatico di Azure (17/08/2026, richiesta
            # esplicita dell'utente sui costi): niente da configurare per attivarlo, e' gia'
            # attivo di default sui modelli supportati e copre sia i messaggi sia le
            # definizioni degli strumenti - verificato dal vivo (95.9% di cache hit su un
            # prefisso stabile ripetuto). Loggato ad ogni round cosi' il risparmio reale e'
            # visibile nel tempo invece che fidarsi di una sola prova puntuale.
            $cachedTok = $response.usage.prompt_tokens_details.cached_tokens
            $promptTok = $response.usage.prompt_tokens
            if ($promptTok -gt 0) {
                $cachePct = [math]::Round(100 * $cachedTok / $promptTok, 1)
                Write-M365OpsLog "Azure OpenAI cache: $cachedTok/$promptTok token dalla cache ($cachePct%)"
            }

            if ($response.choices[0].finish_reason -ne "tool_calls" -or -not $response.choices[0].message.tool_calls) {
                $azureFinalText = $response.choices[0].message.content
                if (-not $azureFinalText) {
                    # Bug reale osservato il 17/08/2026: su un round senza tool_calls, un
                    # contenuto vuoto arrivava silenziosamente all'utente come messaggio bianco -
                    # nessun errore lanciato, nessuna spiegazione. finish_reason='length' con
                    # content vuoto è il segnale tipico di un modello reasoning (gpt-5.x) che ha
                    # esaurito TUTTO il budget di max_completion_tokens nel ragionamento interno
                    # prima di produrre output visibile - qui reso visibile invece di nascosto.
                    Write-M365OpsLog "Azure OpenAI: risposta finale vuota (finish_reason=$($response.choices[0].finish_reason), completion_tokens=$($response.usage.completion_tokens), reasoning_tokens=$($response.usage.completion_tokens_details.reasoning_tokens))" -Level Error
                    $azureFinalText = "Il modello non ha prodotto una risposta (motivo interno: $($response.choices[0].finish_reason)) - probabile esaurimento del budget di token su una richiesta complessa. Prova a riformulare in modo piu' semplice o a spezzarla in piu' passaggi."
                }
                return [pscustomobject]@{ Text = $azureFinalText; PendingWrite = $pendingWrite; Attachments = $reportAttachments }
            }

            $messages += @{ role = "assistant"; content = $response.choices[0].message.content; tool_calls = $response.choices[0].message.tool_calls }

            # Normalizza i tool_calls di Azure nella STESSA forma (name/input/id) del blocco
            # tool_use di Claude, cosi' lo switch di dispatch sotto resta condiviso tra i due
            # provider invece di duplicare centinaia di righe di logica per ciascun tool.
            $normalizedBlocks = @($response.choices[0].message.tool_calls | ForEach-Object {
                [pscustomobject]@{
                    name  = $_.function.name
                    id    = $_.id
                    input = if ($_.function.arguments) { $_.function.arguments | ConvertFrom-Json } else { [pscustomobject]@{} }
                }
            })
        }
        else {
            # --- Ramo Claude (Anthropic Messages API, invariato) ---
            # Stessa rete di sicurezza del ramo Azure sopra (vedi commento li'): mai lasciar
            # passare un messaggio con 'role' mancante/nullo.
            $sanitizedMessages = @($messages | Where-Object { $_.role })
            $body = @{
                model      = "claude-sonnet-4-5"
                # 4000, non 2000: propose_new_custom_script puo' dover generare il codice
                # completo di uno script PowerShell come argomento, non solo un breve JSON.
                max_tokens = 4000
                system     = $systemPrompt
                tools      = $currentTools
                messages   = $sanitizedMessages
            } | ConvertTo-Json -Depth 20

            $response = Invoke-RestMethod -Method POST -Uri "https://api.anthropic.com/v1/messages" -Headers @{
                "x-api-key"         = $apiKey
                "anthropic-version" = "2023-06-01"
                "Content-Type"      = "application/json"
            } -Body $body
            $script:M365OpsAiCallCount.Claude++

            if ($response.stop_reason -ne "tool_use") {
                $textBlock = $response.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1
                $claudeFinalText = $textBlock.text
                if (-not $claudeFinalText) {
                    # Stesso controllo del ramo Azure: mai lasciare che un contenuto vuoto arrivi
                    # all'utente come messaggio bianco senza spiegazione.
                    Write-M365OpsLog "Claude: risposta finale vuota (stop_reason=$($response.stop_reason))" -Level Error
                    $claudeFinalText = "Il modello non ha prodotto una risposta (motivo interno: $($response.stop_reason)) - prova a riformulare in modo piu' semplice o a spezzarla in piu' passaggi."
                }
                return [pscustomobject]@{ Text = $claudeFinalText; PendingWrite = $pendingWrite; Attachments = $reportAttachments }
            }

            $messages += @{ role = "assistant"; content = $response.content }
            $normalizedBlocks = @($response.content | Where-Object { $_.type -eq "tool_use" })
        }

        $toolResults = @()
        foreach ($block in $normalizedBlocks) {
            $inputSummary = if ($block.input.path) { $block.input.path } elseif ($block.input.cmdlet) { $block.input.cmdlet } elseif ($block.input.topic) { $block.input.topic } elseif ($block.input.title) { $block.input.title }
            $callLabel = "$($block.name)$(if($inputSummary){" $inputSummary"})"
            $attemptedCalls += $callLabel
            Write-Host "[AgentTools] chiamato: $callLabel" -ForegroundColor Cyan
            Write-M365OpsLog "Tool AI chiamato: $callLabel"

            $output = try {
                switch ($block.name) {
                    "list_devices" { Get-M365OpsManagedDevices | ConvertTo-Json -Depth 5 -Compress }
                    "list_noncompliant_devices" { Get-M365OpsManagedDevices -NonCompliantOnly | ConvertTo-Json -Depth 5 -Compress }
                    "get_device_compliance_reasons" { Get-M365OpsDeviceComplianceReasons -Id $block.input.deviceId | ConvertTo-Json -Depth 5 -Compress }
                    "get_user_overview" { Get-M365OpsUserOverview -Upn $block.input.upn | ConvertTo-Json -Depth 6 -Compress }
                    "get_group_overview" { Get-M365OpsGroupOverview -GroupName $block.input.groupName | ConvertTo-Json -Depth 6 -Compress }
                    "get_user_mfa_status" { Get-M365OpsUserMfaStatus -Upn $block.input.upn | ConvertTo-Json -Depth 6 -Compress }
                    "propose_mfa_reset" {
                        if ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa (reset MFA) in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $pendingWrite = @{
                                Kind       = 'MfaReset'
                                Upn        = $block.input.upn
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "lookup_ms_docs" { Invoke-M365OpsLookupMsDocs -Topic $block.input.topic }
                    "generate_report" {
                        $sections = @(@($block.input.sections) | ForEach-Object { @{ Name = $_.name; Data = @($_.data); ChartFields = @($_.chartFields) } })
                        $totalRows = ($sections | ForEach-Object { $_.Data.Count } | Measure-Object -Sum).Sum
                        # Default xlsx (17/08/2026, richiesta esplicita): se l'AI non passa 'format'
                        # o passa qualcosa di non riconosciuto, non si assume MAI pdf da sola - xlsx
                        # non dipende da Edge headless, quindi non puo' fallire per un problema di
                        # rendering esterno ai dati stessi (bug reale osservato: "Edge non ha
                        # prodotto il file" ha fatto perdere un intero report i cui dati erano gia'
                        # raccolti correttamente).
                        $formats = switch ([string]$block.input.format) {
                            'pdf' { @('pdf') }
                            'both' { @('xlsx', 'pdf') }
                            default { @('xlsx') }
                        }
                        if ($sections.Count -eq 0 -or $totalRows -eq 0) {
                            "Nessun dato fornito in nessuna sezione - raccogli prima i dati con graph_api_call/exo_query (l'elenco completo, non un riassunto), poi richiama generate_report con 'sections' valorizzato. Una singola sezione vuota va bene se e' un risultato legittimo (es. nessuna regola di forwarding), ma non tutte le sezioni vuote insieme."
                        } else {
                            try {
                                $result = Export-M365OpsDataReport -Sections $sections -Title $block.input.title -Formats $formats
                                $script:LastReportPath = if ($result.PdfPath) { $result.PdfPath } else { $result.XlsxPath }
                                # Solo i file DAVVERO generati (uno dei due puo' essere $null se non
                                # richiesto, o se quel formato specifico e' fallito senza far perdere
                                # l'altro - vedi Export-M365OpsDataReport).
                                $reportAttachments = @()
                                if ($result.XlsxPath) { $reportAttachments += @{ FileName = (Split-Path -Leaf $result.XlsxPath) } }
                                if ($result.PdfPath) { $reportAttachments += @{ FileName = (Split-Path -Leaf $result.PdfPath) } }
                                $filesNote = @(if ($result.XlsxPath) { "Excel" }; if ($result.PdfPath) { "PDF" }) -join " e "
                                $warnNote = if ($result.Warnings) { " Attenzione: $($result.Warnings -join '; ')." } else { "" }
                                $sectionsNote = (($result.Sections | ForEach-Object { "$($_.Name): $($_.RowCount) righe" })) -join ', '
                                # Niente percorso su disco nel testo: i file sono gia' allegati/scaricabili
                                # nella GUI (vedi Attachments), indicare un path assoluto qui non serve
                                # all'utente e l'AI tenderebbe solo a ripeterlo nella risposta finale.
                                "Report generato con successo: $($result.RowCount) righe totali su $($sections.Count) sezioni ($sectionsNote). $filesNote gia' allegato/i e scaricabile/i nell'interfaccia.$warnNote Nella tua risposta conferma solo che il report e' pronto (specifica il formato generato) ed elenca le sezioni, non indicare nomi di file o percorsi."
                            }
                            catch {
                                "Generazione report fallita: $($_.Exception.Message)"
                            }
                        }
                    }
                    "generate_raw_export" {
                        if ($block.input.cmdlet -notin $exoReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito (stesso elenco di exo_query)."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            # Tetto assoluto di sicurezza, non il tetto "conversazione" di 1000: qui i
                            # dati non entrano mai nel contesto del modello, quindi ha senso un limite
                            # molto piu' alto - resta comunque un limite (non illimitato) per non
                            # rischiare un export che impiega minuti/produce un file enorme per un
                            # errore di query (es. filtro dimenticato su un tenant molto attivo).
                            if ((Get-Command $block.input.cmdlet).Parameters.ContainsKey('MaxTotalRows')) {
                                $params['MaxTotalRows'] = 50000
                            }
                            $formats = switch ([string]$block.input.format) {
                                'pdf' { @('pdf') }
                                'both' { @('xlsx', 'pdf') }
                                default { @('xlsx') }
                            }
                            try {
                                $script:M365OpsLastReportWarnings = $null
                                $data = @(& $block.input.cmdlet @params)
                                $cmdletWarnings = $script:M365OpsLastReportWarnings
                                if ($data.Count -eq 0) {
                                    "Nessun dato trovato per questa query - nessun file generato. Verifica i parametri (es. periodo, filtro) prima di riprovare."
                                } else {
                                    $sections = @(@{ Name = $block.input.title; Data = $data })
                                    $result = Export-M365OpsDataReport -Sections $sections -Title $block.input.title -Formats $formats
                                    $script:LastReportPath = if ($result.PdfPath) { $result.PdfPath } else { $result.XlsxPath }
                                    $reportAttachments = @()
                                    if ($result.XlsxPath) { $reportAttachments += @{ FileName = (Split-Path -Leaf $result.XlsxPath) } }
                                    if ($result.PdfPath) { $reportAttachments += @{ FileName = (Split-Path -Leaf $result.PdfPath) } }
                                    $filesNote = @(if ($result.XlsxPath) { "Excel" }; if ($result.PdfPath) { "PDF" }) -join " e "
                                    $allWarnings = @($cmdletWarnings) + @($result.Warnings) | Where-Object { $_ }
                                    $warnNote = if ($allWarnings) { " Attenzione: $($allWarnings -join '; ')." } else { "" }
                                    "Export generato con successo: $($data.Count) righe (dati MAI passati nella conversazione). $filesNote gia' allegato/i e scaricabile/i nell'interfaccia.$warnNote Nella tua risposta conferma solo che il file e' pronto e il conteggio righe, non indicare nomi di file o percorsi - e non descrivere il CONTENUTO dei dati, perche' non li hai visti."
                                }
                            }
                            catch {
                                "Export fallito: $($_.Exception.Message)"
                            }
                        }
                    }
                    "propose_send_report_email" {
                        if ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa (invio email) in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } elseif (-not $script:LastReportPath -or -not (Test-Path $script:LastReportPath)) {
                            "Nessun report generato in questa conversazione (o il file non e' piu' presente) - genera prima il report con generate_report/generate_raw_export, poi proponi l'invio."
                        } else {
                            $pendingWrite = @{
                                Kind           = 'EmailReport'
                                To             = $block.input.to
                                Subject        = if ($block.input.subject) { $block.input.subject } else { "Report M365Ops" }
                                Body           = if ($block.input.body) { $block.input.body } else { "In allegato il report generato da M365Ops." }
                                # Passato esplicitamente nell'oggetto restituito, MAI riletto da
                                # Server.ps1 come $script:LastReportPath: quella variabile vive
                                # nello scope del MODULO qui dentro, ma Server.ps1 non fa parte
                                # del modulo (e' solo un consumer) - il suo $script: e' un altro
                                # scope, sempre $null li' anche quando qui e' valorizzato (bug
                                # reale osservato il 17/08/2026, stessa classe di errore gia'
                                # vista piu' volte in questo progetto per lo stesso motivo).
                                AttachmentPath = $script:LastReportPath
                                Reason         = $block.input.reason
                                StepNumber     = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps     = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "graph_api_call" {
                        if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
                            # Lokka non e' mai disponibile in modalita' delegata (richiede client
                            # credentials) - chiamata diretta con lo stesso token delegato usato
                            # dal resto del modulo, stesso principio di ogni cmdlet Graph esistente.
                            $directPath = $block.input.path
                            if ($block.input.queryParams) {
                                $qp = @()
                                $block.input.queryParams.PSObject.Properties | ForEach-Object { $qp += "$([uri]::EscapeDataString($_.Name))=$([uri]::EscapeDataString([string]$_.Value))" }
                                if ($qp.Count -gt 0) { $directPath = "$directPath`?$($qp -join '&')" }
                            }
                            Invoke-M365OpsGraphRequest -Method GET -Path $directPath | ConvertTo-Json -Depth 8 -Compress
                        } else {
                            $lokkaArgs = @{ apiType = "graph"; method = "get"; path = $block.input.path }
                            if ($block.input.queryParams) { $lokkaArgs.queryParams = $block.input.queryParams }
                            $lokkaResult = Invoke-M365OpsLokkaTool -ToolName "Lokka-Microsoft" -Arguments $lokkaArgs
                            (($lokkaResult.content | ForEach-Object { $_.text }) -join "`n")
                        }
                    }
                    "propose_graph_write" {
                        if ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $pendingWrite = @{
                                Kind       = 'Graph'
                                Method     = $block.input.method
                                Path       = $block.input.path
                                Body       = ConvertTo-M365OpsHashtable $block.input.body
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "exo_query" {
                        if ($block.input.cmdlet -notin $exoReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per exo_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            $script:M365OpsLastReportWarnings = $null
                            $queryResult = & $block.input.cmdlet @params | ConvertTo-Json -Depth 6 -Compress
                            # Alcune cmdlet (es. Get-M365OpsMessageTrace) troncano un risultato troppo
                            # grande per non far esplodere il contesto del modello (bug reale 17/08/2026:
                            # una query di 30 giorni senza filtro ha superato da sola il limite token di
                            # Azure) - se e' successo, il modello deve saperlo per dirlo all'utente invece
                            # di presentare un dato parziale come completo.
                            if ($script:M365OpsLastReportWarnings) {
                                $queryResult = "$queryResult`n`n[AVVISO: $($script:M365OpsLastReportWarnings -join '; ')]"
                            }
                            $queryResult
                        }
                    }
                    "intune_query" {
                        if ($block.input.cmdlet -notin $intuneReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per intune_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            try {
                                & $block.input.cmdlet @params | ConvertTo-Json -Depth 8 -Compress
                            }
                            catch {
                                "Query Intune fallita: $($_.Exception.Message)"
                            }
                        }
                    }
                    "sharepoint_query" {
                        if ($block.input.cmdlet -notin $sharePointReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per sharepoint_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            try {
                                & $block.input.cmdlet @params | ConvertTo-Json -Depth 6 -Compress
                            }
                            catch {
                                # L'errore piu' probabile qui, finche' il permesso SharePoint non
                                # e' concesso, e' "Unauthorized" - passato cosi' com'e' (vedi
                                # descrizione dello strumento) invece di un messaggio generico.
                                "Query SharePoint fallita: $($_.Exception.Message)"
                            }
                        }
                    }
                    "kb_query" {
                        # TenantName SEMPRE da $script:M365OpsContext.Name (tenant realmente
                        # attivo in questo momento), MAI da un valore che l'AI potrebbe passare -
                        # lo schema del tool infatti non espone nemmeno un parametro tenant. E'
                        # l'unica garanzia strutturale di isolamento: per costruzione non esiste
                        # un modo di chiedere a questo strumento la Knowledge Base di un tenant
                        # diverso da quello attivo ora.
                        if (-not $script:M365OpsContext -or -not $script:M365OpsContext.Name) {
                            "Nessun tenant attivo - impossibile leggere la Knowledge Base."
                        } else {
                            try {
                                Get-M365OpsKnowledgeDocumentText -TenantName $script:M365OpsContext.Name -FileName $block.input.fileName
                            }
                            catch {
                                "Lettura Knowledge Base fallita: $($_.Exception.Message)"
                            }
                        }
                    }
                    "compliance_query" {
                        if ($block.input.cmdlet -notin $complianceReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per compliance_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            try {
                                & $block.input.cmdlet @params | ConvertTo-Json -Depth 6 -Compress
                            }
                            catch {
                                # "term not recognized" qui significa quasi sempre ruolo Purview
                                # mancante (Connect-IPPSSession espone solo i cmdlet coperti dai
                                # ruoli RBAC assegnati), non un errore di query - vedi descrizione
                                # dello strumento.
                                "Query Compliance fallita: $($_.Exception.Message)"
                            }
                        }
                    }
                    "teams_query" {
                        # BUG SERIO trovato dal vivo il 18/08/2026 durante uno stress test: questo
                        # case non esisteva affatto - "teams_query" e' dichiarato nello schema
                        # (l'AI lo vede come strumento disponibile e lo chiama per davvero, vedi
                        # log "Tool AI chiamato: teams_query ...") ma ogni chiamata cadeva nel
                        # 'default' dello switch sotto, che restituisce "Tool sconosciuto" -
                        # l'AI riceveva quella stringa come risultato e la riportava all'utente
                        # come "strumento non disponibile", anche quando $teamsReadAllowlist e
                        # Get-M365OpsTeamsPolicies/Get-M365OpsTeamsExternalAccessConfig esistono
                        # e funzionano perfettamente se chiamati direttamente. Le liste/canali/
                        # membri di base non erano mai colpite perche' l'AI le recupera quasi
                        # sempre via graph_api_call (Teams espone quei dati anche su Graph
                        # standard) - solo le due cmdlet Cs*-only (Policies, ExternalAccessConfig)
                        # passano per forza da qui, quindi il gap e' rimasto invisibile finora.
                        if ($block.input.cmdlet -notin $teamsReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per teams_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            try {
                                & $block.input.cmdlet @params | ConvertTo-Json -Depth 6 -Compress
                            }
                            catch {
                                # "Access Denied" qui significa quasi sempre il permesso Application
                                # mancante "Skype and Teams Tenant Admin API" (sezione 4.4 della
                                # guida), non un problema della query - vedi descrizione strumento.
                                "Query Teams fallita: $($_.Exception.Message)"
                            }
                        }
                    }
                    "propose_exo_write" {
                        if ($block.input.cmdlet -notin $exoWriteAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per propose_exo_write."
                        } elseif ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            $pendingWrite = @{
                                Kind       = 'Exo'
                                Cmdlet     = $block.input.cmdlet
                                Parameters = $params
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "propose_intune_write" {
                        if ($block.input.cmdlet -notin $intuneWriteAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per propose_intune_write."
                        } elseif ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            $pendingWrite = @{
                                Kind       = 'Intune'
                                Cmdlet     = $block.input.cmdlet
                                Parameters = $params
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "propose_sharepoint_write" {
                        if ($block.input.cmdlet -notin $sharePointWriteAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per propose_sharepoint_write."
                        } elseif ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            $pendingWrite = @{
                                Kind       = 'SharePoint'
                                Cmdlet     = $block.input.cmdlet
                                Parameters = $params
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "propose_teams_write" {
                        if ($block.input.cmdlet -notin $teamsWriteAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per propose_teams_write."
                        } elseif ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            $pendingWrite = @{
                                Kind       = 'Teams'
                                Cmdlet     = $block.input.cmdlet
                                Parameters = $params
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "security_hunting_query" {
                        try {
                            $huntResult = Invoke-M365OpsGraphRequest -Method POST -Path "/security/runHuntingQuery" -Body @{ Query = $block.input.query } -Beta
                            $huntResult | ConvertTo-Json -Depth 8 -Compress
                        }
                        catch {
                            # Il messaggio di errore di Graph qui e' gia' auto-esplicativo (indica
                            # esattamente il permesso applicativo mancante, es. ThreatHunting.Read.All)
                            # - passato cosi' com'e' invece di un messaggio generico, cosi' l'utente sa
                            # subito cosa aggiungere all'App Registration senza dover indagare.
                            "Query hunting fallita: $($_.Exception.Message)"
                        }
                    }
                    "custom_script_query" {
                        if ($block.input.cmdlet -notin $customReadAllowlist) {
                            "Script '$($block.input.cmdlet)' non e' nell'elenco consentito per custom_script_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            try {
                                & $block.input.cmdlet @params | ConvertTo-Json -Depth 6 -Compress
                            }
                            catch {
                                # Script "home made", non del modulo core - piu' probabile che abbia
                                # un bug reale. Diagnosi AI con proposta di correzione, invece del
                                # solo messaggio di errore grezzo passato agli altri strumenti.
                                $scriptPath = Join-Path $script:M365OpsModuleRoot "Scripts\Custom\$($block.input.cmdlet).ps1"
                                $triage = Invoke-M365OpsErrorTriage -ErrorMessage $_.Exception.Message `
                                    -Context "Script personalizzato '$($block.input.cmdlet)' (sola lettura) chiamato con parametri $(($params | ConvertTo-Json -Compress -Depth 3))" `
                                    -SourceFile $scriptPath -Provider $Provider
                                if (-not $pendingWrite -and (Test-M365OpsFixApplicable $triage $script:M365OpsModuleRoot)) {
                                    $pendingWrite = @{ Kind = 'ApplyFix'; Triage = $triage; Reason = $triage.explanation }
                                }
                                Format-M365OpsErrorTriage $triage
                            }
                        }
                    }
                    "propose_custom_script_write" {
                        if ($block.input.cmdlet -notin $customWriteAllowlist) {
                            "Script '$($block.input.cmdlet)' non e' nell'elenco consentito per propose_custom_script_write."
                        } elseif ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            $pendingWrite = @{
                                Kind       = 'Custom'
                                Cmdlet     = $block.input.cmdlet
                                Parameters = $params
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                            }
                            "Proposta registrata. NON eseguirla, NON dire all'utente che e' stata fatta: nella tua risposta finale spiega chiaramente cosa proponi di fare e di che si aspetti una richiesta di conferma separata."
                        }
                    }
                    "propose_new_custom_script" {
                        if ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $newName = [string]$block.input.name
                            $newCode = [string]$block.input.code
                            $newMode = [string]$block.input.mode

                            # Validazioni SERVER-SIDE, non ci si fida del solo giudizio del modello: un
                            # nome fuori convenzione o un codice che non passerebbe comunque la scoperta
                            # automatica (Get-M365OpsCustomScriptCatalog) verrebbe salvato per niente,
                            # scoperto solo dopo il riavvio - meglio rifiutare subito con un motivo chiaro
                            # che il modello puo' correggere nello stesso turno.
                            if ($newName -notmatch '^[A-Z][a-zA-Z]*-M365Ops[A-Za-z0-9]+$') {
                                "Rifiutato: nome '$newName' non valido - deve seguire la convenzione Verbo-M365OpsNome (es. Get-M365OpsQualcosa), stessa di ogni cmdlet del modulo."
                            }
                            elseif (Test-Path (Join-Path $script:M365OpsModuleRoot "Scripts\Custom\$newName.ps1")) {
                                "Rifiutato: esiste gia' uno script chiamato '$newName' - scegli un nome diverso, oppure se l'intento e' modificarlo dillo esplicitamente all'utente invece di proporne uno nuovo."
                            }
                            else {
                                $parseErrors = $null
                                $tokens = $null
                                $ast = [System.Management.Automation.Language.Parser]::ParseInput($newCode, [ref]$tokens, [ref]$parseErrors)

                                if ($parseErrors -and $parseErrors.Count -gt 0) {
                                    "Rifiutato: il codice ha errori di sintassi PowerShell, non verra' mai salvato cosi'. Dettaglio:`n" + (($parseErrors | ForEach-Object { "- riga $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n") + "`nCorreggi e riprova."
                                }
                                else {
                                    $funcDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
                                    $matchingFunc = $funcDefs | Where-Object { $_.Name -eq $newName }
                                    $modePattern = '(?im)^\s*Mode:\s*' + [regex]::Escape($newMode) + '\s*$'

                                    if (-not $matchingFunc) {
                                        "Rifiutato: il codice deve definire ESATTAMENTE una funzione chiamata '$newName' (nome file = nome funzione, stessa convenzione di ogni cmdlet del modulo)."
                                    }
                                    elseif ($newCode -notmatch '(?im)^\s*\.SYNOPSIS\s*$') {
                                        "Rifiutato: manca il blocco .SYNOPSIS nell'help - e' l'unica descrizione che l'AI user' per usarlo in futuro, obbligatorio."
                                    }
                                    elseif ($newCode -notmatch $modePattern) {
                                        "Rifiutato: il codice deve contenere in '.NOTES' la riga 'Mode: $newMode', identica al parametro mode dichiarato qui - altrimenti lo script verrebbe salvato ma poi ignorato dal catalogo al riavvio (tag Mode mancante o diverso)."
                                    }
                                    else {
                                        # Non un blocco tecnico (in PowerShell puro non e' praticabile un
                                        # sandboxing reale) - solo un avviso ben visibile nella conferma,
                                        # cosi' chi legge il codice prima di dire "si" sa dove guardare con
                                        # piu' attenzione, senza impedire un uso legittimo di questi comandi.
                                        $dangerousPatterns = @('Remove-Item', 'Invoke-Expression', 'DownloadString', 'Stop-Computer', 'Restart-Computer', 'Format-Volume', 'Clear-Disk', 'Remove-Mailbox', 'Remove-MsolUser', 'Remove-AzureADUser')
                                        $foundDangerous = @($dangerousPatterns | Where-Object { $newCode -match [regex]::Escape($_) })

                                        $pendingWrite = @{
                                            Kind       = 'NewCustomScript'
                                            Name       = $newName
                                            Code       = $newCode
                                            Mode       = $newMode
                                            Reason     = $block.input.reason
                                            Warnings   = $foundDangerous
                                            StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                            TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
                                        }
                                        "Proposta registrata (sintassi e convenzione gia' validate). NON dire all'utente che il file esiste gia': nella tua risposta finale spiega chiaramente cosa proponi di creare e perche', e che serve conferma esplicita prima che lo script esista davvero e diventi uno strumento reale."
                                    }
                                }
                            }
                        }
                    }
                    default { "Tool sconosciuto: $($block.name)" }
                }
            }
            catch {
                Write-M365OpsLog "Tool AI fallito: $callLabel - $($_.Exception.Message)" -Level Error
                "Errore eseguendo $($block.name): $($_.Exception.Message)"
            }
            Write-M365OpsLog "Tool AI completato: $callLabel"

            # Bug della stessa famiglia di GET /api/chat/history (16/08/2026): un tool di sola
            # lettura (list_devices, exo_query, ecc.) che pipeIa uno zero risultati dentro
            # ConvertTo-Json restituisce $null vero, non "[]" - [string]$null sotto non lancia
            # un errore, ma diventa silenziosamente una stringa VUOTA nel risultato mandato
            # all'AI, indistinguibile da un tool fallito. Qui invece deve arrivare un "[]"
            # esplicito, cosi' il modello capisce chiaramente "zero risultati trovati" (es.
            # nessun dispositivo non conforme, nessuna mailbox con inoltro configurato - un
            # esito perfettamente normale) invece di sospettare un errore silenzioso.
            if ($null -eq $output) { $output = "[]" }

            $toolResults += if ($Provider -eq 'AzureOpenAI') {
                @{ tool_call_id = $block.id; role = "tool"; content = [string]$output }
            } else {
                @{ type = "tool_result"; tool_use_id = $block.id; content = [string]$output }
            }
        }

        if ($Provider -eq 'AzureOpenAI') {
            # Azure: ogni risultato e' un messaggio top-level a se' (role=tool), non
            # incapsulato in un unico messaggio "user" come nel formato Claude.
            $messages += $toolResults
        } else {
            $messages += @{ role = "user"; content = $toolResults }
        }
    }

    $attemptSummary = if ($attemptedCalls) { "- " + (($attemptedCalls | Select-Object -Unique) -join "`n- ") } else { "(nessuna chiamata effettuata)" }
    return [pscustomobject]@{
        Text = @"
Non sono riuscito a dare una risposta completa entro $MaxRounds passaggi. Ecco cosa ho provato:
$attemptSummary

Motivo piu' probabile: la domanda richiede dati che Microsoft Graph non espone direttamente (es. permessi di mailbox, altri dati Exchange-specifici), oppure serve iterare su troppi elementi per il numero di passaggi disponibili. Se riguarda mailbox condivise o permessi di posta, servirebbe collegare Exchange Online PowerShell (non ancora disponibile in questo sistema).
"@
        PendingWrite = $pendingWrite
        Attachments  = $reportAttachments
    }
}
