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
        # Nota "consulta la guida su .../guida" aggiunta il 21/08/2026 (richiesto esplicitamente
        # dall'utente su un PC pulito: "quando l'app parte e non e' configurata la sua guida deve
        # essere raggiungibile... o non fa perche' manca l'IA?"): prima di questo fix, senza
        # nessuna chiave AI configurata, anche la domanda piu' semplice sulla guida stessa
        # falliva con questo errore - un problema dell'uovo e della gallina. La guida e' ora
        # raggiungibile anche a zero configurazione via /guida (sezione 17.20 della guida
        # stessa). $Port non e' un parametro di questa funzione (vive nel modulo, non in
        # Server.ps1) - la porta reale si legge da Config\active-port.txt, scritta da
        # Server.ps1 all'avvio apposta per questo genere di lettura incrociata.
        $guidePortHint = try { (Get-Content (Join-Path $script:M365OpsModuleRoot 'Config\active-port.txt') -Raw -ErrorAction Stop).Trim() } catch { '8743' }
        if (-not ($azureKey -and $azureEndpoint -and $azureDeployment)) {
            throw "Servono AZURE_OPENAI_KEY, AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT come variabili d'ambiente (tab Motore AI). Nel frattempo puoi comunque consultare la guida di configurazione direttamente da http://localhost:$guidePortHint/guida, senza bisogno di nessuna chiave AI."
        }
    } else {
        $apiKey = Get-M365OpsSecret -Name 'ANTHROPIC_API_KEY'
        if (-not $apiKey) {
            $guidePortHint = try { (Get-Content (Join-Path $script:M365OpsModuleRoot 'Config\active-port.txt') -Raw -ErrorAction Stop).Trim() } catch { '8743' }
            throw "Variabile d'ambiente ANTHROPIC_API_KEY non trovata (tab Motore AI). Nel frattempo puoi comunque consultare la guida di configurazione direttamente da http://localhost:$guidePortHint/guida, senza bisogno di nessuna chiave AI."
        }
    }

    $pendingWrite = $null
    $reportAttachments = $null
    $attemptedCalls = @()
    # Sorgenti reali (Lokka/CLI Microsoft 365/moduli interni) usate in QUESTA risposta -
    # richiesto esplicitamente dall'utente il 26/08/2026, mostrato all'utente in fondo alla
    # risposta finale e loggato per ogni singola chiamata (vedi Get-M365OpsToolSourceLabel,
    # Private) - lista, non hashset, per preservare l'ordine di primo utilizzo; deduplicata
    # solo al momento di comporre la nota finale.
    $sourceLabelsUsed = @()

    # CLI Microsoft 365 come sostituto PROATTIVO di Graph quando la sessione Graph delegata
    # generica non e' attiva (23/08/2026, richiesto esplicitamente dal vivo dall'utente dopo il
    # bug del fallback reattivo v0.9.68 - "senza graph attivo bisogna usare il cli per ogni cosa
    # in cui il cli puo' dare una risposta, consideralo un tool idempotente a graph laddove ha
    # possibilita'"): calcolato QUI, PRIMA del system prompt, cosi' l'AI lo sa fin dal primo
    # tentativo invece di scoprirlo solo dopo un tentativo Graph fallito (v0.9.68 restava solo
    # reattivo, e copriva solo le letture - non le scritture, dove un tentativo fallito e poi
    # ritentato e' anche piu' costoso/confuso per l'utente). Riusa lo stesso controllo (nome
    # 'CLI-Microsoft365' in McpServers) gia' usato piu' sotto per dichiarare i tool cli_m365_* -
    # duplicato qui deliberatamente invece di riordinare tutta la funzione: e' una lettura da
    # file innocua, il rischio di una modifica piu' ampia non ne vale la pena.
    $cliM365ConfiguredEarly = $false
    try { $cliM365ConfiguredEarly = [bool](Get-M365OpsMcpServers | Where-Object { $_.Name -eq 'CLI-Microsoft365' }) } catch { }
    $graphDelegatedSessionActive = $true
    if ($script:M365OpsContext -and $script:M365OpsContext.AuthMode -eq 'Delegated') {
        $cachedDelegated = $script:M365OpsTokenCache[$script:M365OpsContext.Name]
        $graphDelegatedSessionActive = [bool]($cachedDelegated -and $cachedDelegated.Delegated -and ($cachedDelegated.Delegated.AccessToken -or $cachedDelegated.Delegated.RefreshToken))
    }
    $cliM365ProactivePreference = ""
    if (-not $graphDelegatedSessionActive -and $cliM365ConfiguredEarly) {
        $cliM365ProactivePreference = "`nATTENZIONE PROATTIVA PER QUESTA CONVERSAZIONE: la sessione Graph delegata generica NON risulta attiva ORA per questo tenant (graph_api_call/propose_graph_write falliranno subito con 'Nessuna sessione delegata attiva' - non e' un'ipotesi, e' gia' verificato). CLI Microsoft 365 e' pero' gia' configurato e potrebbe gia' essere connesso in modo INDIPENDENTE (login separato, vedi sotto): per QUALUNQUE lettura O SCRITTURA che rientra nel suo dominio (Entra ID/Outlook/Planner/OneDrive/Purview-ricerca-conformita'/Teams-lato-app-o-chat), trattalo come EQUIVALENTE a Graph e usa DIRETTAMENTE cli_m365_run_command o propose_cli_m365_command come primo tentativo, PRIMA di graph_api_call/propose_graph_write - non ha senso tentare un percorso che sai gia' in anticipo fallire. Resta valido tutto il resto invariato: SharePoint mai su CLI365 (i comandi 'spo' falliscono sempre su questa integrazione), Exchange profondo/Intune/criteri Teams mai su CLI365 (solo sui moduli PowerShell dedicati) - se l'argomento e' fuori dal dominio di CLI365 o anche CLI365 fallisce, spiega chiaramente che serve il login Graph generico ('Accedi con il mio utente', tab Tenant)."
    }

    $systemPrompt = @"
Per leggere dati dal tenant, usa 'graph_api_call' (via Lokka): e' lo strumento primario, copre qualunque endpoint Graph.
Se compaiono anche altri strumenti di lettura (list_devices, get_user_overview, exo_query, ecc.), sono un FALLBACK disponibile solo perche' il primo tentativo con Lokka non e' bastato - usali solo per quello che Lokka non e' riuscito a darti.
Se sono disponibili gli strumenti cli_m365_* (CLI Microsoft 365, secondo connettore oltre a Lokka - non tutti i tenant lo hanno configurato): stessa logica di priorita', mai il primo tentativo. Provali SOLO per Entra ID/Outlook/Planner/OneDrive/Purview-ricerca-conformita'/Teams-lato-app-o-chat quando graph_api_call non ha gia' dato il dato cercato (es. un endpoint Graph che non esiste per quel caso specifico) - MAI per Exchange profondo (mailbox/gruppi/regole, resta esclusivamente su exo_query), Intune (resta esclusivamente sugli strumenti Intune dedicati) o criteri/policy Teams (resta esclusivamente su teams_query) - questi tre restano sempre e solo sui moduli PowerShell interni, cli_m365_* non li copre affatto. SharePoint: MAI cli_m365_*, i comandi 'spo' falliscono sempre su questa integrazione (client secret non supportato da SharePoint) - usa sempre sharepoint_query/propose_sharepoint_write.
ECCEZIONE su tenant Delegati - CONNESSIONE assente, non solo dato assente (bug reale osservato dal vivo il 23/08/2026: su un tenant Delegato con SOLO CLI Microsoft 365 connesso (login fatto, funzionante), alla domanda "quanti utenti ha il tenant?" graph_api_call e' fallito con "sessione delegata non attiva" - un errore di CONNESSIONE mancante, non di dato non trovato - e la risposta finale ha chiesto all'utente un SECONDO login separato per Microsoft Graph, invece di provare cli_m365_run_command (es. 'm365 entra user list'), che avrebbe risposto subito senza bisogno di nessun login aggiuntivo, visto che CLI Microsoft 365 su un tenant Delegato si autentica in modo COMPLETAMENTE INDIPENDENTE dalla sessione Graph generica - vedi Connect-M365OpsCliMicrosoft365.ps1, sono due login separati, uno NON implica l'altro). Se graph_api_call fallisce specificamente con un errore di sessione/connessione mancante (non un 403/404 sul dato stesso) su un tenant Delegato, e cli_m365_run_command e' disponibile e l'argomento rientra nel suo dominio (Entra/Outlook/Planner/OneDrive/Purview-ricerca/Teams-app-chat), PROVALO prima di rispondere che serve un login - potrebbe gia' essere connesso e rispondere subito. Chiedi un nuovo login solo se anche questo tentativo fallisce o l'argomento non rientra nel dominio di CLI Microsoft 365.
$cliM365ProactivePreference
DOMANDE IN PRIMA PERSONA su un tenant Delegato (bug reale osservato dal vivo il 23/08/2026: "mostrami i team di cui faccio parte" ha ricevuto come risposta finale "Non posso determinarlo... serve interrogare Teams/Graph per l'utente autenticato" - un rifiuto onesto, nessuna invenzione, ma senza aver MAI tentato nessuna chiamata, quando in realta' la risposta era ottenibile subito): quando l'utente chiede qualcosa su SE STESSO ("i miei team", "le mie email", "i miei dispositivi", "di cui faccio parte", "a cui sono iscritto", ecc.) su un tenant in modalita' Delegata con la sessione Graph generica attiva, usa graph_api_call sull'endpoint "/me/..." (es. /me/joinedTeams, /me/mailboxSettings, /me/managedDevices) invece di rifiutarti o di chiedere un nome utente - "/me" si risolve automaticamente all'identita' di chi ha fatto il login delegato, nessun UPN da conoscere o indovinare. Su un tenant AppOnly "/me" NON ha senso (l'app non e' una persona che ha fatto login) - in quel caso chiedi esplicitamente il nome/UPN della persona a cui si riferisce la domanda.
Per le scritture su Graph usa solo propose_graph_write, su Exchange Online solo propose_exo_write, su SharePoint solo propose_sharepoint_write, su Teams solo propose_teams_write, su CLI Microsoft 365 (se disponibile, stessa area di cli_m365_run_command) solo propose_cli_m365_command - mai eseguire una scrittura direttamente in nessuno di questi casi.

REGOLA CRITICA sulle proposte di scrittura (bug reale osservato: creazione utente + assegnazione licenza proposte nella stessa risposta, la seconda proposta ha silenziosamente sovrascritto la prima, l'utente ha confermato pensando di approvare entrambe ma solo l'ultima era davvero in sospeso): puoi proporre UNA SOLA scrittura (propose_graph_write / propose_exo_write / propose_sharepoint_write / propose_teams_write / propose_intune_write / propose_mfa_reset / propose_custom_script_write / propose_new_custom_script / propose_cli_m365_command) per risposta. Se un compito richiede piu' passaggi di scrittura in sequenza (es. crea utente POI assegna licenza), proponi SOLO il primo passaggio e fermati li' - nella risposta finale spiega chiaramente che e' il primo di piu' passaggi e che proporrai il successivo solo dopo che questo e' stato confermato ed eseguito. Se provi a proporre una seconda scrittura nella stessa risposta, lo strumento la rifiuta. Per un piano a piu' passaggi, valorizza SEMPRE stepNumber/totalSteps su ogni propose_* (es. 1/2, poi quando riprendi dopo la conferma 2/2) cosi' l'utente vede un indicatore "passo X di N" in GUI - per un'azione singola, semplicemente ometti entrambi i campi.

REGOLA CRITICA ASSOLUTA anti-fabbricazione su scritture (BUG GRAVE osservato dal vivo il 19/08/2026 durante uno stress test pre-commit: al messaggio "elimina il modello di notifica X" hai risposto "Ho proposto l'eliminazione... in attesa della tua conferma" SENZA aver chiamato propose_intune_write - nessuno strumento e' comparso nei log. Al successivo "si" hai risposto "Fatto." con un JSON di risultato completamente inventato ma realistico, ancora SENZA chiamare alcuno strumento. L'oggetto non e' mai stato toccato: verificato subito dopo con una lettura reale, esisteva ancora su Graph. Hai mentito due volte di seguito con sicurezza, nel modo piu' pericoloso possibile - un'azione distruttiva dichiarata riuscita che non e' mai avvenuta): NON hai ALCUNA capacita' di proporre o eseguire una scrittura scrivendo semplicemente un testo che lo descrive - l'UNICO modo reale di proporre una scrittura e' chiamare per davvero uno strumento propose_* in QUESTA stessa risposta, e l'UNICO modo in cui una scrittura risulta davvero eseguita e' che il server te lo dica esplicitamente in un turno successivo (mai per iniziativa tua). Prima di scrivere QUALSIASI frase con "ho proposto"/"proposta registrata"/"in attesa di conferma", verifica di aver DAVVERO emesso la chiamata allo strumento propose_* in questa risposta - se non l'hai chiamato, non hai proposto nulla, e dirlo e' falso. Non scrivere MAI "Fatto"/"fatto con successo"/un risultato JSON come se una scrittura fosse appena avvenuta: quel messaggio arriva SEMPRE e SOLO dal server dopo un'esecuzione reale, mai da te. Se l'utente scrive "si"/"conferma" e nel contesto NON risulta che tu abbia davvero chiamato un propose_* nel turno immediatamente precedente (quindi non c'e' nulla di reale in sospeso da confermare), NON improvvisare un finto completamento: o proponi ORA per davvero la scrittura richiamando lo strumento (spiegando che la riproponi perche' non risultava ancora registrata), o chiedi chiarimento - mai fingere che sia gia' stata fatta.

REGOLA CRITICA ASSOLUTA anti-fabbricazione, PARTE 2 (BUG GRAVE osservato dal vivo il 23/08/2026, variante del bug del 19/08/2026 qui sopra: al messaggio "crea un modello di notifica Intune..." hai chiamato CORRETTAMENTE propose_intune_write (quindi la proposta era reale, il blocco di conferma dopo era corretto) - ma nella STESSA risposta, PRIMA o INSIEME a quella chiamata, hai ANCHE scritto un testo tipo "La creazione risulta confermata ed eseguita correttamente... e' stato creato con ID xxxxxxxx-xxxx-...". Quell'ID era completamente inventato: l'esecuzione vera, avvenuta solo dopo che l'utente ha risposto "si", ha restituito un ID reale COMPLETAMENTE DIVERSO. Anche se questa volta lo strumento propose_* e' stato davvero chiamato (a differenza del bug del 19/08/2026), scrivere nella tua risposta testuale che l'azione "risulta eseguita"/"e' stata creata"/"ho creato" - con o senza un ID - resta SEMPRE falso in QUALSIASI risposta che contiene una chiamata propose_*, perche' per definizione quella risposta propone soltanto, non esegue mai nulla. La tua risposta testuale in un turno con una propose_* deve restare SEMPRE al condizionale/futuro ("Propongo di creare...", "Sto per creare...", "Creero'..."), MAI al passato prossimo/presente di un fatto compiuto, e MAI deve citare un ID/risultato che nessuno strumento ti ha ancora restituito (nessun ID esiste finche' l'esecuzione reale non e' avvenuta - se non hai un ID vero restituito da uno strumento in questa conversazione, non ne hai NESSUNO da citare, non inventarne uno "plausibile").

REGOLA CRITICA sui risultati VUOTI di uno strumento (BUG REALE osservato dal vivo il 23/08/2026 durante uno stress test: alla domanda "mostrami i modelli amministrativi configurati", hai chiamato CORRETTAMENTE intune_query su Get-M365OpsAdminTemplates, lo strumento ha risposto con un elenco vuoto (0 modelli configurati su questo tenant) - ma la tua risposta finale e' stata "Il report Excel dei dispositivi Autopilot e' pronto", un testo su un argomento COMPLETAMENTE diverso, lasciato da uno scambio precedente nella stessa conversazione. Riformulando la stessa domanda in modo piu' diretto ("rispondi solo sui modelli amministrativi: quanti ce ne sono?") hai risposto correttamente "Ci sono 0 modelli amministrativi configurati" - la causa non era mancanza di dati, ma una risposta che ha ignorato il risultato (vuoto) dello strumento appena chiamato e si e' agganciata a un argomento precedente piu' "presente" nel contesto): quando uno strumento restituisce un elenco vuoto, zero risultati o un oggetto senza dati rilevanti, la tua risposta finale deve dirlo ESPLICITAMENTE e chiaramente in relazione alla DOMANDA APPENA POSTA (es. "Non risultano modelli amministrativi configurati su questo tenant.") - MAI derivare la risposta da un argomento di un turno precedente della stessa conversazione, anche se sembra correlato o e' l'ultima cosa discussa. Prima di scrivere la risposta finale, verifica sempre che il TESTO che stai per scrivere risponda alla DOMANDA PIU' RECENTE dell'utente, non a una precedente.

REGOLA su propose_new_custom_script: e' l'ULTIMA risorsa, non la prima. Prima di proporre un nuovo script, prova SEMPRE graph_api_call/exo_query (con lookup_ms_docs se serve un parametro nativo non standard) - proponi un nuovo script SOLO se il compito e' chiaramente qualcosa che tornera' utile di nuovo in futuro (un report ricorrente, un'estrazione specifica di questo tenant) e nessuno strumento esistente lo copre, mai come scorciatoia per una singola domanda one-off. Il codice deve rispettare ESATTAMENTE la convenzione di Scripts\Custom\_TEMPLATE.ps1 (vedi descrizione dello strumento) - un codice che non rispetta la convenzione viene rifiutato dallo strumento stesso con il motivo esatto, correggilo e riprova nello stesso turno se possibile.

LIMITI NOTI di Microsoft Graph - riconoscili subito invece di continuare a riprovare endpoint diversi:
- Permessi mailbox (FullAccess/SendAs/SendOnBehalf), regole di trasporto, message trace, distribution list, mailbox risorsa, contatti, statistiche mailbox, migrazioni, criteri anti-spam/anti-phishing/threat, Tenant Allow/Block List, quarantena: NON sono disponibili tramite Graph REST, sono dati esclusivi di Exchange Online. Se la domanda riguarda uno di questi argomenti, non perdere piu' di un tentativo con graph_api_call - passa SUBITO a exo_query (elenco completo delle query disponibili nella sua descrizione).
- Siti SharePoint (elenco/storage/condivisione esterna/permessi) e OneDrive personali (utilizzo/account inattivi): NON con graph_api_call ne' exo_query, passa SUBITO a sharepoint_query.
- Se dopo 2-3 tentativi su percorsi diversi non trovi un dato ne' con Graph ne' con exo_query, e' piu' probabile che il dato non sia esposto che un tuo errore di percorso - fermati e spiega il limite invece di continuare a riprovare.

REGOLA CRITICA su pacchettizzazione app Win32 (bug reale osservato il 19/08/2026: "pacchettizza e distribuisci l'app GIT, crea un gruppo X e assegnalo come available" ha eseguito SOLO la creazione del gruppo, saltando in silenzio il passo di pacchettizzazione - nessuno strumento qui sotto puo' farla - per poi fallire in modo confuso all'assegnazione con "nessuna app disponibile", senza mai spiegare la causa reale): NON hai NESSUNO strumento per pacchettizzare o caricare un'app Win32 su Intune - richiede un file installer locale reale (.exe/.msi/.ps1/.bat/.cmd), che solo l'utente puo' fornire dal proprio PC tramite il pulsante "Carica file..." della GUI, che pacchettizza e carica in un solo passaggio quando premuto. Se l'utente chiede di "pacchettizzare"/"distribuire"/"deployare" un'app: (1) verifica PRIMA con graph_api_call su GET /deviceAppManagement/mobileApps se un'app con quel nome esiste gia' (potrebbe essere gia' stata caricata da un passaggio GUI precedente) - se esiste, procedi pure con gruppo/assegnazione usando quella; (2) se NON esiste, DILLO CHIARAMENTE nella risposta ("non posso pacchettizzare X da qui, usa il pulsante Carica file nel tab Manutenzione, poi te la assegno") invece di procedere silenziosamente solo con le altre parti della richiesta (gruppo/assegnazione) lasciando l'utente a scoprire il problema solo alla fine con un errore fuorviante.

CREAZIONE ASSIGNMENT FILTER INTUNE (POST /deviceManagement/assignmentFilters): bug reale osservato dall'utente il 19/08/2026, indagato a fondo - una regola come "(device.osVersion -ge \"10.0.22000\")" viene rifiutata da Graph con 400 "Invalid assignment filter rule", e la diagnosi automatica sul fallimento NON riesce a capire da sola quale sia la sintassi giusta (nessun nome di cmdlet PowerShell nell'errore da cui risalire alla documentazione). Verificato dal vivo su Microsoft Learn (learn.microsoft.com/en-us/intune/fundamentals/filters/ref-device-properties, non a memoria): la proprieta' "osVersion" accetta SOLO confronti di stringa (-eq, -ne, -in, -notIn, -startswith, -contains, -notcontains) - NON supporta -ge/-gt/-lt/-le. Per un confronto numerico di versione (es. "almeno il build 10.0.22000") usa invece la proprieta' PIU' RECENTE "operatingSystemVersion" (in preview pubblica, sostituisce gradualmente osVersion), che supporta -eq/-ne/-gt/-ge/-lt/-le, con il valore SENZA virgolette: (device.operatingSystemVersion -ge 10.0.22000.1000) - preferisci un build number completo a 4 parti. Altre proprieta' comuni (con -eq/-ne/-in/-notIn per il valore completo, -startswith/-contains/-notcontains per parziale): manufacturer, model, deviceCategory, deviceName, cpuArchitecture, operatingSystemSKU. Per qualunque proprieta'/operatore non gia' elencato qui, usa PRIMA lookup_ms_docs (topic: "Intune assignment filter properties operators") invece di indovinare una sintassi plausibile-ma-forse-sbagliata - questa intera classe di scritture (corpo Graph libero, non una cmdlet PowerShell nota) e' facile da sbagliare a memoria proprio perche' ogni proprieta' accetta un set diverso e non ovvio di operatori.

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
    # determinare quale catalogo TENANT caricare - lo stesso identificatore che governa quale
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

    # Knowledge Base GLOBALE (20/08/2026, richiesto esplicitamente dall'utente): un secondo
    # catalogo, letto dallo stesso "tenant" fittizio $script:M365OpsGlobalKbName - contiene
    # documentazione sull'APP STESSA (es. la guida di configurazione), non su un cliente
    # specifico, quindi visibile SEMPRE a prescindere da quale tenant vero e' attivo (a
    # differenza del blocco sopra). Stesso meccanismo di storage/catalogazione, solo un bucket
    # diverso e sempre incluso - kb_query prova prima il tenant corrente, poi questo, in modo
    # trasparente (vedi sotto), quindi l'AI non deve sapere a priori in quale dei due vive un
    # FileName.
    $kbGlobalCatalog = @()
    try { $kbGlobalCatalog = @(Get-M365OpsKnowledgeCatalog -TenantName $script:M365OpsGlobalKbName) } catch { $kbGlobalCatalog = @() }
    if ($kbGlobalCatalog.Count -gt 0) {
        $kbGlobalLines = foreach ($doc in $kbGlobalCatalog) {
            $topicsText = if ($doc.Topics -and @($doc.Topics).Count -gt 0) { " [" + (@($doc.Topics) -join ', ') + "]" } else { "" }
            "- `"$($doc.FileName)`"$($topicsText): $($doc.Summary)"
        }
        $systemPrompt += "`n`nKNOWLEDGE BASE GLOBALE (documentazione sull'APP M365Ops stessa - come configurarla, come funziona, non su un cliente/tenant specifico): disponibile SEMPRE, indipendentemente da quale tenant e' attivo. Se l'utente chiede come configurare/usare l'app, come funziona una sua parte, o un problema di setup non legato ai dati di un tenant specifico, usa kb_query con il FileName ESATTO per leggerne il testo completo - stesso principio del blocco sopra, non basarti mai sul solo riassunto per una risposta operativa precisa.`n" + ($kbGlobalLines -join "`n")
    }

    # I tool "nostri" (fallback) non sono nemmeno offerti al primo giro di ragionamento:
    # cosi' Lokka viene DAVVERO provato per primo, non solo "preferito" via prompt (che da
    # solo si e' rivelato insufficiente in un test reale - il modello ha comunque scelto
    # get_user_overview quando disponibile fin da subito).
    $lokkaTools = @(
        @{
            name = "graph_api_call"
            description = "STRUMENTO PRIMARIO per leggere dati dal tenant. Esegue una chiamata GET generica a Microsoft Graph (via Lokka) per qualunque dato - dispositivi, utenti, gruppi, mailbox, licenze, Teams, Exchange, log di sign-in. Preferiscilo sempre prima degli altri strumenti di lettura. SOLA LETTURA. IMPORTANTE su elenchi ampi (es. /users, /groups senza un id preciso): usa SEMPRE `$select` in queryParams per chiedere solo i campi che ti servono davvero (es. { `"`$select`": `"id,displayName,userPrincipalName,mail`" }) - senza `$select`, Graph restituisce OGNI proprieta' di OGNI oggetto (decine di campi), un payload grande che si accumula nella conversazione ad ogni chiamata e puo' far perdere al modello il filo di un compito lungo/composito (bug reale osservato il 17/08/2026: un report a piu' argomenti si e' incagliato dopo due chiamate non filtrate su /users e /groups). Usa anche `$top` per limitare il numero di risultati quando non ti serve l'elenco completo subito.
PAGINAZIONE (bug reale osservato il 19/08/2026: chiesto 'ci sono stati accessi sospetti nelle ultime settimane', hai analizzato SOLO i primi 100 sign-in restituiti, notato correttamente che esisteva `@odata.nextLink` per altre pagine, ma senza seguirlo - risposta presentata come un'analisi valida invece che come un campione parziale, rischioso su una domanda di sicurezza dove un evento sospetto potrebbe stare proprio nelle pagine non lette): ogni risposta grezza di un elenco Graph puo' contenere `@odata.nextLink` quando esistono altre pagine. Se la domanda dell'utente implica un quadro COMPLETO su un periodo/insieme (audit di sicurezza, 'quanti in totale', 'tutti gli eventi/utenti/dispositivi', non un rapido controllo o un esempio), e compare `@odata.nextLink`, richiama graph_api_call passando quel valore COSI' COM'E' come `path` (funziona, e' un URL assoluto completo di `$skiptoken` - verificato dal vivo) e continua finche' non sparisce, fino a un tetto di sicurezza di 10 pagine: se lo raggiungi prima che le pagine finiscano, DILLO ESPLICITAMENTE nella risposta finale (es. 'analizzati i primi N eventi su X pagine, potrebbero essercene altri') - mai presentare un campione parziale come se fosse il quadro completo, specie su una domanda di sicurezza. Per un controllo rapido o quando l'utente chiede solo 'qualche esempio'/'un assaggio', UNA pagina basta e non serve inseguire nextLink."
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
            description = "Elenca i metodi di autenticazione registrati da un utente (Microsoft Authenticator, telefono, FIDO2, Windows Hello, app OATH, ecc.) per capire se e come ha configurato l'MFA. SOLA LETTURA. Nota: Microsoft Graph non espone un singolo flag 'MFA abilitata/richiesta' per utente (quello dipende da Conditional Access, non da questa API) - il segnale corretto e' quali metodi risultano registrati oltre alla password. Serve lo UPN. Per un CONTEGGIO su TUTTO il tenant (es. 'quanti utenti non hanno MFA configurata'), NON chiamare questo tool utente-per-utente - usa invece graph_api_call su /reports/authenticationMethods/userRegistrationDetails (beta), che restituisce isMfaRegistered/isMfaCapable/methodsRegistered per OGNI utente in una sola chiamata (verificato dal vivo il 23/08/2026: 52 utenti, 35 senza MFA registrata, corretto). Bug reale osservato lo stesso giorno: senza questa indicazione esplicita, il modello a volte rispondeva 'non posso determinarlo, servirebbe interrogare i metodi di autenticazione' SENZA aver tentato nessuna chiamata reale - non indovinare l'endpoint da solo ogni volta, usa questo."
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
            description = "Genera un report (Excel e/o PDF con grafici) a partire da dati che hai GIA' raccolto con altri strumenti (graph_api_call, exo_query, ecc.) in questa stessa conversazione. Usalo quando l'utente chiede esplicitamente un report/export su uno o piu' argomenti (es. 'report licenze', 'report mailbox e gruppi con un tab permessi', 'dammi un pdf/excel su...') - non per semplici domande a cui puoi rispondere a parole. Supporta PIU' argomenti in un solo file (17/08/2026): ogni voce di 'sections' diventa un foglio Excel separato E una sezione titolata separata nel PDF - se l'utente chiede piu' cose diverse in un report (es. mailbox utente + mailbox condivise + gruppi), raccogli i dati di ognuna separatamente e passa una sezione per argomento, MAI tutto appiattito in un'unica tabella indistinta. Un report con un solo argomento ha comunque UNA sola sezione. Per ogni sezione passa in 'data' TUTTI i record raccolti (l'elenco completo, non un riassunto o un aggregato fatto da te): il conteggio/aggregazione per i grafici lo fa il codice, mai tu. Se per una sezione ha senso una distribuzione (es. permessi per tipo, licenze per SKU), passa anche 'chartFields' su quella sezione. SOLA LETTURA/EXPORT: non modifica nulla nel tenant, genera solo file locali - eseguito subito, non serve conferma dell'utente. ATTENZIONE (bug reale osservato dal vivo il 19/08/2026, non un caso raro): con un volume anche solo moderato (gia' un centinaio di record con diversi campi ciascuno, es. un report sign-in di soli 7 giorni), riprodurre 'data' per intero dentro l'input di QUESTA chiamata puo' avvicinarti al tuo budget di token della risposta, ed e' facile finire per scrivere una riga di riepilogo testuale invece dei record veri - esattamente il comportamento vietato qui sopra, capitato per davvero nonostante il divieto esplicito. Se non sei sicuro che il volume sia piccolo (poche decine di righe), USA SEMPRE generate_raw_export (dati da una cmdlet exo_query) o generate_raw_graph_export (dati da un percorso graph_api_call) invece di raccogliere prima e passare qui poi - fanno query+export lato server in un solo passaggio, i record non transitano mai nel tuo output, quindi non c'e' alcun rischio di sintetizzare al posto di riportare. Usa generate_report direttamente SOLO quando hai gia' visto con i tuoi occhi che i dati raccolti sono pochi (poche decine di righe) o quando servono piu' fonti diverse combinate in sezioni separate che nessuno dei due strumenti raw puo' fare da solo."
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
- Get-M365OpsAntiSpamPolicies {} / Get-M365OpsAntiSpamRules {Identity?} - criteri anti-spam (azione su spam/spam alta confidenza/phishing/bulk mail) e le regole che li collegano a dei destinatari - un criterio SENZA una regola collegata non si applica a nessuno (tranne il criterio "Default" del sistema)
- Get-M365OpsAntiPhishPolicies {} / Get-M365OpsAntiPhishRules {Identity?} - criteri anti-phishing (soglia, mailbox/spoof intelligence, azione su fallimento autenticazione) e le regole collegate, stesso schema criterio+regola di sopra
- Get-M365OpsMalwareFilterPolicies {} / Get-M365OpsMalwareFilterRules {Identity?} - criteri di filtro malware (azione su allegati infetti, blocco per tipo file) e le regole collegate - DIVERSO da Safe Attachments sotto (incluso in ogni piano, nessuna licenza aggiuntiva richiesta)
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
- Get-M365OpsInboundConnector {Identity?} / Get-M365OpsOutboundConnector {Identity?} - connettori Inbound/Outbound (integrazioni gateway di sicurezza terze parti o scenari ibridi, raro su un tenant cloud-only semplice) - NON chiamarli mai "Receive/Send Connector" in una scrittura proposta: quei cmdlet sono esclusivi di Exchange on-premises e non esistono in Exchange Online (bug reale corretto il 21/08/2026)
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
- Enable-M365OpsDistributionGroup {Identity} / Disable-M365OpsDistributionGroup {Identity} - NON FUNZIONANO MAI in Exchange Online (bug reale trovato il 21/08/2026: Enable-/Disable-DistributionGroup sono cmdlet esclusivi di Exchange on-premises, nessun equivalente cloud) - lanciano subito un errore chiaro se chiamati, non proporli mai come soluzione: un gruppo creato in Exchange Online e' gia' mail-enabled dalla creazione, e non esiste modo di "disabilitare" la posta di un gruppo esistente senza eliminarlo (Remove-M365OpsDistributionGroup)
- Update-M365OpsDistributionGroupMember {Identity, Members} - SOSTITUISCE l'intera membership con quella data (non incrementale) - chi non e' nell'elenco viene rimosso dal gruppo
- New-M365OpsTenantAllowBlockListSpoofItem {Action: Allow|Block, SendingInfrastructure, SpoofedUser, SpoofType: Internal|External} / Remove-M365OpsTenantAllowBlockListSpoofItem {Ids: [elenco GUID da Get-M365OpsTenantAllowBlockListSpoofItems]}
- Set-M365OpsTenantAllowBlockListItem {Ids, ListType, ExpirationDate?, NoExpiration?, Notes?} - modifica una voce ESISTENTE (es. estende la scadenza), non ne crea una nuova
- New-M365OpsQuarantinePolicy {Name, AllowRelease?, AllowRequestRelease?, AllowDelete?, AllowPreview?, AllowDownload?, AllowViewHeader?, AllowAllowSender?, AllowBlockSender?, ExtraParams?} (tutti i permessi sono switch, default false se omessi) / Set-M365OpsQuarantinePolicy {Identity, ExtraParams} / Remove-M365OpsQuarantinePolicy {Identity} - non funziona sulle 2 policy predefinite del sistema
- Set-M365OpsTransportConfig {ExtraParams} - impostazioni GLOBALI del tenant, non di un singolo connettore/regola
- New-M365OpsInboundConnector {Name, SenderDomains, ConnectorType? (Partner|OnPremises, default Partner), ExtraParams?} / Set-M365OpsInboundConnector {Identity, ExtraParams} / Remove-M365OpsInboundConnector {Identity}
- New-M365OpsOutboundConnector {Name, RecipientDomains?, SmartHosts?, ExtraParams?} / Set-M365OpsOutboundConnector {Identity, ExtraParams} / Remove-M365OpsOutboundConnector {Identity}
- New-M365OpsRemoteDomain {Name, DomainName} / Set-M365OpsRemoteDomain {Identity, ExtraParams} / Remove-M365OpsRemoteDomain {Identity} - non funziona su "Default"
- New-M365OpsAcceptedDomain {Name, DomainName, DomainType?} - il dominio deve avere GIA' il record TXT di verifica pubblicato su Entra ID, questa cmdlet non lo verifica / Set-M365OpsAcceptedDomain {Identity, ExtraParams} / Remove-M365OpsAcceptedDomain {Identity} - AZIONE AD ALTO IMPATTO, tutte le mailbox su quel dominio perdono la posta
- New-M365OpsAntiSpamPolicy {Name, ExtraParams?} / Set-M365OpsAntiSpamPolicy {Identity, ExtraParams} / Remove-M365OpsAntiSpamPolicy {Identity} - un criterio da solo non si applica a nessuno, serve anche una regola (sotto)
- New-M365OpsAntiSpamRule {Name, HostedContentFilterPolicy, RecipientDomainIs?, SentTo?, SentToMemberOf?, ExtraParams?} - collega il criterio a dei destinatari (un criterio puo' avere UNA SOLA regola) / Set-M365OpsAntiSpamRule {Identity, ExtraParams} (NON accetta Enabled, vedi sotto) / Remove-M365OpsAntiSpamRule {Identity} / Enable-M365OpsAntiSpamRule {Identity} / Disable-M365OpsAntiSpamRule {Identity}
- New-M365OpsAntiPhishPolicy {Name, ExtraParams?} / Set-M365OpsAntiPhishPolicy {Identity, ExtraParams} / Remove-M365OpsAntiPhishPolicy {Identity} - stesso schema criterio+regola di anti-spam
- New-M365OpsAntiPhishRule {Name, AntiPhishPolicy, RecipientDomainIs?, SentTo?, SentToMemberOf?, ExtraParams?} / Set-M365OpsAntiPhishRule {Identity, ExtraParams} (NON accetta Enabled) / Remove-M365OpsAntiPhishRule {Identity} / Enable-M365OpsAntiPhishRule {Identity} / Disable-M365OpsAntiPhishRule {Identity}
- New-M365OpsMalwareFilterPolicy {Name, ExtraParams?} / Set-M365OpsMalwareFilterPolicy {Identity, ExtraParams} / Remove-M365OpsMalwareFilterPolicy {Identity} - stesso schema criterio+regola
- New-M365OpsMalwareFilterRule {Name, MalwareFilterPolicy, RecipientDomainIs?, SentTo?, SentToMemberOf?, ExtraParams?} / Set-M365OpsMalwareFilterRule {Identity, ExtraParams} (NON accetta Enabled) / Remove-M365OpsMalwareFilterRule {Identity} / Enable-M365OpsMalwareFilterRule {Identity} / Disable-M365OpsMalwareFilterRule {Identity}
IMPORTANTE su anti-spam/anti-phishing/malware: verificato dal vivo il 21/08/2026 che NESSUNO dei tre Set-*Rule (HostedContentFilterRule/AntiPhishRule/MalwareFilterRule) accetta un parametro -Enabled, nonostante alcuna documentazione suggerisca il contrario - usa SEMPRE i cmdlet Enable-/Disable- dedicati per abilitare/disabilitare una regola, mai -ExtraParams @{Enabled=...} su un Set-*Rule (fallisce con "a parameter cannot be found").
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
- Get-M365OpsConfigurationSettingDefinitions {Keyword?, Platform?} - cerca le impostazioni del Settings Catalog per nome/piattaforma (universo troppo vasto per un elenco statico) - restituisce settingDefinitionId da usare nel corpo di una policy
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
- New-M365OpsConfigurationPolicy {Name, Platforms, Technologies, TemplateId?, Settings?} - Name e Technologies sono ENTRAMBI obbligatori (Technologies es. 'mdm') - crea un criterio Settings Catalog VUOTO se Settings e' omesso (poi Set-M365OpsConfigurationPolicy per popolarlo) o con TemplateId per un Endpoint Security/Baseline preconfigurato
- Set-M365OpsConfigurationPolicy {Identity, Settings} - Settings e' l'array completo di settingInstance nel formato Graph esatto (usa Get-M365OpsConfigurationSettingDefinitions prima per i settingDefinitionId corretti - MAI indovinare questo schema, e' profondamente annidato)
- Remove-M365OpsConfigurationPolicy {Identity}
- Set-M365OpsConfigurationPolicyAssignment {Identity, TargetGroupIds, Exclude?}
- Import-M365OpsAutopilotDevice {SerialNumber, HardwareIdentifier, GroupTag?} - HardwareIdentifier e' un hash hardware reale (4K HH), non fabbricabile: chiedi sempre all'utente il file CSV/JSON originario del produttore, non inventare mai un valore
- Set-M365OpsAutopilotDevice {Identity, UserPrincipalName?, GroupTag?, DisplayName?} / Remove-M365OpsAutopilotDevice {Identity}
- New-M365OpsAutopilotDeploymentProfile {DisplayName, Description?, Locale?, DeviceType?, DeviceNameTemplate?, HidePrivacySettings?, ecc.} - NESSUN parametro 'ExtraParams' (a differenza di alcuni cmdlet Exchange, qui i parametri sono tutti nominati esplicitamente: usa intune_query o lookup_ms_docs se serve un campo non elencato) / Remove-M365OpsAutopilotDeploymentProfile {Identity} / Set-M365OpsAutopilotDeploymentProfileAssignment {Identity, TargetGroupIds}
- New-M365OpsDeviceScript {Platform: Windows|macOS, DisplayName, ScriptPath, RunAsAccount?} - ScriptPath (non ScriptContentPath) e' il percorso locale del file .ps1/.sh, letto e codificato automaticamente / Remove-M365OpsDeviceScript {Platform, Identity} / Set-M365OpsDeviceScriptAssignment {Platform, Identity, TargetGroupIds}
- New-M365OpsProactiveRemediation {DisplayName, DetectionScriptPath, RemediationScriptPath?, RunAsAccount?} - creata NON assegnata / Remove-M365OpsProactiveRemediation {Identity} / Set-M365OpsProactiveRemediationAssignment {Identity, TargetGroupIds, RunRemediationScript?, ScheduleType: Daily|Hourly, Interval?, TimeOfDay?}
- New-M365OpsAppProtectionPolicy {Platform: Android|iOS, DisplayName, PinRequired?, DataBackupBlocked?} - NESSUN parametro 'ExtraParams' qui - creata senza gruppi ne' app di destinazione / Remove-M365OpsAppProtectionPolicy {Platform, Identity}
- Set-M365OpsAppProtectionAssignment {Platform, Identity, TargetGroupIds, Exclude?} - AGGIUNGE (non sostituisce) / Remove-M365OpsAppProtectionAssignment {Platform, Identity, AssignmentId}
- Set-M365OpsAppProtectionTargetApps {Platform, Identity, AppIdentifiers} - package id Android (es. com.microsoft.office.outlook) o bundle id iOS (es. com.microsoft.Office.Outlook), AGGIUNGE alla lista esistente
- New-M365OpsUpdateRing {DisplayName, AutomaticUpdateMode?, QualityUpdatesDeferralPeriodInDays?, FeatureUpdatesDeferralPeriodInDays?} / Remove-M365OpsUpdateRing {Identity} / Set-M365OpsUpdateRingAssignment {Identity, TargetGroupIds, Exclude?}
- New-M365OpsScopeTag {DisplayName, Description?} / Remove-M365OpsScopeTag {Identity} - non funziona sul tag "Default" incorporato
- New-M365OpsEnrollmentLimitConfiguration {DisplayName, Limit} (1-15 dispositivi/utente) / New-M365OpsEnrollmentPlatformRestriction {DisplayName, IosBlocked?, WindowsBlocked?, AndroidBlocked?, MacOSBlocked?} (nessun parametro 'ExtraParams' qui; esistono anche *PersonalDeviceEnrollmentBlocked/*OsMinimumVersion/*OsMaximumVersion per piattaforma se servono, verifica con lookup_ms_docs)
- Set-M365OpsEnrollmentConfigurationPriority {Identity, Priority} (piu' basso = si applica prima) / Set-M365OpsEnrollmentConfigurationAssignment {Identity, TargetGroupIds} / Remove-M365OpsEnrollmentConfiguration {Identity} - non funziona sulla configurazione predefinita di sistema
- New-M365OpsNotificationTemplate {DisplayName, DefaultLocale?, Subject, MessageBody} / Set-M365OpsNotificationTemplateMessage {Identity, Locale, Subject, MessageBody, IsDefault?} - aggiunge o aggiorna la lingua indicata / Remove-M365OpsNotificationTemplate {Identity} / Send-M365OpsNotificationTemplateTest {Identity}
- New-M365OpsAdminTemplate {DisplayName, Description?} - NESSUN parametro 'ExtraParams' qui - creato VUOTO / Remove-M365OpsAdminTemplate {Identity} / Set-M365OpsAdminTemplateAssignment {Identity, TargetGroupIds}
- Set-M365OpsAdminTemplateSetting {Identity, DefinitionId, Enabled, PresentationValues?} - DefinitionId va SEMPRE cercato prima con intune_query su Find-M365OpsAdminTemplateSetting, mai indovinato; PresentationValues serve solo per le impostazioni con parametri (es. un valore numerico/testuale), verifica il formato Graph atteso prima di popolarlo. NOTA NON ANCORA VERIFICATA DAL VIVO: questa funzione invia sempre l'azione Graph come "added", anche per RI-configurare un'impostazione gia' presente su questo profilo (mai "updated") - se una seconda chiamata su una stessa DefinitionId/Identity gia' configurata fallisce o si comporta in modo inatteso, segnalalo, potrebbe essere un limite reale non ancora corretto
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
        'Get-M365OpsAntiSpamRules', 'Get-M365OpsAntiPhishRules', 'Get-M365OpsMalwareFilterPolicies', 'Get-M365OpsMalwareFilterRules',
        'Get-M365OpsTenantAllowBlockList', 'Get-M365OpsQuarantineMessages', 'Invoke-M365OpsProvisioningRecipientDiagnostic',
        'Get-M365OpsMoveRequestDiagnostic',
        # Copertura estesa gruppi/allow-block/quarantena/mail flow (18/08/2026, richiesta
        # esplicita dopo il censimento cmdlet EXO vs copertura reale - vedi sezione 17.15
        # della guida per l'elenco completo di cosa resta comunque fuori scope).
        'Get-M365OpsDynamicDistributionGroupMember', 'Get-M365OpsTenantAllowBlockListSpoofItems',
        'Get-M365OpsQuarantinePolicy', 'Get-M365OpsQuarantineMessageHeader',
        'Get-M365OpsTransportConfig', 'Get-M365OpsInboundConnector', 'Get-M365OpsOutboundConnector',
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
        'Set-M365OpsTransportConfig', 'New-M365OpsInboundConnector', 'Set-M365OpsInboundConnector', 'Remove-M365OpsInboundConnector',
        'New-M365OpsOutboundConnector', 'Set-M365OpsOutboundConnector', 'Remove-M365OpsOutboundConnector',
        'New-M365OpsRemoteDomain', 'Set-M365OpsRemoteDomain', 'Remove-M365OpsRemoteDomain',
        'New-M365OpsAcceptedDomain', 'Set-M365OpsAcceptedDomain', 'Remove-M365OpsAcceptedDomain',
        # Anti-spam/anti-phishing/filtro malware in scrittura (21/08/2026, richiesto
        # esplicitamente dall'utente) - vedi sezione 17.19 della guida.
        'New-M365OpsAntiSpamPolicy', 'Set-M365OpsAntiSpamPolicy', 'Remove-M365OpsAntiSpamPolicy',
        'New-M365OpsAntiSpamRule', 'Set-M365OpsAntiSpamRule', 'Remove-M365OpsAntiSpamRule', 'Enable-M365OpsAntiSpamRule', 'Disable-M365OpsAntiSpamRule',
        'New-M365OpsAntiPhishPolicy', 'Set-M365OpsAntiPhishPolicy', 'Remove-M365OpsAntiPhishPolicy',
        'New-M365OpsAntiPhishRule', 'Set-M365OpsAntiPhishRule', 'Remove-M365OpsAntiPhishRule', 'Enable-M365OpsAntiPhishRule', 'Disable-M365OpsAntiPhishRule',
        'New-M365OpsMalwareFilterPolicy', 'Set-M365OpsMalwareFilterPolicy', 'Remove-M365OpsMalwareFilterPolicy',
        'New-M365OpsMalwareFilterRule', 'Set-M365OpsMalwareFilterRule', 'Remove-M365OpsMalwareFilterRule', 'Enable-M365OpsMalwareFilterRule', 'Disable-M365OpsMalwareFilterRule'
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

    # CLI Microsoft 365 (26/08/2026, valutazione e integrazione richieste esplicitamente
    # dall'utente): secondo server MCP oltre a Lokka, offerto SOLO se configurato per il
    # tenant attivo (vedi Get-M365OpsMcpServers - l'utente ha gia' registrato l'entry
    # 'CLI-Microsoft365' dalla GUI). Copre ~400 comandi su SharePoint, Entra, Outlook,
    # Planner, OneDrive, Purview (audit/compliance search), Teams (solo lato Graph:
    # app/meeting/chat, MAI criteri di riunione/chiamata) - NON sostituisce Exchange
    # profondo (mailbox/gruppi/regole di trasporto, il gruppo 'exo' della CLI copre solo
    # application role assignment) ne' i criteri Teams (Get-CsTeamsMeetingPolicy e affini,
    # API "Teams Admin Center" mai esposta da questa CLI) ne' Intune (nessun gruppo
    # dedicato) - quei tre restano SOLO sui moduli PowerShell/Graph gia' esistenti in questo
    # modulo, mai in fallback qui. LIMITE REALE trovato testando dal vivo (non documentato
    # da nessuna parte): con login a client secret (l'unico supportato per ora, vedi
    # Connect-M365OpsCliMicrosoft365.ps1) i comandi 'spo' (SharePoint) falliscono SEMPRE con
    # "SharePoint does not support authentication using client ID and secret" - Entra/
    # Outlook/Planner invece verificati funzionanti con dati reali. A differenza di
    # graph_api_call/exo_query, il server MCP sottostante non distingue lettura da scrittura
    # al suo interno (un solo tool generico m365_run_command esegue QUALUNQUE comando) - la
    # distinzione qui e' fatta da Test-M365OpsCliCommandReadOnly (Private), basata sul verbo
    # finale del comando (get/list/search/export/status = lettura, ogni altro verbo, incluso
    # uno sconosciuto, richiede sempre conferma) - MAI eseguita una scrittura senza passare
    # da propose_cli_m365_command. Nomi dei tool e comportamento del comando (prefisso "m365
    # " SEMPRE richiesto, "--output" da NON impostare mai a mano) verificati dal vivo
    # chiamando davvero il server MCP (0.1.23), non dalla sua documentazione pubblica, che su
    # entrambi questi punti si e' rivelata sbagliata o incompleta.
    $cliM365Configured = $false
    try { $cliM365Configured = [bool](Get-M365OpsMcpServers | Where-Object { $_.Name -eq 'CLI-Microsoft365' }) } catch { }
    if ($cliM365Configured) {
        $fallbackTools += @{
            name = "cli_m365_run_command"
            description = "Esegue un comando di SOLA LETTURA di CLI Microsoft 365 (Entra, Outlook, Planner, OneDrive, OneNote, To Do, Purview audit/compliance search, Teams solo lato Graph - app/meeting/chat, MAI criteri di riunione/chiamata). ATTENZIONE: i comandi 'spo' (SharePoint) NON funzionano su questa integrazione (il login usa client secret, che SharePoint rifiuta sempre con un errore esplicito) - per SharePoint usa sempre sharepoint_query, mai questo strumento. Usa cli_m365_search_commands PRIMA se non conosci gia' il nome esatto del comando, poi cli_m365_get_command_docs per i parametri esatti - non indovinare. Rifiutato automaticamente se il comando non e' riconosciuto come sola lettura (usa propose_cli_m365_command in quel caso)."
            input_schema = @{
                type       = "object"
                properties = @{
                    command = @{ type = "string"; description = "Comando completo CON il prefisso 'm365 ' (obbligatorio), es. 'm365 entra user get --userName mario@contoso.com', 'm365 outlook calendar event list'. NON aggiungere '--output json' o altro '--output': il formato ottimale viene scelto automaticamente da questo strumento." }
                }
                required   = @("command")
            }
        }
        $fallbackTools += @{
            name = "cli_m365_search_commands"
            description = "Cerca tra i ~400 comandi di CLI Microsoft 365 per parola chiave (fuzzy search) - usalo SEMPRE per primo quando non conosci gia' il nome esatto di un comando (es. 'condivisione esterna sito', 'evento calendario ricorrente'). Ogni risultato include name (nome comando completo, gia' col prefisso 'm365 '), description e docs (percorso da passare a cli_m365_get_command_docs per i parametri esatti)."
            input_schema = @{
                type       = "object"
                properties = @{ query = @{ type = "string"; description = "Parole chiave dell'operazione desiderata" } }
                required   = @("query")
            }
        }
        $fallbackTools += @{
            name = "cli_m365_get_command_docs"
            description = "Restituisce la documentazione completa (parametri, esempi) di UN comando CLI Microsoft 365 - usalo prima di eseguire o proporre un comando di cui non conosci gia' con certezza tutti i parametri, stesso principio di lookup_ms_docs per le cmdlet Exchange. Richiede ENTRAMBI commandName e docs, presi ESATTAMENTE dal risultato di una chiamata precedente a cli_m365_search_commands (mai indovinati) - chiama sempre prima cli_m365_search_commands se non li hai gia'."
            input_schema = @{
                type       = "object"
                properties = @{
                    commandName = @{ type = "string"; description = "Nome esatto del comando (campo 'name' di un risultato di cli_m365_search_commands), es. 'm365 spo site set'" }
                    docs        = @{ type = "string"; description = "Percorso documentazione (campo 'docs' dello STESSO risultato di cli_m365_search_commands), es. 'spo/site/site-set.mdx'" }
                }
                required   = @("commandName", "docs")
            }
        }
        $fallbackTools += @{
            name = "propose_cli_m365_command"
            description = "Proponi l'esecuzione di un comando CLI Microsoft 365 di SCRITTURA (o non riconosciuto con certezza come sola lettura). NON viene mai eseguita qui: la proposta torna all'utente per conferma esplicita prima che avvenga qualunque modifica reale. ATTENZIONE: i comandi 'spo' (SharePoint) NON funzionano su questa integrazione (vedi cli_m365_run_command) - per scritture SharePoint usa propose_sharepoint_write, mai questo strumento. Usa cli_m365_get_command_docs PRIMA se non conosci gia' con certezza la sintassi esatta."
            input_schema = @{
                type       = "object"
                properties = @{
                    command    = @{ type = "string"; description = "Comando completo CON il prefisso 'm365 ' (obbligatorio), es. 'm365 entra user set --userId ... --accountEnabled false'. NON aggiungere '--output'." }
                    reason     = @{ type = "string"; description = "Spiegazione in italiano di cosa fa questo comando e perche', da mostrare all'utente" }
                    stepNumber = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero di QUESTO passaggio, a partire da 1. Ometti per un'azione singola." }
                    totalSteps = @{ type = "integer"; description = "Solo per piani a piu' passaggi: numero totale di passaggi previsti. Ometti per un'azione singola." }
                }
                required   = @("command", "reason")
            }
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

    # BUG SERIO trovato dal vivo il 19/08/2026, segnalato dall'utente: "fai un report dei
    # sign-in log degli ultimi 7 giorni di diego@vnsys.it" ha prodotto un file Excel con UNA
    # sola riga di riepilogo testuale invece dei 114 sign-in reali del periodo (verificato dal
    # vivo: 114 eventi reali via chiamata Graph diretta). generate_raw_export sopra risolve
    # esattamente questo problema, ma SOLO per le cmdlet di exo_query (Exchange) - i dati Graph
    # (sign-in log, audit log, elenchi dispositivi/utenti tenant-wide) passano SOLO da
    # graph_api_call, che non ha equivalente: con un volume non banale (qui, 114 record x
    # ~9 campi ciascuno) il modello, dovendo riprodurre ogni riga dentro l'input JSON di
    # generate_report entro il proprio budget di token per la risposta, ha sintetizzato un
    # riepilogo invece di riportare tutti i record - esattamente il comportamento che
    # generate_report vieta esplicitamente nella sua descrizione ("non un riassunto o un
    # aggregato fatto da te"), ma la sola istruzione non basta quando il volume rende
    # impraticabile riprodurre tutto. Stesso strumento di generate_raw_export (query+export
    # lato server, dati mai nel contesto del modello) ma per un percorso Graph diretto invece
    # di una cmdlet nominata, con paginazione automatica (@odata.nextLink) - il modello non
    # deve seguirla lui stesso chiamando piu' volte graph_api_call.
    $fallbackTools += @{
        name = "generate_raw_graph_export"
        description = 'Genera un export (Excel/PDF) eseguendo una chiamata Microsoft Graph CON PAGINAZIONE AUTOMATICA e scrittura file in un solo passaggio lato server, SENZA far transitare i dati grezzi nella conversazione - equivalente di generate_raw_export ma per QUALUNQUE percorso Graph diretto (stesso "path" di graph_api_call, qualunque area: sign-in log, audit log, dispositivi, utenti, gruppi, licenze, Teams, mail flow via Graph, qualunque endpoint) invece di una cmdlet Exchange nominata. REGOLA GENERALE, non solo per un caso specifico: ogni volta che l''utente chiede un REPORT/EXPORT (non una domanda a parole) su dati Graph, preferisci SEMPRE questo strumento a graph_api_call+generate_report, a meno che tu sappia gia'' con certezza che il volume e'' minimo (poche righe) - la sequenza graph_api_call+generate_report costringe OGNI riga a passare (e essere riscritta) nel tuo output, e con un volume anche solo moderato rischi di sintetizzare un riepilogo invece di riportare tutti i record, anche se te lo si vieta esplicitamente nella descrizione di generate_report (bug reale osservato dal vivo il 19/08/2026: un report sign-in di 114 eventi reali su 7 giorni e'' uscito come 1 sola riga di riepilogo testuale invece di 114 righe vere - lo stesso rischio esiste per QUALUNQUE altro report Graph di volume comparabile, non solo per i sign-in). Specifica "path" (stesso formato/query string di graph_api_call), "beta" (bool, true se l''endpoint richiede la versione beta), "title". Il server segue automaticamente @odata.nextLink fino a un tetto di sicurezza di 50000 righe totali, poi scrive il file. La risposta che ricevi e'' solo un riepilogo (conteggio righe) - MAI i dati stessi: se ti serve analizzare il contenuto nel dettaglio (non solo esportarlo), fai invece una graph_api_call separata con un filtro piu'' stretto per restare su un volume che puoi davvero vedere. SOLA LETTURA/EXPORT, eseguito subito, non serve conferma dell''utente.'
        input_schema = @{
            type       = "object"
            properties = @{
                path   = @{ type = "string"; description = "Stesso formato di graph_api_call: percorso relativo con query string opzionale (es. filtri OData) - qualunque endpoint Graph, non solo sign-in/audit" }
                beta   = @{ type = "boolean"; description = "true se l'endpoint richiede la versione beta - stesso criterio gia' noto per graph_api_call" }
                title  = @{ type = "string"; description = "Titolo del report/nome sezione, es. 'Dispositivi non conformi' o 'Sign-in log 7 giorni - diego@contoso.com'" }
                format = @{ type = "string"; enum = @("xlsx", "pdf", "both"); description = "Come in generate_report: default 'xlsx' se omesso" }
            }
            required   = @("path", "title")
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
    # CAUSA RADICE TROVATA il 19/08/2026 (bug-hunt mirato) della voce con 'role' mancante
    # inseguita a vuoto da mesi (mitigata ma mai spiegata, sezione 20.5 della guida):
    # Get-M365OpsChatHistory fa "return @()" quando lo storico e' vuoto, ma il chiamante
    # (Gui\Server.ps1) assegna il risultato SENZA avvolgerlo in @(...) - un array vuoto
    # restituito cosi' da una funzione PowerShell "collassa" a $null quando l'assegnazione
    # non forza la semantica array (verificato: '$a = FunzioneCheRestituisceArrayVuoto'
    # rende $a proprio $null, non un array di lunghezza 0). "-History $null" arriva qui
    # come $null, non come array vuoto (un $null passato esplicitamente NON attiva il
    # default del parametro, quello scatta solo se il parametro e' del tutto omesso).
    # "$null | ForEach-Object {...}" poi NON esegue zero iterazioni come per una collezione
    # vuota - ne esegue UNA, con $_ = $null, producendo esattamente @{role=$null;
    # content=$null} - la voce fantasma filtrata (in silenzio) da ogni chiamata AI su
    # QUALSIASI conversazione che parte da uno storico vuoto (praticamente ogni "nuova
    # conversazione"/primo messaggio di sessione - riprodotto al 100% su richiesta).
    # Where-Object { $_ } qui sotto scarta un $History nullo/con voci nulle PRIMA che possa
    # mai produrre la voce fantasma, indipendentemente da come viene chiamata la funzione -
    # stessa filosofia gia' in uso per la rete di sicurezza sull'OUTPUT (righe piu' sotto),
    # ora anche sull'INPUT. Corretto anche il chiamante in Server.ps1 (@(...) su entrambe le
    # chiamate a Get-M365OpsChatHistory) per la causa radice vera e propria.
    $messages = @($History | Where-Object { $_ } | ForEach-Object { @{ role = $_.role; content = $_.text } })
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
                # Nota sorgente (26/08/2026, richiesta esplicitamente dall'utente): SOLO se
                # almeno un tool e' stato davvero chiamato in questa risposta - una risposta
                # puramente conversazionale (nessun dato del tenant coinvolto) non ne ha
                # bisogno.
                if ($sourceLabelsUsed.Count -gt 0) {
                    $azureFinalText += "`n`n_Fonte dati: $(($sourceLabelsUsed | Select-Object -Unique) -join ', ')._"
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
                if ($sourceLabelsUsed.Count -gt 0) {
                    $claudeFinalText += "`n`n_Fonte dati: $(($sourceLabelsUsed | Select-Object -Unique) -join ', ')._"
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
            $sourceLabel = Get-M365OpsToolSourceLabel -ToolName $block.name -IsDelegatedTenant $isDelegatedTenant
            $sourceLabelsUsed += $sourceLabel
            Write-Host "[AgentTools] chiamato: $callLabel" -ForegroundColor Cyan
            Write-M365OpsLog "Tool AI chiamato: $callLabel [fonte: $sourceLabel]"

            $output = try {
                switch ($block.name) {
                    # -InputObject @(...) -AsArray su ogni risultato di query in questo switch (non
                    # solo qui sotto): bug reale trovato dal vivo il 19/08/2026 durante un bug-hunt
                    # mirato. "risultato | ConvertTo-Json" appiattisce un array a 0 o 1 elementi -
                    # stessa classe di bug gia' corretta altrove nel progetto (Add-/Remove-
                    # M365OpsKnowledgeDocument, sezione 23.1 della guida) ma mai propagata qui.
                    # Con 0 elementi (es. "nessun dispositivo non conforme" - l'esito piu' comune
                    # su un tenant sano) il modello riceveva una stringa VUOTA come risultato dello
                    # strumento invece di "[]", indistinguibile da un fallimento silenzioso.
                    # Verificato dal vivo: Get-M365OpsManagedDevices -NonCompliantOnly | ConvertTo-Json
                    # su un set vuoto produce una stringa di lunghezza 0.
                    "list_devices" { ConvertTo-Json -InputObject @(Get-M365OpsManagedDevices) -Depth 5 -Compress -AsArray }
                    "list_noncompliant_devices" { ConvertTo-Json -InputObject @(Get-M365OpsManagedDevices -NonCompliantOnly) -Depth 5 -Compress -AsArray }
                    "get_device_compliance_reasons" { ConvertTo-Json -InputObject @(Get-M365OpsDeviceComplianceReasons -Id $block.input.deviceId) -Depth 5 -Compress -AsArray }
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
                    "generate_raw_graph_export" {
                        try {
                            $formats = switch ([string]$block.input.format) {
                                'pdf' { @('pdf') }
                                'both' { @('xlsx', 'pdf') }
                                default { @('xlsx') }
                            }
                            $useBeta = [bool]$block.input.beta
                            $currentPath = $block.input.path
                            $allRows = @()
                            # Stesso tetto assoluto di sicurezza di generate_raw_export (50000, non i
                            # 1000 pensati per proteggere la conversazione - qui i dati non ci entrano
                            # mai) + un tetto sul NUMERO di pagine indipendente dal conteggio righe,
                            # cosi' un endpoint che pagina in blocchi minuscoli non gira all'infinito.
                            $maxTotalRows = 50000
                            $maxPages = 500
                            $pageCount = 0
                            $nextLink = $null
                            do {
                                $resp = Invoke-M365OpsGraphRequest -Method GET -Path $currentPath -Beta:$useBeta
                                if ($null -ne $resp.value) { $allRows += @($resp.value) }
                                elseif ($resp -and -not ($resp.PSObject.Properties.Name -contains '@odata.nextLink')) { $allRows += @($resp) }
                                $nextLink = $resp.'@odata.nextLink'
                                if ($nextLink) {
                                    # @odata.nextLink e' sempre un URL assoluto - Invoke-M365OpsGraphRequest
                                    # vuole un percorso RELATIVO alla base v1.0/beta che concatena da se'
                                    # ($base + $Path) - senza questo la richiesta successiva duplicherebbe
                                    # l'host e fallirebbe.
                                    $currentPath = $nextLink -replace 'https://graph\.microsoft\.com/(v1\.0|beta)', ''
                                }
                                $pageCount++
                            } while ($nextLink -and $allRows.Count -lt $maxTotalRows -and $pageCount -lt $maxPages)

                            $truncated = [bool]$nextLink -and ($allRows.Count -ge $maxTotalRows -or $pageCount -ge $maxPages)

                            if ($allRows.Count -eq 0) {
                                "Nessun dato trovato per questo percorso - nessun file generato. Verifica il percorso/filtro prima di riprovare."
                            } else {
                                $sections = @(@{ Name = $block.input.title; Data = $allRows })
                                $result = Export-M365OpsDataReport -Sections $sections -Title $block.input.title -Formats $formats
                                $script:LastReportPath = if ($result.PdfPath) { $result.PdfPath } else { $result.XlsxPath }
                                $reportAttachments = @()
                                if ($result.XlsxPath) { $reportAttachments += @{ FileName = (Split-Path -Leaf $result.XlsxPath) } }
                                if ($result.PdfPath) { $reportAttachments += @{ FileName = (Split-Path -Leaf $result.PdfPath) } }
                                $filesNote = @(if ($result.XlsxPath) { "Excel" }; if ($result.PdfPath) { "PDF" }) -join " e "
                                $truncNote = if ($truncated) { " ATTENZIONE: risultato troncato al tetto di sicurezza ($($allRows.Count) righe) - potrebbero esserci altri dati non esportati, restringi il filtro se serve il totale esatto." } else { "" }
                                "Export generato con successo: $($allRows.Count) righe (dati MAI passati nella conversazione). $filesNote gia' allegato/i e scaricabile/i nell'interfaccia.$truncNote Nella tua risposta conferma solo che il file e' pronto e il conteggio righe, non descrivere il contenuto dei dati perche' non li hai visti."
                            }
                        }
                        catch {
                            "Export fallito: $($_.Exception.Message)"
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
                    "cli_m365_run_command" {
                        # Test-M365OpsCliCommandReadOnly (Private) - classificazione per verbo
                        # finale, difetto su scrittura per ogni verbo non riconosciuto. Un
                        # comando NON riconosciuto come sola lettura viene rifiutato QUI, non
                        # lasciato all'AI da rispettare per buona volonta' - stesso principio
                        # gia' in uso per $exoReadAllowlist (mai fidarsi del solo prompt).
                        if (-not (Test-M365OpsCliCommandReadOnly -Command $block.input.command)) {
                            "Rifiutato: questo comando non e' riconosciuto come sola lettura (l'ultimo verbo non e' get/list/search/export/status). Usa propose_cli_m365_command invece, che richiede conferma esplicita dell'utente."
                        } else {
                            $cliResult = Invoke-M365OpsMcpServerTool -ServerName 'CLI-Microsoft365' -ToolName "m365_run_command" -Arguments @{ command = $block.input.command }
                            (($cliResult.content | ForEach-Object { $_.text }) -join "`n")
                        }
                    }
                    "cli_m365_search_commands" {
                        $cliResult = Invoke-M365OpsMcpServerTool -ServerName 'CLI-Microsoft365' -ToolName "m365_search_commands" -Arguments @{ query = $block.input.query }
                        (($cliResult.content | ForEach-Object { $_.text }) -join "`n")
                    }
                    "cli_m365_get_command_docs" {
                        $cliResult = Invoke-M365OpsMcpServerTool -ServerName 'CLI-Microsoft365' -ToolName "m365_get_command_docs" -Arguments @{ commandName = $block.input.commandName; docs = $block.input.docs }
                        (($cliResult.content | ForEach-Object { $_.text }) -join "`n")
                    }
                    "propose_cli_m365_command" {
                        if ($pendingWrite) {
                            "Rifiutato: e' gia' in sospeso un'altra proposta di scrittura in questa stessa risposta ('$($pendingWrite.Kind)'). Puoi proporne solo UNA per risposta - concludi qui spiegando la proposta gia' registrata, poi proponi questa in un messaggio separato dopo che la prima e' stata confermata ed eseguita."
                        } else {
                            $pendingWrite = @{
                                Kind       = 'CliM365'
                                Command    = $block.input.command
                                Reason     = $block.input.reason
                                StepNumber = if ($block.input.stepNumber) { [int]$block.input.stepNumber } else { 1 }
                                TotalSteps = if ($block.input.totalSteps) { [int]$block.input.totalSteps } else { 1 }
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
                            # -InputObject @(...) -AsArray: vedi nota sul bug 0/1-elementi in cima a questo switch.
                            $queryResult = ConvertTo-Json -InputObject @(& $block.input.cmdlet @params) -Depth 6 -Compress -AsArray
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
                                ConvertTo-Json -InputObject @(& $block.input.cmdlet @params) -Depth 8 -Compress -AsArray
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
                                ConvertTo-Json -InputObject @(& $block.input.cmdlet @params) -Depth 6 -Compress -AsArray
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
                        # attivo in questo momento) o dal bucket globale riservato
                        # $script:M365OpsGlobalKbName, MAI da un valore che l'AI potrebbe passare
                        # - lo schema del tool infatti non espone nemmeno un parametro tenant.
                        # Questa resta l'unica garanzia strutturale di isolamento tra i KB dei
                        # singoli tenant: per costruzione non esiste un modo di chiedere a questo
                        # strumento la Knowledge Base di un tenant VERO diverso da quello attivo
                        # ora. Il bucket globale (20/08/2026) non e' un'eccezione a questa
                        # garanzia: non e' il KB di "un altro tenant", e' documentazione
                        # sull'app stessa, deliberatamente la stessa per chiunque.
                        # Prova prima il tenant corrente (piu' specifico), poi il globale in
                        # fallback se il FileName non e' li' - l'AI chiede solo un FileName, non
                        # deve sapere a priori in quale dei due cataloghi vive davvero.
                        $kbResult = $null
                        $kbErrors = @()
                        if ($script:M365OpsContext -and $script:M365OpsContext.Name) {
                            try { $kbResult = Get-M365OpsKnowledgeDocumentText -TenantName $script:M365OpsContext.Name -FileName $block.input.fileName }
                            catch { $kbErrors += $_.Exception.Message }
                        }
                        if (-not $kbResult) {
                            try { $kbResult = Get-M365OpsKnowledgeDocumentText -TenantName $script:M365OpsGlobalKbName -FileName $block.input.fileName }
                            catch { $kbErrors += $_.Exception.Message }
                        }
                        if ($kbResult) {
                            $kbResult
                        } elseif (-not $script:M365OpsContext -or -not $script:M365OpsContext.Name) {
                            "Nessun tenant attivo e nessun documento globale trovato con questo nome - impossibile leggere la Knowledge Base."
                        } else {
                            "Lettura Knowledge Base fallita: $($kbErrors -join ' / ')"
                        }
                    }
                    "compliance_query" {
                        if ($block.input.cmdlet -notin $complianceReadAllowlist) {
                            "Cmdlet '$($block.input.cmdlet)' non e' nell'elenco consentito per compliance_query."
                        } else {
                            $params = @{}
                            if ($block.input.parameters) { $block.input.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = ConvertTo-M365OpsHashtable $_.Value } }
                            try {
                                ConvertTo-Json -InputObject @(& $block.input.cmdlet @params) -Depth 6 -Compress -AsArray
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
                                ConvertTo-Json -InputObject @(& $block.input.cmdlet @params) -Depth 6 -Compress -AsArray
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
                                ConvertTo-Json -InputObject @(& $block.input.cmdlet @params) -Depth 6 -Compress -AsArray
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
