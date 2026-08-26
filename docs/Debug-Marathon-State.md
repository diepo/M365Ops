# Stato delle maratone di debug — M365Ops

Questo file è lo **stato persistente** delle "maratone di debug" richieste dall'utente. Ogni
nuova maratona DEVE leggerlo prima di iniziare (per sapere cosa è già stato fatto e ripartire
da lì) e DEVE aggiornarlo — almeno ogni ora durante l'esecuzione, e sempre a fine sessione.

Non è un changelog di release (quello resta `Guida-Configurazione.html`) — è un log di lavoro
tra maratone, pensato per essere letto da un'altra sessione Claude senza contesto pregresso.

## Regole della maratona (definite dall'utente il 23/08/2026, valide per ogni maratona futura)

1. **Durata minima 4 ore** dall'inizio effettivo del lavoro (non dalla richiesta). Se il lavoro
   richiede più di 4 ore per essere fatto bene, si estende — non si taglia per rientrare nel
   tempo. Annotare sempre l'ora di inizio reale in questo file.
2. **Obiettivo reale: verificare TUTTO il codice**, non solo le aree toccate di recente. Le
   maratone precedenti NON garantiscono che il codice da loro corretto sia ora perfetto — va
   ri-testato anche quello, oltre a cercare debolezze mai viste prima su codice preesistente.
   Non dare per assodato nulla solo perché una maratona passata lo ha già "chiuso".
3. **Un agente dedicato SOLO all'autoreview dei fix**: il cui unico compito è rileggere le
   modifiche fatte in QUESTA maratona (non l'intero codebase) cercando regressioni introdotte
   dai fix stessi — mai bug nuovi indipendenti, quello è compito degli altri agenti. Pattern già
   collaudato (ha trovato 4 regressioni reali nella maratona del 23/08/2026, sezione storica
   sotto).
4. **Testare ogni elemento della GUI** alla ricerca di blocchi, stati inconsistenti, pulsanti che
   restano disabilitati, messaggi fuorvianti - non solo le funzionalità "principali".
5. **Testare ogni comando/area coperta dall'app, sia in lettura che in scrittura**, con uso
   realistico (scenari in linguaggio naturale, persona "utente naive" già in uso nelle maratone
   precedenti), verificando l'output reale e correggendo/migliorando dove serve — mai solo
   lettura del codice quando è possibile riprodurre dal vivo.
6. **Parallelizzare con più agenti dove possibile**, sia per velocità sia per aumentare
   complessità/realismo dei test (scenari indipendenti eseguiti in parallelo).
7. **Report almeno ogni ora**, scritti sia in chat sia in questo file (sezione "Log delle
   sessioni" sotto) — non solo un report finale.
8. **Dichiarare esplicitamente quali agenti sono stati spinnati e con quale compito** in questo
   file, così diventano parte dell'ecosistema noto della maratona (riutilizzabili/referenziabili
   dalle maratone successive).
9. **Proporre modifiche e miglioramenti liberamente**, non solo correggere bug stretti.

## Stato noto al 23/08/2026 (prima che la metodologia sopra fosse formalizzata)

Le maratone precedenti (v0.9.61 → v0.9.67, tutte in data 23/08/2026) hanno already trovato e
corretto **38 bug reali** (34 nella maratona principale di 16 ore + 4 fix urgenti fuori
sequenza: CLI-Microsoft365 non configurato di default, login delegato CLI365 rotto, pulsanti
Annulla incoerenti, messaggio "server bloccato" mancante). Report narrativo completo della
maratona principale: artifact pubblicato
`https://claude.ai/code/artifact/201ca6a9-4334-492c-af59-b6e5c5118be2` (non garantito accessibile
da sessioni future senza URL - il contenuto essenziale è comunque riassunto qui sotto).

### Aree già coperte da almeno un giro di audit/test dal vivo
Exchange, Teams, Compliance/Purview, Intune, SharePoint/Entra, GUI/installer, catalogo comandi
locale (Gui/CommandCatalog.ps1), packaging Win32/Autopilot, report e persistenza chat/KB,
isolamento reattivo (Delegato+AppOnly), CLI Microsoft 365 (nuovo connettore).

### Open item NON ancora risolti (da NON considerare chiusi, da ri-verificare)
- **⚠️ AZIONE RICHIESTA - residuo reale sul tenant "vnsys-test"**: il sito SharePoint
  `https://vnsysit.sharepoint.com/sites/ZZTEST-marathon-Site` (creato il 23/08/2026 per un test
  di scrittura) resta **Active**, non rimosso dopo 7 tentativi (4 dell'agente + 3 miei, incluso
  un tentativo via Graph DELETE) - vincolo di piattaforma su siti appena creati, non un bug.
  Ritentare `Remove-PnPTenantSite -Url '...' -Force` una volta passato piu' tempo, o rimuoverlo
  dal centro amministrazione SharePoint. Verificarlo PER PRIMO in qualunque maratona futura.
- **Popup interattivo del worker isolato Delegato** (Exchange/Teams/Purview, v0.9.61): mai
  verificato dal vivo con un vero login umano+MFA — richiede un utente reale al tavolo.
- **Secondo sintomo del conflitto .NET sezione 6.6**: un errore di token JWT (`IDX12729`) o di
  serializzazione compare SOLO in un processo server attivo da ore con più isolamenti già
  scattati (Teams + Purview + Exchange in sequenza) — non riproducibile in uno script pwsh
  appena avviato. Il riavvio del server (tab Manutenzione) lo risolve sempre, confermato dal
  vivo più volte, ma la causa radice nel processo long-running resta non identificata.
- **`Set-M365OpsAdminTemplateSetting`**: sospetto "added" invece di "updated" su una
  reimpostazione — mai confermato dal vivo.
- **Foglio Excel con sola riga di intestazione**: sparisce silenziosamente dal testo estratto
  per la Knowledge Base — severità bassa, non ancora corretto.
- **Lettura .txt/.md senza `-Encoding` esplicito**: garbla accenti solo sotto Windows PowerShell
  5.1 (il percorso GUI reale usa sempre pwsh 7) — gap solo per chi importa il modulo a mano su
  5.1.
- **Installer su VM pulita (Windows Sandbox)**: mai testato in questo giro, solo audit statico.
- **Caricamento file (Documentazione/Upload)**: non testabile con gli strumenti browser
  disponibili finora — nessun input file utilizzabile via automazione. Da riprovare con un
  approccio diverso (es. drag&drop simulato, o chiedere all'utente di caricare un file di test).

### Aree MAI toccate da nessun giro finora (priorità alta per la prossima maratona)
- CLI Microsoft 365 come connettore AI in chat (appena reso di default, mai testato con dati
  reali oltre al login stesso - nessun comando `spo`/`entra`/`outlook`/`planner` reale ancora
  eseguito e verificato).
- **RISOLTO (agente dedicato, 23/08/2026)**: `propose_graph_write` su un tenant Delegato con SOLO
  CLI Microsoft 365 connesso falliva allo stesso modo scoperto per `graph_api_call` (v0.9.68,
  sessione delegata generica mancante) - nessun fallback verso `propose_cli_m365_command` per le
  scritture. Investigato con un confronto dal vivo (creazione+eliminazione di un gruppo Entra su
  "vnsys-test", sia via POST Graph diretto sia via `m365 entra group add`), come richiesto.
  **Evidenza reale raccolta**: le normalizzazioni/validazioni SONO effettivamente diverse tra i
  due percorsi - `m365 entra group add` RIFIUTA il comando senza un `--type security|microsoft365`
  esplicito (nessun equivalente nel body Graph di `New-M365OpsGroup`, che usa
  `mailEnabled`/`securityEnabled` booleani), e anche passando `--type` corretto il gruppo risultante
  ha `mailNickname` generato automaticamente (non derivato dal displayName) e `visibility="Public"`
  invece di `null`. Per questo **NON e' stata implementata una traduzione automatica** del corpo
  Graph in un comando CLI365 (rischio reale, confermato, non ipotetico). E' stato invece
  implementato un **guard deterministico, non una traduzione**: in `Invoke-M365OpsAgentTools.ps1`,
  il dispatch di `propose_graph_write` ora rifiuta ESPLICITAMENTE (prima che l'utente veda anche
  solo una richiesta di conferma) un percorso Entra ID (`/users`, `/groups`, `/devices`,
  `/directoryRoles`, `/organization`, `/domains`) quando la sessione Graph delegata generica non e'
  attiva e CLI Microsoft 365 e' configurato - rimandando l'AI a `propose_cli_m365_command`, che
  deve comunque costruire da sola il comando corretto (stesso doppio cancello di conferma di ogni
  altra scrittura, nessun bypass). **Verificato dal vivo attraverso il percorso reale del guard**
  (stato Delegato+sessione-mancante simulato su "vnsys-test", chiamata IA reale non scriptata):
  l'IA ha davvero chiamato `propose_cli_m365_command` invece di `propose_graph_write` - il guard
  funziona - ma ha costruito il comando per analogia col body Graph (`--securityEnabled true
  --mailEnabled false` invece di `--type security`), esattamente il rischio di normalizzazione
  gia' scoperto: CLI365 ha rifiutato il comando con un errore chiaro, nessun oggetto creato,
  nessun residuo (confermato con una query indipendente). Conferma che il guard e' sicuro per
  costruzione (mai un'esecuzione senza conferma, mai una traduzione automatica dei parametri) anche
  quando l'IA sbaglia la sintassi CLI365 - lo stesso identico rischio che esisterebbe comunque per
  QUALUNQUE `propose_cli_m365_command` scritto male dall'IA, non introdotto da questo fix. Pulizia
  finale: tutti gli oggetti `ZZTEST-marathon-fallback*` creati durante l'indagine (via Graph e via
  CLI365) eliminati e confermati assenti con query indipendenti separate.
- Tenant Delegati completi end-to-end (Exchange+Teams+SharePoint+Purview+Intune+CLI365 tutti
  connessi insieme sullo stesso tenant, sequenza realistica) — in corso di setup da parte
  dell'utente al 23/08/2026, vedi log sessioni sotto.
- Script personalizzati (`Scripts\Custom`) — mai stress-testati in questa serie di maratone.
- Invio report via email (Mail.Send) — mai verificato con un invio reale.
- Aggiornamenti applicativi (canale Stabile/Test, `Controlla aggiornamenti`) — mai testato dal
  vivo.

## Log delle sessioni

### 23/08/2026 — formalizzazione della metodologia + fix urgenti pre-maratona
- Non è una maratona vera e propria (durata <4h, nessun agente spinnato) — è la sessione in cui
  l'utente ha DEFINITO le regole sopra e chiesto di prepararsi a una maratona sui tenant
  Delegati.
- Fix urgenti spediti prima di iniziare (v0.9.67, commit `805eae8`): CLI-Microsoft365 default
  incorporato per ogni tenant; login delegato CLI365 riparato (mancava `--appId`, verificato dal
  vivo con probe diretto `m365 login`); pulsante Annulla dedicato per Graph/Exchange (stesso
  stile di `cancel-edit-profile-btn`); avviso "server bloccato" dopo 25s per le connessioni
  bloccanti (Teams/SharePoint/Purview/Intune/CLI365-delegato).
- Durante il setup manuale dell'utente sono emersi altri due problemi reali, corretti al volo
  prima dell'inizio della maratona vera e propria:
  - **Doppia istanza server**: l'utente aveva due processi M365Ops reali contemporaneamente
    attivi sulle porte 8743 e 8745 sul proprio PC (una vecchia rimasta appesa, una nuova) — il
    mio ambiente di test è sandboxato e separato dal desktop reale dell'utente, quindi i miei
    `/api/restart` non toccavano affatto le sue istanze. Nessun fix di codice (è un problema di
    processi lasciati aperti, non un bug) — dato all'utente un playbook PowerShell per trovare/
    chiudere entrambi i processi e rilanciare pulito da capo.
  - **v0.9.68, commit `e0620fe`**: su un tenant Delegato con SOLO CLI Microsoft 365 connesso,
    "quanti utenti ha il tenant?" chiedeva un secondo login Graph inutile invece di provare
    CLI365 (già connesso, dominio giusto - Entra). Causa: il system prompt distingueva solo "il
    dato non c'è" da "la connessione stessa manca" nel decidere quando usare cli_m365_* come
    fallback. Corretto con un'eccezione esplicita per i tenant Delegati.
- Altri due problemi reali emersi e corretti durante il setup, prima dell'avvio:
  - **v0.9.69, commit `bff12f3`**: la preferenza CLI365 di v0.9.68 era solo reattiva (dopo un
    fallimento) e solo per le letture. Estesa a proattiva (calcolata prima del system prompt) e
    anche alle scritture (`propose_graph_write`), su richiesta esplicita: "trattalo come tool
    idempotente a Graph laddove ha possibilità". Corretto anche un caso nascosto: SharePoint su
    Delegato falliva con lo stesso errore perché `Sync-M365OpsSharePointAppRegistration` (ricerca
    una tantum dell'app dedicata) dipendeva da Graph per un dettaglio interno - ora prova prima
    CLI365 (`m365 entra app get --name`, verificato dal vivo).
  - Doppia istanza server chiarita: non erano processi appesi, erano due istanze REALI e
    intenzionali (`vnsys delegata` su 8743, `AlePiras` su 8745, PID trovati con
    `Get-CimInstance Win32_Process` invece di `Get-NetTCPConnection`, che su HTTP.sys attribuisce
    tutto a PID 4/System - falsa pista). Chiusa la 8743, tenuta solo AlePiras.
- L'utente NON è riuscito a completare tutte le connessioni Delegate su "AlePiras" prima di
  doversi allontanare (CLI Microsoft 365 sì, Exchange/Teams/SharePoint/Purview/Intune/Graph
  generico no) - ha segnalato anche un problema di affidabilità non ancora diagnosticato: dal
  click su "Connetti" all'apertura del browser passa molto tempo, e a volte il browser non si
  apre affatto. Ha chiesto esplicitamente di investigarlo con test reali durante la maratona.
- **Istruzione esplicita per procedere**: "avvio la maratona ORA con quello che hai e puoi fare,
  se delegata non hai tutto fai quello che puoi poi torna in app registered" - quindi: usare
  AlePiras/Delegato per quello che è già testabile (CLI365), investigare il problema di
  affidabilità del login, poi spostare il grosso dei test sul tenant App-only "vnsys-test" (dove
  posso operare senza bisogno di login umano/MFA per quasi tutto).

## ORA DI INIZIO UFFICIALE: 23/08/2026, 12:42 (locale)
Durata minima impegnata: 4 ore, quindi fino ad almeno le 16:42. Da estendere onestamente in
chat e qui se il lavoro richiede più tempo per essere fatto bene - non tagliare per rientrare.

## Agenti attivi in questa maratona

*(sezione aggiornata mano a mano che vengono spinnati - vedi anche i log sessione sotto per il
dettaglio di cosa hanno trovato)*

1. **Agente "Connection reliability investigator"** (general-purpose, background, sola lettura
   di codice - nessuna modifica) — COMPLETATO. Traccia riga per riga cosa succede da
   Connect-M365Ops{SharePoint,Teams,Intune,CliMicrosoft365,Compliance}.ps1 fino all'apertura
   reale del browser. Trovato: (a) `Connect-M365OpsSharePoint.ps1` L60-71 puo' installare
   PnP.PowerShell da PSGallery al volo (rete, decine di secondi-minuti); (b) gli
   `Assert-M365Ops*SafeVersion` fanno un controllo integrita' file a ogni connect, che puo'
   scatenare intermittentemente una reinstallazione se un file sembra corrotto (AV/scrittura
   parziale); (c) `Sync-M365OpsSharePointAppRegistration` aggiunge un'ulteriore chiamata di rete
   prima del login vero e proprio, la prima volta per tenant; (d) ipotesi WAM sollevata per
   Purview (`Connect-IPPSSession` senza `-DisableWAM` equivalente, a differenza di Teams) - **verificata
   e SMENTITA da me subito dopo**: le versioni moduli REALMENTE installate su questo PC
   (`Get-Module -ListAvailable`, non assunto) sono ExchangeOnlineManagement 3.4.0 e
   MicrosoftTeams 6.5.0, entrambe precedenti a quando Microsoft ha reso WAM il broker
   predefinito (confermato via ricerca web: EXO da 3.7.0, Teams da 7.8.1-preview) - quindi WAM
   non è la causa su QUESTA installazione, anche se resta un rischio reale se in futuro i
   moduli si aggiornassero oltre quelle soglie. Causa reale piu' probabile, confermata: (a)+(b)+(c)
   sopra, MA il problema piu' ingannevole trovato è che **la GUI non distingueva mai "sto
   installando un modulo" da "sto aspettando il tuo login"** - stesso testo statico per
   entrambe le fasi. **Fix spedito, v0.9.70, commit `eb28025`**: messaggio iniziale onesto sulla
   possibile attesa moduli; soglia dell'avviso "server bloccato" alzata da 25s a 45s (25s
   scattava spesso durante un'installazione ancora legittima) e riscritta per coprire entrambe
   le cause plausibili. **Non risolto perché non risolvibile con un fix leggero**: i veri tempi
   di installazione moduli/rete restano quelli che sono - il fix e' sulla comunicazione, non sulla
   velocita' stessa. Se il problema persiste anche a moduli gia' installati (nessun reinstall in
   corso), va riaperta l'indagine con log piu' dettagliati durante un test dal vivo.
3. **Agente "Test cmdlet lettura Exchange/Intune/Purview"** (general-purpose, background, test
   dal vivo via pwsh diretto su tenant "vnsys-test" AppOnly - nessun browser) — COMPLETATO.
   ~65 invocazioni reali (40 Exchange, 19 Intune, 2 Purview). **4 bug reali trovati e corretti,
   tutti riverificati dal vivo dopo il fix - v0.9.71, commit da seguire**:
   - `Get-M365OpsAllMailboxes`/`Get-M365OpsSharedMailboxes`/`Get-M365OpsSharedMailboxReport`:
     colonna `WhenMailboxCreated` sempre `$null` perche' `Get-EXOMailbox` non la include nel set
     di proprieta' di default - serve `-Properties WhenMailboxCreated` esplicito. Stesso bug in
     tre punti diversi, mai propagato prima.
   - `Get-M365OpsMailFlowReport`: il fallback (quando `Get-MailTrafficSummaryReport` non e'
     disponibile) usava ancora `Get-MessageTrace` V1, in dismissione dal 1/9/2025 - falliva ormai
     SEMPRE con un errore terminante su questo tenant, proprio quando il fallback doveva essere
     la rete di sicurezza. Sostituito con `Get-MessageTraceV2 -ResultSize` (stesso fix gia' noto
     e applicato altrove in `Get-M365OpsMessageTrace.ps1`, mai propagato qui).
   - Confermati NON bug: retention policy Purview (limite RBAC gia' documentato), vari elenchi
     Intune vuoti per mancanza di configurazione reale sul tenant di test, non per fallimento
     silenzioso (verificato incrociando con cmdlet correlate non vuote).
   - Nota collaterale, nessuna azione richiesta: durante il test di `ConfigurationPolicyTemplates`
     Intune e' comparsa una baseline reale del tenant chiamata "Local AI Agent Baseline -
     OpenClaw" (dato genuino del tenant di test, non iniettato dal test) - l'agente l'ha
     correttamente trattata come semplice dato osservato, nessuna direttiva contenuta, nessuna
     azione presa. Segnalato qui solo per trasparenza.
4. **Agente "Regression review v0.9.67-v0.9.71"** (general-purpose, background, `git diff
   e85120d..HEAD`) — COMPLETATO. **1 regressione reale trovata e corretta, v0.9.72**: in
   `Sync-M365OpsSharePointAppRegistration.ps1` (il fix CLI365/SharePoint appena spedito), quando
   CLI Microsoft 365 risponde correttamente "app non trovata" (testo semplice, non JSON -
   `"Error: App with name 'X' not found..."`), il codice lo trattava come un errore CLI365
   generico e cadeva nel tentativo Graph successivo - che fallisce SEMPRE in questo scenario
   (nessuna sessione Graph, e' proprio per questo che si e' provato CLI365 prima), producendo
   "Error: fai il login Graph" invece del corretto "NotFound" con il comando di registrazione
   pronto. Proprio il caso PIU' comune la prima volta su un tenant nuovo - la ragion d'essere
   della funzione. Corretto riconoscendo il testo "not found" nella risposta CLI365, verificato
   dal vivo contro l'output reale della CLI. Altri 4 punti controllati (Gui/index.html sintassi
   e coerenza id/riferimenti, inerzia del prompt proattivo su AppOnly, forma output dei 4 fix
   Exchange verso i chiamanti reali, sovrapposizione dei due inserimenti di prompt v0.9.68/69) -
   **nessun problema trovato**, dettaglio nel commit.
5. **Agente "Test scrittura Intune/Entra + pulizia"** (general-purpose, background, test dal
   vivo via pwsh diretto su "vnsys-test", nessun browser) — COMPLETATO. Ciclo completo
   crea→verifica→elimina→verifica su ScopeTag e Configuration Policy (dati Settings Catalog
   reali, assegnazione inclusa) - tutti gli oggetti `ZZTEST-marathon-*` confermati eliminati con
   una scansione finale dedicata (0 residui). Nessun `AssignmentFilter` in questo codebase (mai
   implementato, non un gap - nulla da testare li'). **1 bug di documentazione trovato e
   corretto, v0.9.72**: `New-M365OpsConfigurationPolicy` dichiarava che `-Settings` poteva essere
   omesso (specialmente con `-TemplateId`) per un contenitore vuoto coi default del template -
   verificato dal vivo che e' FALSO in ogni caso provato (senza `-TemplateId` e con un template
   Endpoint Security reale, "Defender Update controls"): Graph rifiuta sempre con 400 "The
   Settings field is required." Comportamento del cmdlet gia' corretto, solo la documentazione
   era sbagliata - corretta. Letture Entra aggiuntive (conditional access, compliance state
   summary, app registration) tutte OK, nessun problema.
6. **Agente "Test lettura Teams/SharePoint"** (general-purpose, background, test dal vivo via
   pwsh diretto su "vnsys-test" AppOnly - nessun browser) — COMPLETATO. 16 cmdlet invocate per
   davvero. **2 bug reali trovati e corretti, entrambi riverificati dal vivo - v0.9.74**:
   - `Connect-M365OpsTeams`: `Connect-MicrosoftTeams` restituisce un oggetto quando riesce
     (Account/Environment/Tenant/TenantId) - non soppresso con `Out-Null` (a differenza del
     lato Exchange, gia' corretto), finiva sulla pipeline di output e si mescolava ai risultati
     reali di ogni chiamante alla PRIMA connessione riuscita per sessione (es.
     `Get-M365OpsTeamsList` restituiva 16 righe invece di 15, con una vuota in testa) - mai
     notato prima perche' capita solo una volta per sessione. Aggiunto `| Out-Null` su entrambi
     i rami (Delegato+AppOnly).
   - `Get-M365OpsTeamsExternalAccessConfig`: le 4 sezioni (federazione/messaggistica-ospiti/
     riunioni-ospiti/chiamate-ospiti) avevano ciascuna il proprio set di colonne invece di uno
     schema unificato (a differenza del gemello `Get-M365OpsTeamsPolicies`, che lo fa apposta) -
     `ConvertTo-Csv`/`Export-Csv`/`Format-Table` usano le proprieta' del PRIMO oggetto per
     l'intera tabella, quindi dati reali (es. `AllowUserChat=True`) sparivano silenziosamente da
     ogni export tabellare pur essendo presenti sull'oggetto. Corretto unificando le colonne.
   - Nota di documentazione aggiornata nello stesso giro: `Get-M365OpsTeamsPolicies` dichiarava
     ancora "permesso non concesso, non verificato" - risulta invece concesso su questo tenant
     (19 righe reali restituite), nota corretta per riflettere lo stato vero.
   - Nessun limite di permesso/licenza ha bloccato nulla in questo giro (il permesso Teams
     Admin API risulta gia' concesso), nessun conflitto .NET Teams/Exchange incontrato (script
     fresco, coerente con quanto gia' documentato sopra sull'open item).
7. **Agente "Test scrittura Exchange/SharePoint/Teams + pulizia"** (general-purpose, background,
   test dal vivo via pwsh diretto su "vnsys-test", nessun browser) — COMPLETATO. Exchange
   (gruppi distribuzione, mailbox condivise, permessi) e Teams (crea/modifica/elimina)
   interamente PASS, tutto pulito e confermato. SharePoint (crea sito, quota, condivisione,
   membri, ereditarieta' permessi) PASS sulle operazioni stesse.
   **1 bug reale trovato e corretto, v0.9.75**: `Set-M365OpsNotificationTemplateMessage` -
   aggiornare un messaggio di notifica GIA' localizzato falliva SEMPRE con 400 "Cannot Patch
   Locale Property" (il body del PATCH includeva ancora `locale`, immutabile via PATCH perche'
   gia' parte dell'ID risorsa - ereditato per errore dal body condiviso col ramo POST). Creare
   un messaggio NUOVO funzionava, solo l'aggiornamento di uno esistente era rotto. Corretto
   separando i due body, riverificato dal vivo.
   **Gap reale scoperto, non colmato**: nessun wrapper `Remove-M365OpsSharePointSite` esiste nel
   modulo - la pulizia ha dovuto usare `Remove-PnPTenantSite` nativo, che ha fallito
   ripetutamente ("The requested operation is not supported for site") su un sito appena creato
   - vincolo di piattaforma (probabile restrizione temporale post-creazione), non un bug del
   modulo. Confermato anche da me con un tentativo aggiuntivo via Graph DELETE (fallito
   ugualmente, 400 Bad Request - Graph v1.0 non supporta comunque la cancellazione di una site
   collection per questa via).<br><br>
   **⚠️ RESIDUO REALE SUL TENANT, azione umana richiesta**: il sito
   `https://vnsysit.sharepoint.com/sites/ZZTEST-marathon-Site` (creato per il test, template
   Communication Site) resta **Active** su vnsys-test, NON rimosso nonostante 7 tentativi totali
   su due sessioni diverse. Da ritentare piu' avanti (probabilmente basta aspettare che la
   piattaforma completi il provisioning) con
   `Remove-PnPTenantSite -Url 'https://vnsysit.sharepoint.com/sites/ZZTEST-marathon-Site' -Force`
   oppure dal centro amministrazione SharePoint. **Non dare questa pulizia per scontata nella
   prossima maratona - verificarla per prima cosa.**

## Test dal vivo (io stesso, GUI su vnsys-test) durante l'attesa degli agenti

- **"Stato permessi" e domanda naturale su Conditional Access - PASS**: audit permessi reale via
  Graph, risposta coerente con l'agente 5 (2 criteri CA trovati, stessi stati).
- **GUI a larghezza mobile (mai testata in nessuna maratona precedente) - 2 bug reali trovati e
  corretti, v0.9.73**: (1) nessun tag `<meta name="viewport">` in `Gui/index.html` - su mobile
  reale la pagina si renderizza su una viewport virtuale desktop (980px) poi si rimpicciolisce,
  illeggibile senza zoom continuo (verificato `window.visualViewport.width` = 980 invece di
  375). Aggiunto il tag standard `width=device-width, initial-scale=1`. (2) col viewport
  corretto, il gruppo di pulsanti header non andava mai a capo (nessun `flex-wrap`), causando un
  piccolo overflow orizzontale residuo (435px su 375px di schermo, misurato via
  `getBoundingClientRect`). Aggiunto `flex-wrap:wrap` al contenitore. Entrambi verificati dal
  vivo prima/dopo (screenshot + misure DOM dirette), nessun impatto sul layout desktop
  (verificato ridimensionando avanti e indietro).

- **CLI Microsoft 365 usato per davvero in chat (non solo login) - PRIMA VOLTA, PASS con nota
  sulle prestazioni**: "ci sono piani planner attivi nel tenant? mi serve un elenco" (Planner non
  ha nessuna cmdlet PowerShell dedicata in questo modulo - forza l'uso di Lokka/CLI365). L'AI ha
  provato prima Graph poi CLI365 su un gruppo reale (`PlannerTest`), entrambi hanno risposto
  onestamente "You do not have the required permissions" (Tasks.Read.All/GroupMember.Read.All
  mancanti su questo tenant - limite di permesso reale, non un bug), citando entrambe le fonti
  in coda. Conferma dal vivo che il fix "CLI365 proattivo" (v0.9.69) funziona per davvero in un
  caso reale, non solo in teoria.<br>**Nota sulle prestazioni, non un bug ma da tenere a mente**:
  la risposta ha impiegato ~3 minuti (13:25→13:28) - durante questa finestra il server e'
  risultato COMPLETAMENTE non rispondente anche a richieste HTTP banali e scollegate
  (`GET /api/server-port`), verificato sia dal browser sia con una `curl` diretta esterna al
  browser, entrambe in timeout. Si e' sbloccato da solo senza intervento. Coerente con
  l'architettura gia' ampiamente documentata (server a thread singolo), ma e' la prima volta che
  si osserva un blocco COMPLETO (non solo del turno di chat in corso) per un tempo cosi' lungo -
  probabile causa: il primo avvio/handshake del sottoprocesso CLI365 via `npx` (osservato nei
  processi reali: due `node.exe` spawnati proprio in quella finestra temporale) e' un'operazione
  sincrona pesante nel processo server. Non affrontato come fix in questo giro (nessun errore,
  solo lentezza al primo uso per tenant/sessione) - da tenere presente se il pattern si ripete.

- **Script personalizzati - MAI testato prima, ora coperto end-to-end, PASS**: "ogni tanto mi
  serve controllare quali gruppi di distribuzione non hanno nessun membro, puoi automatizzarlo
  come script cosi' lo riuso in futuro?" → l'AI ha correttamente riconosciuto il caso d'uso
  ricorrente (non una richiesta one-off), proposto `propose_new_custom_script` con codice
  conforme al template (`Get-M365OpsEmptyDistributionGroups`, dichiarato ReadOnly), richiesto
  conferma prima di scrivere il file (corretto, anche se ReadOnly - e' comunque una scrittura sul
  filesystem). Confermato "si" → salvato in `Scripts\Custom\`, **il server si e' riavviato da
  solo per caricarlo** (comportamento corretto, spiegato chiaramente all'utente prima che
  succedesse) → richiesta successiva "usa lo script che hai appena creato" → eseguito per
  davvero, trovati 2 gruppi reali (`gruppo_dynamicdl`, `test.2`), nessuna invenzione. Unica nota:
  la generazione ha impiegato ~180 secondi (normale per generazione+validazione codice, non un
  bug) - durante l'attesa il server e' temporaneamente sparito dalla lista processi tracciata dal
  mio harness, causa proprio il riavvio automatico legittimo, non un crash (verificato
  ripetendo `fetch('/api/server-port')`, sempre raggiungibile). Script di test rimosso a mano
  dopo la verifica (`Scripts\Custom\Get-M365OpsEmptyDistributionGroups.ps1`), server riavviato
  di nuovo per pulizia.
- **"Stato permessi" (pulsante header) - PASS**: audit permessi reali via Graph, non statico -
  stato corretto per area (Intune/Entra/MFA/Teams/SharePoint/Exchange), con guida azionabile per
  ogni permesso mancante (dove aggiungerlo, che consenso serve). Nessun bug.
- **Ciclo scrittura Entra completo (crea+elimina gruppo) - PASS**: "crea un gruppo di sicurezza
  QA-Marathon-Delegata con automation@vnsys.it" → verificato l'utente su Entra prima di proporre,
  body Graph esatto mostrato, confermato, creato con successo (ID reale ottenuto e usato per la
  pulizia) → eliminato subito dopo, `DELETE /groups/{id}` confermato "Success (No Content)".
  Trasparenza fonte/comando presente su entrambi i passaggi. Nessun bug, nessun residuo lasciato
  sul tenant.

- **Segnalazione dal vivo dell'utente: "sembra che il server sia crashato" durante il login
  Teams delegato - INDAGATO, NON era un crash, 2 fix reali spediti, v0.9.76**: l'utente ha
  completato un login Teams delegato su un tenant reale (non il mio, il suo - AlePiras) e ha
  ricevuto "Errore di comunicazione: NetworkError when attempting to fetch resource",
  interpretandolo come un crash del server. I log reali che l'utente stesso ha condiviso hanno
  chiarito la vera sequenza: conflitto .NET noto (sezione 6.6) rilevato → isolamento reattivo
  scattato → connessione riuscita tramite un SECONDO popup di login (nel processo worker
  isolato) → successo lato server. Il problema vero: durante l'attesa umana reale del login
  (aggravata da un secondo popup mai comunicato all'utente), la connessione TCP del browser e'
  caduta prima che la risposta tornasse - `fetch()` restituisce un generico NetworkError,
  indistinguibile da un fallimento vero anche quando il server ha gia' finito con successo.
  **Fix**: (1) tutti e 5 i pulsanti di connessione bloccanti ora ricontrollano lo stato reale
  della connessione quando il `fetch()` stesso fallisce, invece di lasciare solo il messaggio
  d'errore grezzo; (2) Teams avvisa ora esplicitamente (nel popup di conferma e nel messaggio di
  stato) che potrebbe comparire un secondo popup separato se scatta il conflitto noto.
  **Domanda dell'utente, con risposta**: "è possibile rendere multi-thread il server, così
  queste operazioni non blocchino/facciano crashare tutto?" - risposta data in chat (vedi
  trascrizione): NON raccomandato come riscrittura piena in questo giro - l'intera architettura
  del progetto (scritture proponi-poi-conferma con un solo slot in memoria, contesto tenant
  attivo condiviso, gestione processi MCP) e' deliberatamente e ripetutamente documentata come
  "mai concorrente" per la sicurezza dei dati - multi-threading vero richiederebbe ripensare
  tutto questo stato condiviso in modo thread-safe, un lavoro grosso e rischioso (bug di
  concorrenza potenzialmente peggiori del problema attuale, es. fuga di dati tra richieste
  concorrenti di tenant diversi). Alternativa proposta invece (non ancora implementata, da
  valutare in un giro futuro se il problema si ripete spesso): eseguire SOLO le operazioni di
  login bloccanti (Teams/SharePoint/Purview/Intune/CLI365) in un job/runspace in background,
  cosi' il resto del server (pagine, log, altri tenant) resta reattivo durante l'attesa, senza
  toccare il modello di concorrenza del resto dell'app.<br><br>
  **Rete di sicurezza indipendente aggiunta nello stesso giro**: il ciclo principale del server
  (`Gui/Server.ps1`) non aveva MAI un `catch` esterno (solo `try{while}finally{}`) - qualunque
  eccezione sfuggita al gestore per-richiesta terminerebbe l'intero processo senza lasciare
  traccia nei log. Aggiunto un `catch` che logga l'eccezione fatale prima che il processo
  termini davvero - non impedisce un crash genuino, ma garantisce diagnosticabilita' se succede.

## Maratona sull'ambiente Delegato "AlePiras" (iniziata dopo che l'utente ha completato tutti i
login umani reali - io non posso testare questo tenant direttamente, sessione live solo sul suo
processo server, non nel mio ambiente sandboxato - l'utente esegue gli scenari, io interpreto e
correggo)

- **Scenario 1 "mostrami i team di cui faccio parte" - bug reale trovato e corretto, v0.9.77**:
  vedi sopra (sezione "domande in prima persona"), stessa causa del bug #2 sotto.
- **Scenario 5 "quanti utenti hanno mfa non configurata?" - bug reale trovato e corretto,
  v0.9.78**: il modello ha risposto "non posso determinarlo... servirebbe interrogare i metodi
  di autenticazione" SENZA tentare nessuna chiamata reale - confermato nel log
  (Avvio→completato in 3s, zero righe "Tool AI chiamato" nel mezzo), a differenza di altre
  domande nella STESSA conversazione che hanno chiamato tool regolarmente (es. Planner, 2
  chiamate reali poco dopo) - quindi non e' un problema di "tool rotti", il modello ha scelto
  di non provare SOLO per questa domanda. Causa: nessun tool dedicato per un conteggio
  aggregato su tutto il tenant (solo per un singolo utente via UPN) - il modello doveva
  improvvisare l'endpoint Graph giusto (`/reports/authenticationMethods/userRegistrationDetails`)
  da solo ogni volta, funzionava a volte (era gia' riuscito su vnsys-test in precedenza nella
  stessa maratona) e a volte no. Verificato dal vivo che l'endpoint e' corretto (52 utenti, 35
  senza MFA, stesso conteggio esatto di prima) - aggiunta la guida esplicita nella descrizione
  del tool `get_user_mfa_status`, non piu' lasciato all'improvvisazione.
- **Scenario "crea gruppo ZZTEST-delegata + elimina" (dal log) - PASS**: ciclo completo
  propose_graph_write→conferma→propose_graph_write(delete)→conferma, entrambi riusciti, nessun
  residuo (confermato dal log stesso, "Esecuzione azione confermata" su entrambi i turni).
- **Scenario "ci sono piani planner attivi?" (CLI365-escluso, via Graph diretto stavolta) -
  PASS**: 2 chiamate reali (`/groups` poi `/groups/{id}/planner/plans`), completato in ~9s -
  molto piu' veloce del test equivalente su vnsys-test (che aveva impiegato ~3 minuti e bloccato
  temporaneamente il server, vedi sopra) - probabilmente perche' qui e' passato da Graph diretto
  (sessione delegata gia' attiva) invece che dover avviare il sottoprocesso CLI365 la prima
  volta.
- **Scenario "Teams delegato" (il primo test dell'utente, prima di questo batch) - vedi sezione
  dedicata sopra "Un 'crash' segnalato dal vivo su Teams..."** - non era un crash, isolamento
  reattivo riuscito, ma nessun avviso all'utente su un secondo popup + NetworkError client dopo
  un successo lato server. Corretto in v0.9.76.
- **Scenari 2/3/4 (SharePoint/Purview/Intune) - confermati PASS dall'utente** ("provati e
  tutto ok"), nessun dettaglio negativo riportato.
- **Bug reale segnalato dal vivo dall'utente: "Stato permessi" mostrava note di sviluppo
  interne** ("nota: Verificato dal vivo il 21/08/2026...") - fuorviante e senza senso per un
  utente finale. Corretto in `Get-M365OpsDelegatedPermissionsCheck.ps1` e
  `Get-M365OpsAppPermissionsCheck.ps1`, v0.9.79: le date/verifiche restano SOLO nei commenti di
  codice, il campo `Note` mostrato all'utente ora dice solo cio' che gli serve.
- **Report della maratona non aggiornato da un po' - segnalato dall'utente**: mi ero
  concentrato sui commit al repository (questo file + changelog), trascurando l'artifact
  "Marathon Report" pubblicato all'inizio della sessione. Aggiornato con una nuova sezione 11
  che copre l'intera fase v0.9.67→v0.9.80 (CLI365 + tenant Delegato reale). Promemoria per le
  prossime maratone: aggiornare ANCHE l'artifact a intervalli regolari, non solo questo file -
  l'utente lo controlla attivamente.

## Agente 8: test scrittura Purview/Entra avanzato (RBAC Intune, PIM, device objects)

**Agente "Test scrittura Purview/Entra avanzato"** (general-purpose, background, test dal vivo
via pwsh diretto su "vnsys-test", nessun browser) — COMPLETATO. Confermato: nessuna cmdlet di
SCRITTURA Purview esiste in questo codebase (solo letture) - non un gap, un fatto verificato
controllando l'intera cartella Public/. Nessuna cmdlet PIM/directory-role/device-object/app-
registration esiste nemmeno. L'unica area di scrittura Entra/Graph non ancora coperta era il
RBAC Intune (ruoli custom + assegnazioni).
**2 bug reali trovati e corretti, entrambi riverificati dal vivo - v0.9.80**:
- `Set-M365OpsRoleAssignment`: POST sulla rotta SBAGLIATA (tipo base astratto `roleAssignment`,
  documentata su Microsoft Learn ma rifiutata sempre dal backend reale con 400) - il tipo
  concreto usato davvero da Intune (`deviceAndAppManagementRoleAssignment`) si crea sulla
  collezione di primo livello con `@odata.type` + `roleDefinition@odata.bind`. Corretto anche
  il campo sbagliato per "chi puo' usare il ruolo" (`scopeMembers` → `members`). Stessa
  correzione di rotta propagata a `Remove-M365OpsRoleAssignment` (mai verificata prima perche'
  nessuna assegnazione era mai stata creata con successo).
- Stesso file, secondo bug: un solo gruppo in `-ScopeGroupIds` produceva `resourceScopes` come
  stringa scalare invece di array (spacchettamento di array a un elemento attraverso l'output
  di un if/else, comportamento noto della pipeline PowerShell) - corretto forzando l'array con
  `@(...)`.
Pulizia finale confermata: `ZZTEST-marathon-CustomRole`, `ZZTEST-marathon-RoleAssignment`,
`ZZTEST-marathon-RoleGroup` tutti eliminati e verificati assenti con query indipendenti. Nessun
nuovo residuo (il sito SharePoint `ZZTEST-marathon-Site` gia' noto resta l'unico residuo aperto,
non toccato da questo agente).

## Sessione 23/08/2026 (continuazione) — login Teams Delegato reso non bloccante + 3 bug reali

Richiesta esplicita dal vivo, arrivata DURANTE la maratona, dopo l'episodio v0.9.76 ("un crash
segnalato... in realta' un NetworkError dopo un successo lato server"): *"su questo ti chiedo
rendere la questione multi thread cosi che queste operazioni non blocchino / facciano crashare
tutto è possbile?"*. Discussa con l'utente prima di implementare: riscrivere l'intero server per
essere davvero multi-thread è stato **scartato deliberatamente** (rischio concreto di bug di
concorrenza su stato condiviso critico per la sicurezza delle scritture - `$pendingWrite`,
`$script:M365OpsContext`, i dizionari dei processi MCP - peggiore del problema che risolverebbe,
dato il modello "mai concorrente" su cui è costruita l'intera app). L'utente ha approvato
l'alternativa mirata proposta ("per ora lakscia stare, dedicati alla maratoma debug su ambiente
delegato pooi impolementa l'alternativa mirata") e l'ho implementata dopo aver proseguito la
maratona sul tenant Delegato.

**Architettura**: riuso del meccanismo di isolamento in processo separato gia' esistente e
collaudato (finora attivato SOLO reattivamente, dopo un conflitto .NET reale), reso disponibile
anche in modalita' start+poll non bloccante. Nuovi file: `Private/Start-M365OpsIsolatedModuleConnectAsync.ps1`
(avvia il worker e manda la richiesta "connect" senza attendere), `Private/Get-M365OpsIsolatedModuleConnectAsyncStatus.ps1`
(un solo controllo non bloccante per chiamata, pensato per il polling), `Private/Complete-M365OpsIsolatedModuleConnect.ps1`
(logica di completamento condivisa, estratta da `Connect-M365OpsIsolatedModule.ps1` per essere
riusata identica da entrambi i percorsi). Lato GUI: nuove route `/api/teams-test-async-start` e
`/api/teams-test-async-poll` in `Gui/Server.ps1`, e il pulsante Teams in `Gui/index.html` (solo
ramo Delegato - l'App-only resta sul percorso rapido esistente) ora usa uno schema start/poll con
pulsante "Annulla" dedicato, stesso principio gia' in uso per il login Graph/Exchange a codice
dispositivo. Costo accettato e comunicato in chat: un secondo popup di login sempre per Teams
Delegato, anche quando nessun conflitto .NET si sarebbe mai verificato - scambio deliberato per
un server che non si blocca mai durante l'attesa umana.

**3 bug reali trovati durante la verifica dal vivo del refactor** (nessuno visibile leggendo il
codice, tutti emersi solo testando end-to-end su "vnsys-test" - vedi anche la riga di changelog
v0.9.81 in `Guida-Configurazione.html` per il dettaglio completo):
1. `ConvertFrom-Json` su un oggetto JSON vuoto (`{}`) restituisce un `PSCustomObject` la cui
   `PSObject.Properties.Name` contiene UN elemento `$null` invece di zero - quirk PowerShell
   riprodotto in isolamento con un test minimale, non legato al tenant. Causava "Index operation
   failed; the array index evaluated to null." quando il worker non trovava nessun comando nuovo
   da proxare. Corretto filtrando i nomi vuoti/nulli in `Complete-M365OpsIsolatedModuleConnect.ps1`.
2. Causa di quel caso-limite, molto piu' seria: il worker calcolava i comandi da proxare con un
   diff prima/dopo su `Get-Command -CommandType Function, Cmdlet` SENZA `-Module` - corretto per
   Exchange (cmdlet generati dinamicamente via implicit remoting, mai pre-catalogabili) ma
   **SEMPRE a zero per Teams**: verificato dal vivo che `'Get-Team' -in (Get-Command -CommandType
   Function,Cmdlet).Name` e' gia' vero in un `pwsh -NoProfile` completamente pulito, PRIMA di
   qualunque `Import-Module` (PowerShell cataloga i nomi di un modulo staticamente dichiarato
   scansionando `$env:PSModulePath`, senza doverlo importare davvero). Senza fix, l'isolamento
   Teams "riusciva" (log di successo) ma installava ZERO proxy - ogni cmdlet Teams successivo
   sarebbe fallito silenziosamente con "term not recognized", un fallimento molto piu' subdolo
   del crash che ha permesso di scoprirlo. Corretto in `M365OpsIsolatedWorker.ps1` includendo
   anche i comandi il cui `ModuleName` corrisponde davvero al modulo appena connesso, in OR col
   diff esistente (innocuo per Exchange). Verificato dal vivo: 561 cmdlet Teams proxati
   correttamente dopo il fix, `Get-Team` via proxy restituisce le 15 righe reali del tenant.
3. Trovato SOLO testando il percorso ASINCRONO end-to-end (mai capitato sul percorso sincrono/
   reattivo esistente): dopo un login asincrono riuscito, `Get-M365OpsTeamsList` falliva con
   "Errore MCP: ...Dictionary con chiavi non-stringa non supportato per la serializzazione".
   Causa: `Connect-M365OpsTeams.ps1` salta il proprio corpo solo se `$script:M365OpsTeamsConnected`
   e' gia' vero - flag impostato SOLO dal corpo normale di quella funzione, mai dal nuovo percorso
   asincrono (che puo' rendere l'isolamento attivo senza mai passarci). Risultato: una chiamata
   successiva a `Connect-M365OpsTeams` provava a "riconnettersi" chiamando `Connect-MicrosoftTeams`
   per nome - ma quel nome e' ormai una funzione PROXY globale (installata per ogni comando nuovo
   del modulo, `Connect-MicrosoftTeams` compreso), quindi la chiamata veniva inoltrata al worker
   come un'esecuzione qualsiasi: il worker eseguiva davvero un secondo connect ridondante e
   crashava provando a serializzarne il risultato (oggetto Account/Environment/Tenant/TenantId
   con un Dictionary interno a chiavi non-stringa). Corretto impostando il flag direttamente in
   `Complete-M365OpsIsolatedModuleConnect.ps1` (il punto unico raggiunto da ENTRAMBI i percorsi),
   invece che nei soli corpi di `Connect-M365OpsTeams`/`Connect-M365OpsExchange`. Verificato dal
   vivo end-to-end: login asincrono completo su "vnsys-test", poi `Get-M365OpsTeamsList` subito
   dopo restituisce le 15 righe reali senza errori, `$script:M365OpsTeamsConnected` correttamente
   `$true`.

**Spedito in v0.9.81**, sintassi verificata su tutti i 386 file `.ps1` + tag HTML bilanciati
(`Gui/index.html` e `Guida-Configurazione.html`, tecnica Node.js gia' in uso) prima del commit.

**Scope deliberatamente limitato**: solo Teams Delegato in questo giro (il caso segnalato dal
vivo dall'utente, e il piu' proficuo da convertire). SharePoint/Purview/Intune/CLI365-delegato
**restano bloccanti** - trasparente con l'utente su questo, non un'omissione nascosta. Estenderli
con lo stesso schema resta un lavoro futuro se richiesto.

**Non ancora verificato dal vivo con un vero utente umano**: questo giro ha testato SOLO il
percorso App-only (nessun login umano necessario, tutto scriptabile). Il popup Delegato vero
(Teams Delegato, con MFA reale) resta non testabile dal mio ambiente sandboxato - stesso limite
gia' documentato per l'isolamento reattivo Delegato in generale (vedi open item in cima al file).
Da verificare quando l'utente prova di persona il nuovo pulsante "Connetti Teams" su un tenant
Delegato.

## Fuori maratona: nota sorgente estesa a OGNI interazione (v0.9.87)

Seguito diretto del v0.9.86 (sopra): segnalato dal vivo dall'utente che "dammi i fattori mfa di
X" non mostrava nessuna nota - quella domanda matcha un comando del catalogo locale
(`Gui/CommandCatalog.ps1`, `RequiresAI=$false`), percorso completamente diverso da
`Invoke-M365OpsAgentTools`. Estratta `Get-M365OpsAiProviderLabel` (Private, condivisa) e applicata
la nota a tre punti in `Gui/Server.ps1`: dispatch catalogo (con e senza IA, inclusi gli errori),
diagnosi/correzione scritture fallite, fallback dopo un errore del loop AI principale. Verificato
dal vivo MfaStatus (nessuna IA) e CompliancePatterns (IA reale). Commit `517e7f9`.

**Agente "Regression check v0.9.87"** (general-purpose, background) — AVVIATO 24/08/2026, su
richiesta esplicita dell'utente ("doipo fai girare agente esteno per debug"). Scope: SOLO il
commit `517e7f9` - in particolare se il pattern generico di append della nota funziona per TUTTE
le ~20 voci del catalogo (non solo le 2 gia' testate), eventuale collisione con
`$script:LastReportPath`/`$attachments` o con parser lato GUI, e raggiungibilita' reale di
`Get-M365OpsAiProviderLabel` da `Gui/Server.ps1`. — COMPLETATO.

**1 regressione reale trovata e corretta, verificata dal vivo - v0.9.88**: il ramo di successo del
dispatch catalogo distingue correttamente "nessuna IA usata" da "con analisi IA" in base a
`$entry.RequiresAI` - il blocco `catch` aggiunto dallo stesso commit no, diceva SEMPRE "nessuna IA
usata (fallito prima di completare)", anche per le voci `RequiresAI=$true`
(`CompliancePatterns`/`ExportCompliancePatterns`) dove l'IA e' esattamente cio' che puo' aver
fallito - contraddicendo lo scopo stesso della trasparenza appena introdotta. Riprodotto dal vivo
forzando un errore di validazione dentro `Get-M365OpsCompliancePatterns`. Corretto branchando il
`catch` sullo stesso `$entry.RequiresAI` del ramo di successo, riverificato dal vivo entrambi i
casi (AI e non-AI).

**Altre aree controllate, nessun problema trovato**: tutti i ~19 Formatter del catalogo
restituiscono sempre una stringa semplice (mai `$null`/array/hashtable), nessuna interferenza con
`$script:LastReportPath`/allegati, nessuna collisione con parser lato GUI (la chat renderizza il
testo come nodo di testo puro, nessuna interpretazione markdown/HTML), `Get-M365OpsAiProviderLabel`
confermata raggiungibile da una sessione reale. Verificate dal vivo 7 voci del catalogo oltre alle
2 gia' testate (`ListDevices`, `ExportDevices` con allegato, `GroupOverview`, piu' due casi
sintetici di fallimento) - tutte corrette.

Marathon Report (artifact) aggiornato in parallelo con una nuova sezione 12 dedicata a questo
lavoro - vedi `https://claude.ai/code/artifact/201ca6a9-4334-492c-af59-b6e5c5118be2`.

## Agente 9: comandi reali CLI Microsoft 365 mai testati oltre il login

**Agente "Test CLI Microsoft 365 comandi reali"** (general-purpose, background, sola lettura sul
tenant - nessuna scrittura in questo giro) — COMPLETATO. Setup identico al percorso reale
dell'AI: `Connect-M365Ops -TenantProfile 'vnsys-test'` (AppOnly) poi `Connect-M365OpsMcpServer
-Name 'CLI-Microsoft365'`, comandi invocati via `Invoke-M365OpsMcpServerTool` (stesso codice
della chat), mai `m365` CLI grezzo. Solo verbi di lettura (`get`/`list`/`search`), nessuna
scrittura sul tenant in questo giro.

**1 bug reale trovato e corretto, riverificato dal vivo - v0.9.82**:
`Assert-M365OpsCliMicrosoft365Installed.ps1` catturava l'output di `npm install -g
@pnp/cli-microsoft365` con `2>&1` - npm scrive avvisi non fatali su stderr (es. "npm warn
allow-scripts..." per una dipendenza, presente su ogni installazione recente del pacchetto).
Sotto `$ErrorActionPreference = 'Stop'` (impostato a livello di modulo), Windows PowerShell 5.1
promuove il PRIMO di quegli avvisi a eccezione terminante ben prima del controllo esplicito su
`$LASTEXITCODE` - un'installazione riuscita per davvero (exit 0, verificato dal vivo) veniva
segnalata come fallita. PowerShell 7 (il runtime reale della GUI) non ne soffre - resta comunque
un bug reale per chi importa il modulo a mano su 5.1, stessa classe del gap gia' noto sulla
lettura file senza `-Encoding`. Corretto con un `$ErrorActionPreference = 'Continue'` locale solo
per la chiamata npm (ripristinato in `finally`) - il controllo su `$LASTEXITCODE` resta l'unica
fonte di verita'. Riprodotto e riverificato dal vivo due volte sotto `powershell.exe` 5.1.

**Risultati dei comandi reali** (pwsh 7, "vnsys-test"): `entra user list` → 56 utenti reali;
`entra m365group list` → gruppo reale `vnsysit`; `purview auditlog list` → dati di audit
sostanziali reali (eventi quarantena phishing, etichette sensibilita', promozione admin Yammer).
Falliscono CORRETTAMENTE (non bug): `spo site list` (limite documentato, l'auth a client
secret/id non e' supportata da SharePoint per questo), `planner plan list`/`outlook event list`
(permessi Graph realmente mancanti su questa App Registration - `Calendars.Read` non concesso).
Nessuna ripetizione del blocco di ~3 minuti segnalato in passato in questo giro (test su processi
isolati, non sul vero server GUI) - il costo reale di ~2 minuti per l'installazione npm alla
primissima connessione per processo server resta pero' confermato.

**Verdetto**: CLI Microsoft 365 e' genuinamente utilizzabile end-to-end dall'AI in chat per
Entra/Purview oggi. SharePoint/Planner/Outlook via CLI365 restano limitati da vincoli reali
(piattaforma/permessi), non da bug - nessuna azione ulteriore necessaria li', sono limiti onesti
gia' comunicati come tali dagli errori reali della CLI, non fallimenti silenziosi.

## Agenti 10 e 11 (in corso, paralleli): fallback CLI365 sulle scritture Entra + Scripts\Custom

Spinnati in parallelo 23/08/2026, ~20:35, per rispettare la regola "parallelizzare dove
possibile" - entrambi in sola lettura sul codice, con eventuali test di scrittura sul tenant
"vnsys-test" (AppOnly) sempre nominati `ZZTEST-marathon-*` e ripuliti a fine test.

1. **Agente "Fallback CLI365 scritture Entra"** (general-purpose, background) - riprende l'item
   "prioritario, trovato dal vivo il 23/08/2026" nella sezione "Aree MAI toccate" sopra: valutare
   con prove reali (non teoria) se estendere il fallback letture→CLI365 (gia' attivo dal
   v0.9.68/69) anche alle scritture nel dominio Entra, confrontando un ciclo crea→elimina reale
   fatto sia via Graph diretto sia via comando CLI365 equivalente. Deciso APPOSTA di procedere
   solo se le prove mostrano che e' sicuro (una scrittura mal instradata ha conseguenze piu' serie
   di una lettura) - se trova differenze reali di normalizzazione/validazione, non deve
   implementare nulla, solo documentare perche' con le prove concrete. **COMPLETATO** - vedi la
   voce "RISOLTO" nella sezione "Aree MAI toccate" sopra per il dettaglio completo (guard
   deterministico implementato in `Invoke-M365OpsAgentTools.ps1`, non una traduzione automatica -
   spedito in v0.9.84).
2. **Agente "Stress-test Scripts\Custom"** (general-purpose, background) — COMPLETATO. Contenuto
   reale della cartella: `README.md` (convenzione: nome file = nome funzione, help a commenti
   PowerShell, tag obbligatorio `.NOTES Mode: ReadOnly|Write`, nessun input interattivo), `_TEMPLATE.ps1`
   (esempio, correttamente mai caricato), e UN solo script reale: `Get-M365OpsOneDriveSharingReport.ps1`
   (ReadOnly - elenca link di condivisione OneDrive attivi via Graph). Caricamento al boot OK,
   invocato dal vivo su 3 UPN reali di "vnsys-test": 0 righe per tutti e tre, confermato CORRETTO
   (non un fallimento silenzioso) leggendo la risposta Graph grezza - il tenant di test
   semplicemente non ha link di condivisione attivi ora. Percorso di errore testato con un UPN
   inesistente: 404 Graph reale con corpo completo, propagato pulito per il livello di triage
   dell'AI.
   **2 bug reali trovati e corretti, entrambi riverificati dal vivo - v0.9.83**:
   - `Get-M365OpsCustomScriptCatalog.ps1`: la lista di esclusione parametri comuni non includeva
     `ProgressAction` (aggiunto da PowerShell 7.4 in poi) - su questo ambiente (PS 7.6.5) il
     catalogo esposto all'AI mostrava un parametro FASULLO (`Upn, ProgressAction` invece del solo
     `Upn` reale) per ogni script - sarebbe finito nello schema dei tool `custom_script_query`/
     `propose_custom_script_write`. Corretto, verificato dal vivo che il catalogo ora mostra solo
     `Upn`.
   - `M365Ops.psm1`, loader script personalizzati: il blocco `catch` usava `$_.Name` per nominare
     lo script fallito, ma dentro un `catch` `$_` e' l'ErrorRecord (senza `Name`), non piu'
     l'oggetto file della pipeline - l'avviso non diceva MAI quale script fosse rotto ("Script
     personalizzato '' non caricato..."), inutile con piu' di uno script presente. Riprodotto dal
     vivo con un file di test dalla sintassi volutamente rotta. Corretto catturando l'oggetto file
     PRIMA del `try` - verificato dal vivo che l'avviso ora nomina correttamente lo script rotto.
   Nessun dato di test creato sul tenant (l'unico script reale e' di sola lettura, nessuna
   scrittura necessaria). Due script di test locali usati solo per esercitare i percorsi di
   validazione/errore, eliminati e pulizia verificata con una reimportazione pulita del modulo.
   **Verdetto**: la feature funziona come documentato end-to-end, modulo i due bug sopra ora
   corretti.

## Agente 12 (in corso): autoreview del blocco v0.9.81→v0.9.84

**Agente "Regression review v0.9.81-v0.9.84"** (general-purpose, background, `git diff
462213f..45166a6`) — AVVIATO 23/08/2026, ~21:50. **INTERROTTO, NON COMPLETATO**: fallito per
limite di utilizzo della sessione ("hit your session limit", reset 23:40 Europe/Rome), non per un
problema nel suo lavoro - si era fermato ancora in fase di lettura del diff, prima di produrre
qualunque modifica (verificato: `git status` pulito, nessuna modifica parziale lasciata a meta').
**Task ancora da rifare in una maratona futura**: autoreview dedicato del blocco v0.9.81→v0.9.84
(login Teams asincrono + 3 bug, fix installazione CLI365 su PS 5.1, 2 bug Scripts\Custom, guard
scritture Entra→CLI365) - `git diff 462213f..45166a6` (o l'equivalente range completo se altri
commit si aggiungono prima del prossimo giro), SOLO regressioni introdotte da questi fix
specifici, non nuovi bug indipendenti.

**RIPARTITO** 24/08/2026 subito dopo la chiusura di fase sopra (limite di sessione presumibilmente
resettato, 23:40 Europe/Rome gia' passate) - stesso identico task, retry pulito (l'agente
precedente non aveva prodotto nessuna modifica prima di fermarsi). — COMPLETATO (dettaglio piu'
sotto). Scope rivisto:
`git diff e79355f..45166a6` (il range originale `462213f..45166a6` escludeva per un dettaglio
tecnico le modifiche del commit 462213f stesso, che E' il commit v0.9.81 - ampliato al genitore
per coprire l'intero blocco descritto nel task).

**Verdetto**: nessuna vera regressione nei 4 fix del blocco - tutti riverificati dal vivo end-to-end
(login Teams asincrono: start→poll→Connected, flag corretto, 561 cmdlet, nessun crash, nessuna
riga fantasma; guard scritture Entra: confermato che non puo' mai scattare su App-only, nessun
conflitto con la preferenza proattiva CLI365 esistente; i due fix Scripts\Custom: riprodotti con
un nuovo file dalla sintassi rotta, entrambi confermati).

**1 gap reale trovato e corretto - v0.9.85**: non una regressione dei fix stessi, ma un gemello
del fix v0.9.82 mai propagato. `Public/Install-M365OpsPrerequisites.ps1` (installazione
prerequisiti "in anticipo", separata dalla connessione "al primo uso" gia' corretta in v0.9.82)
faceva la STESSA identica chiamata `npm install -g @pnp/cli-microsoft365 2>&1` senza il fix -
sotto Windows PowerShell 5.1, un'installazione riuscita per davvero (verificato dal vivo: npm
reale, "changed 207 packages", exit 0) veniva comunque segnalata fallita per lo stesso motivo gia'
diagnosticato. Corretto propagando lo stesso identico fix, riverificato dal vivo con la stessa
installazione reale. Nessun oggetto di test creato sul tenant (solo una reinstallazione npm
globale idempotente, nessun residuo).

## Chiusura di questa fase della maratona (23-24/08/2026)

Iniziata 23/08/2026 12:42, ampiamente oltre il minimo di 4 ore richiesto. In questa fase (dopo la
sezione 11 del report): login Teams Delegato reso non bloccante (3 bug reali trovati e corretti,
v0.9.81), primo test dal vivo di CLI Microsoft 365 con comandi reali - Entra/Purview confermati
funzionanti, 1 bug reale corretto sull'installazione su PowerShell 5.1 (v0.9.82), primo
stress-test di Scripts\Custom - 2 bug reali corretti (v0.9.83), chiuso l'item prioritario sul
fallback scritture Entra→CLI365 con un guard deterministico verificato dal vivo (v0.9.84).
L'unico task lasciato esplicitamente a meta' e' l'autoreview dedicato del blocco appena spedito
(agente 12 sopra) - da rifare per primo alla prossima ripresa, prima di aprire nuove aree.
Nessun nuovo residuo di test lasciato sul tenant in questa fase (tutti i cicli crea/elimina
verificati con query indipendenti). Report narrativo aggiornato in parallelo ad ogni chiusura:
`https://claude.ai/code/artifact/201ca6a9-4334-492c-af59-b6e5c5118be2`.

## Fuori maratona: nota "elaborata da IA" sempre presente in chat (v0.9.86)

Richiesta diretta dell'utente (24/08/2026), non parte del giro di audit sistematico ma un fix
mirato: durante un'analisi sui token spediti alle API IA (richiesta separata, vedi conversazione),
l'utente ha chiesto di rendere sempre visibile in chat QUALE motore IA ha risposto, non solo quali
dati sono stati consultati - prima la nota "Fonte dati: ..." compariva solo se almeno un tool era
stato chiamato, lasciando una risposta puramente conversazionale senza nessuna indicazione che
fosse comunque stata scritta dall'IA. Implementato in `Invoke-M365OpsAgentTools.ps1`: nuova
`$aiProviderLabel` (Claude Sonnet 4.5 o Azure OpenAI), applicata sui tre punti di uscita della
funzione. Verificato dal vivo entrambe le varianti su "vnsys-test". Commit `93909d2`.

**Agente "Regression check v0.9.86"** (general-purpose, background) — AVVIATO 24/08/2026, su
richiesta esplicita dell'utente ("spinna agente di debug per verificare assenza di regressioni").
Scope: SOLO il commit `93909d2` (`git diff 86339fb..93909d2`) - il pattern `+= if(){} else{}`
usato ai tre punti di uscita, lo scope di `$Provider`/`$aiProviderLabel`, eventuale interferenza
con `PendingWrite`/`Attachments` o con un parsing lato GUI del testo "Fonte dati:". — COMPLETATO.
**Nessuna regressione trovata**, nessuna modifica necessaria. Verificato: il pattern `+= if(){}
else{}` produce una stringa normale (confermato in pwsh diretto, nessuno spacchettamento array);
`$Provider` mai riassegnato in nessun punto della funzione, nessuno shadowing; nessuna
interferenza con `PendingWrite`/`Attachments` (testato dal vivo un caso con `propose_graph_write`
attivo insieme alla nota); nessun parser lato `Gui/Server.ps1`/`index.html` tratta il testo
"Fonte dati:"/"Elaborata da IA:" in modo speciale (unico altro match e' un trailer non correlato
in `Complete-M365OpsWriteResponse`). **4 scenari live verificati** (Claude+tool, Claude+nessun
tool, Azure+tool, Azure+nessun tool su "vnsys-test") - tutti corretti, etichetta giusta per
provider, nessuna duplicazione. Percorso MaxRounds-esaurito verificato solo per ispezione (stesso
pattern gia' confermato sicuro altrove, non forzato dal vivo per non sprecare round a vuoto).

## Fuori maratona: elenco strumenti reso identico su ogni round per il prompt caching

Richiesta diretta dell'utente (24/08/2026), seguito dell'indagine sui token: `graphOverlapToolNames`
(6 strumenti: list_devices, list_noncompliant_devices, get_device_compliance_reasons,
get_user_overview, get_group_overview, get_user_mfa_status) venivano esclusi SOLO dal round 0 per
forzare `graph_api_call` come primo tentativo (fix storico) - questo rendeva l'elenco tool DIVERSO
tra round 0 e round 1+, rompendo il prefisso comune richiesto dal prompt caching (sia Claude
`cache_control`, mai usato finora, sia il caching automatico di Azure). Confermato dal vivo su
"vnsys-test": cache-hit sul round 1 passato da **12,9% (baseline) a ~99%** dopo il fix. Corretto
rendendo l'elenco tool IDENTICO su ogni round, spostando la preferenza per `graph_api_call` in una
frase esplicita nel system prompt (round-invariante, non rompe mai la cache).

**Regressione controllata dal vivo, 3 scenari, nessun problema**: "panoramica utente",
"dispositivi non conformi", "dettaglio MFA" - in tutti e tre il modello ha usato esclusivamente
`graph_api_call`, mai le 6 scorciatoie escluse in precedenza. Comportamento preservato.

**Agente "Regression review token-caching fix"** (general-purpose, background) — AVVIATO
24/08/2026, per coprire scenari aggiuntivi oltre ai 3 gia' testati da me e verificare eventuali
dettagli tecnici (ordine di valutazione delle variabili nel system prompt heredoc, parita' tra
provider Claude/Azure, riferimenti residui al vecchio nome `roundOneShortcutNames`). — COMPLETATO.

**Nessuna regressione trovata**. Confermato: `$graphOverlapToolNames`/`$graphOverlapWarning`
calcolate PRIMA dell'heredoc del system prompt (ordine corretto, nessuna interpolazione vuota);
`$currentTools` calcolato una sola volta per round, consumato identicamente da entrambi i rami
provider (il fix e' uniforme nell'implementazione - solo il BENEFICIO di cache resta specifico di
Azure, dato che `cache_control` non e' mai usato per Claude in questo file, confermato con grep a
zero risultati); zero riferimenti residui al vecchio nome `roundOneShortcutNames` in tutto il
repository; il dispatch `propose_*`/`PendingWrite`/`Attachments` non e' toccato da questo diff.

**3 scenari live aggiuntivi, tutti corretti**: "panoramica del gruppo gruppo_dynamicdl" (mai
`get_group_overview`, cache-hit salito 14,5%→66,2%→90,2%→97,6% nel corso della conversazione);
"quali pc del tenant hanno problemi di compliance?" (frase terse, evita deliberatamente le parole
del catalogo - mai `list_devices`/`get_device_compliance_reasons`, cache-hit 97,9% al round 1);
"riepilogo completo su PlannerTest" (ambiguo utente/gruppo di proposito - risolto correttamente
come gruppo, incontrato un vero limite di permesso Planner e caduto correttamente su `cli_m365_*`
invece che su `get_group_overview`, cache-hit 93-98% su tutti i 6 round). In nessuno dei 6 scenari
totali (3 miei + 3 dell'agente) il modello ha mai usato una delle 6 scorciatoie escluse in
precedenza.

## Fuori maratona: nuova funzionalita' - analisi intestazioni email/NDR con IA (v0.9.90)

**Non un fix, una funzionalita' nuova**: richiesta esplicitamente dall'utente durante un caso
reale di troubleshooting (un NDR "550 5.4.1 Recipient address rejected: Access denied" da un
apparato FortiAnalyzer, inoltrato in chat da un collega dell'utente). Dopo aver diagnosticato quel
caso specifico con ricerca web (confermato: quasi sempre Directory-Based Edge Blocking sul lato
destinatario, non un problema di relay/IP come il nome del codice farebbe pensare), l'utente ha
chiesto di integrare l'equivalente del Message Header Analyzer di Microsoft
(`https://mha.azurewebsites.net`) dentro M365Ops, con un collegamento al motore IA per la
spiegazione.

**Cosa e' stato costruito**: nuovo file `Private/Get-M365OpsMessageHeaderAnalysis.ps1` (parser
locale, zero dipendenze esterne, zero chiamate di rete per il solo parsing) che riconosce
automaticamente due formati - intestazioni RFC 5322 complete (hop di consegna con ritardo
calcolato, SPF/DKIM/DMARC, rapporto antispam X-Forefront-Antispam-Report decodificato) oppure un
blocco di diagnostica NDR/message-trace di Exchange (codice SMTP/esteso scomposto, con
spiegazione mirata per i pattern piu' comuni, es. 5.4.1). Nuova tab "Intestazioni email" nel
pannello impostazioni (`Gui/index.html`), due nuove route in `Gui/Server.ps1`
(`/api/analyze-headers` per il parsing puro, `/api/analyze-headers-ai` per la spiegazione IA -
quest'ultima SOLO su click esplicito separato, mai automatica, con la stessa nota "Elaborata da
IA" del v0.9.86/87 per coerenza).

**1 bug reale trovato e corretto durante il test dal vivo** (non un caso costruito a mano - il
blocco NDR reale incollato dall'utente in questa stessa conversazione): il valore LED del blocco
NDR arriva spesso spezzato su piu' righe (l'ID di tracciamento tra parentesi quadre va a capo da
solo) - `.` non matcha mai un a-capo in .NET regex senza l'opzione Singleline, quindi l'estrazione
di SmtpCode/EnhancedCode/Text falliva sempre silenziosamente su un LED multi-riga pur avendo
catturato correttamente il testo grezzo. Corretto normalizzando spazi/a-capo in una singola
stringa prima di estrarre i codici.

**Verificato dal vivo, end-to-end, su piu' livelli**: unit test diretto del parser (formato
intestazioni: 5 hop, ritardi 0/1/0/4 secondi, identico all'output di riferimento screenshot di
Microsoft Message Header Analyzer fornito dall'utente; formato NDR: codici estratti correttamente
dopo il fix); chiamata diretta alle due nuove route HTTP sul server reale (`localhost:8745`,
riavviato per caricare il nuovo codice); **test nella GUI vera nel browser** (tab aperta, testo
incollato via `form_input`, pulsante "Analizza" cliccato, risultato HTML verificato via
`innerText` - riepilogo/hop/autenticazione/antispam tutti corretti; pulsante "Chiedi all'IA"
cliccato, risposta reale di Azure OpenAI ricevuta e verificata, diagnosi corretta e coerente con
l'analisi locale, nota "Elaborata da IA" presente). Il caso NDR reale FortiAnalyzer di questa
conversazione e' stato usato come test end-to-end: la spiegazione IA ha correttamente identificato
il Directory-Based Edge Blocking come causa piu' probabile, stessa diagnosi gia' data in chat con
ricerca web manuale - confermando che lo strumento locale ora rende quella stessa qualita' di
diagnosi disponibile senza bisogno di una ricerca esterna ogni volta.

## Seguito: pulsante combinato copia+apri MHA + 2 agenti dedicati (v0.9.91)

Su richiesta esplicita dell'utente ("fai partire gli agenti per controllare tutto"), avviati due
agenti in parallelo su v0.9.90 appena spedito:

**Agente "Regression review header analyzer feature"** — COMPLETATO. **1 bug reale trovato e
corretto**: la sezione "Dati grezzi analizzati" (aggiunta durante il lavoro in corso su questo
stesso commit, prima del completamento dell'agente) veniva calcolata ma accodata SOLO nel ramo
`Kind='Ndr'` (uscita anticipata) - il ramo `Headers`, il caso piu' comune, arrivava al `return`
finale senza mai includerla. Nessun errore, nessun crash, solo una sezione mancante in silenzio.
Confermato dal vivo (server riavviato, testato in browser: `headers-open-mha-btn` risultava
`null` dopo un'analisi di intestazioni normali) e corretto (`return html + rawSection;`),
riverificato dal vivo dopo il fix. Altre aree controllate (parser, mappatura camelCase
Server.ps1↔GUI, XSS, bilanciamento tag nei template JS, route HTTP con input malformato) - nessun
altro problema.

**Agente "Stress-test parser con formati reali"** — COMPLETATO. **2 bug reali trovati e
corretti** in `Private/Get-M365OpsMessageHeaderAnalysis.ps1`, su varianti del formato "Received:"
mai testate nella prima versione (solo M365-a-M365 e un NDR erano stati verificati prima):
1. Date con un commento di fuso orario in coda tipo Gmail (`Mon, 24 Aug 2026 01:23:39 -0700
   (PDT)`) - ne' `DateTimeOffset.Parse` ne' il cast lo accettavano, quindi `Time` restava il
   testo grezzo e `DelaySec` non veniva mai calcolato per quell'hop, in silenzio. Corretto
   rimuovendo il commento tra parentesi prima di interpretare la data.
2. Intestazioni "Received:" senza il giorno della settimana (facoltativo per RFC 5322, omesso
   da gateway come Cisco IronPort/ESA, es. `24 Aug 2026 10:00:00 +0200`) facevano fallire
   l'INTERO hop (non solo la data), buttando via anche mittente/destinatario gia' estratti
   correttamente. Corretto rendendo il giorno della settimana facoltativo nella regex.
   Generalizzato nello stesso giro il riconoscimento del mittente per due varianti reali in piu':
   consegna locale Sendmail/Postfix (`(from user@localhost)`) e hop interni Gmail senza alcun
   mittente esplicito - corretto anche un effetto collaterale del secondo fix (il testo grezzo
   finiva comunque in `From` per un hop Gmail correttamente privo di mittente).
Verificato con 12+ casi costruiti (Postfix/Sendmail/IronPort/Gmail/gateway di terze parti in
stile Mimecast/Proofpoint/Barracuda, intestazioni senza `Received:`, NDR con sotto-campi
mancanti, catena di 25 hop) piu' i due casi gia' verificati in v0.9.90 (nessuna regressione).

**Pulsante combinato copia+apri**, richiesta diretta dell'utente: verificato PRIMA di costruire
che `mha.azurewebsites.net` non supporta (nessuna documentazione/evidenza trovata) la
pre-compilazione via URL/query string - un link "auto-fill" sarebbe stato disonesto (aprirebbe il
tool vuoto). Implementato invece un pulsante unico che copia i dati grezzi negli appunti E apre il
tool in un click solo (nessun tasto Copia separato, come richiesto esplicitamente), con un
messaggio di stato onesto in caso l'API Clipboard fallisca (richiede un contesto sicuro + focus
del documento - verificato dal vivo che il percorso di fallback funziona correttamente).

Tutti e 3 i fix riverificati dal vivo end-to-end, incluso un test completo nella GUI reale nel
browser dopo ogni correzione. Spedito in v0.9.91.

## Seguito: conteggio token nella nota "Elaborata da IA" (v0.9.92)

Richiesta esplicita dell'utente, con richiesta di verifica preventiva su eventuali rallentamenti:
il conteggio token (spediti/ricevuti/dalla cache) arriva GRATIS nello stesso campo "usage" gia'
presente in ogni risposta HTTP di Claude/Azure OpenAI - confermato leggendo la struttura reale
della risposta prima di implementare, zero chiamate aggiuntive, zero latenza in piu'.

Aggiunto un parametro opzionale `-ReturnUsage` a `Invoke-M365OpsAgent` (Public) - default `$false`,
comportamento esistente delle altre ~5 funzioni chiamanti (`Invoke-M365OpsErrorTriage`,
`Get-M365OpsCompliancePatterns`, ecc.) rimasto identico, verificato dal vivo (`CompliancePatterns`
del catalogo continua a restituire una stringa semplice come prima). Usato per ora solo in
`/api/analyze-headers-ai`: nota finale diventa "Elaborata da IA: Y (N token inviati, M ricevuti[,
di cui K dalla cache])". Verificato dal vivo con una chiamata reale (1095 inviati, 631 ricevuti).
Spedito in v0.9.92. Scope deliberatamente limitato alla sola route richiesta dall'utente
("in questo caso dell'analisi") - estendere la nota token alle altre interazioni IA (loop
tool-calling generale, triage errori, ecc.) resta un lavoro futuro se richiesto.

**Agente "Regression review token-count feature"** (general-purpose, background) — AVVIATO
25/08/2026, su richiesta esplicita dell'utente ("dopo implementazione spinna agente per
verifica bug"). Scope: SOLO il commit `ef3abd1` - in particolare che nessuno degli altri
chiamanti di `Invoke-M365OpsAgent` sia stato toccato/rotto dal nuovo parametro `-ReturnUsage`
(default `$false`), che i nomi dei campi `usage.*` letti dalle due API siano corretti, e la
null-safety del nuovo codice in caso di un campo `usage` mancante/diverso dall'atteso. —
COMPLETATO. **Nessuna regressione trovata**, nessuna modifica necessaria.

Inventario completo dei chiamanti (10, non ~5 come stimato nel commit): confermato che NESSUNO
passa `-ReturnUsage` e tutti trattano il risultato come stringa semplice esattamente come prima
(regex, `ConvertFrom-Json`, `.Trim()`, interpolazione diretta). Nomi dei campi Azure OpenAI
(`usage.prompt_tokens`/`completion_tokens`/`prompt_tokens_details.cached_tokens`) confermati
identici a quelli gia' letti altrove nel progetto (v0.9.89, caching). Campi Claude
(`usage.input_tokens`/`output_tokens`/`cache_read_input_tokens`) verificati dal vivo con valori
reali non nulli. Null-safety confermata (`$null -gt 0` = `False`, interpolazione di `$null`
degrada a stringa vuota, mai un'eccezione). **Verificato dal vivo su entrambi i provider**
(Claude e Azure OpenAI, con e senza `-ReturnUsage`) e **end-to-end sul server reale** (nota
corretta "506 token inviati, 488 ricevuti", clausola cache correttamente omessa quando 0).
Confermato anche che `cache_read_input_tokens` per Claude sara' sempre 0 in pratica (nessun
`cache_control` mai inviato in questo progetto, solo un commento storico) - gestito
correttamente dalla guardia `-gt 0`.

## Seguito: risposte lunghe non piu' tagliate dopo reload + toggle "Mostra tutto" (v0.9.93)

Segnalato dal vivo dall'utente con uno screenshot: un'analisi lunga (pattern di non conformita'
dispositivi) appariva tagliata a meta' frase con "[...troncato]" - non nella risposta live, ma
dopo un ricaricamento della pagina.

**Causa reale trovata**: `Add-M365OpsChatHistoryTurn.ps1` troncava a 3000 caratteri PRIMA di
salvare su disco - lo stesso file serve pero' due scopi opposti: ridisegnare la chat per l'utente
(dove serve il testo COMPLETO) e fornire contesto all'IA nei turni successivi (dove un limite di
lunghezza e' corretto per non gonfiare costo/tempo di risposta). Lo stesso taglio applicato a
entrambi cancellava per sempre la coda del testo anche per la visualizzazione umana.

**Corretto separando i due scopi** (richiesto esplicitamente: "implementa una cosa che non rompa
quanto gia' fatto finora"): `Add-M365OpsChatHistoryTurn.ps1` ora salva SEMPRE il testo completo
(solo la redazione password resta); il limite di 3000 caratteri si sposta SOLO al punto in cui lo
storico diventa contesto IA (`Invoke-M365OpsAgentTools.ps1`, nuova `$maxHistoryCharsPerTurn`).
Aggiunto anche, su richiesta esplicita, un pulsante "Mostra tutto"/"Mostra meno" lato GUI per i
messaggi oltre 1500 caratteri - un limite puramente di leggibilita', mai di perdita di contenuto.

**Verificato dal vivo end-to-end su "vnsys-test"**: risposta di 5091 caratteri salvata per intero
(nessun `[...troncato]`, confermato via `GET /api/chat/history`); un turno successivo che usa
quello storico come contesto continua a funzionare correttamente (riassunto coerente, nessun
errore); pulsante "Mostra tutto"/"Mostra meno" testato nel browser reale, espansione e
ricompressione funzionanti in entrambe le direzioni su piu' messaggi.

Spedito in v0.9.93. Su richiesta esplicita dell'utente ("a valle rifai tutte le verifiche con gli
agent di debug"), agenti di regressione da avviare subito dopo questa dichiarazione - vedi sotto.

**Agente "Regression review chat-history truncation fix"** (general-purpose, background) —
AVVIATO 25/08/2026. Scope: SOLO il commit `a63ab9d` - altri punti nel codice che potrebbero
dipendere implicitamente dal vecchio taglio a 3000 caratteri, correttezza del nuovo taglio
spostato in `Invoke-M365OpsAgentTools.ps1` (casi limite: testo `$null`/vuoto, taglio esatto al
confine, possibile corruzione di caratteri Unicode multi-byte con `.Substring()`), correttezza
del toggle GUI "Mostra tutto" (soglia 1500 caratteri, interazione con allegati/pulsanti di
conferma, funzionamento sia su messaggi live sia su storico ricaricato). — COMPLETATO.

**1 bug reale trovato e corretto, in due punti gemelli - v0.9.94**: sia `.Substring()` lato
server (PowerShell, `Invoke-M365OpsAgentTools.ps1`) sia `.slice()` lato client (JavaScript,
`Gui/index.html`) tagliano una stringa per unita' di codice UTF-16, non per caratteri veri - un
taglio che cade esattamente a meta' di una coppia surrogata (es. un'emoji) lascia un surrogato
alto orfano. Riprodotto dal vivo lato server: la stringa passa `ConvertTo-Json` senza errori, ma
`Invoke-RestMethod` (la chiamata HTTP reale verso l'IA) converte il surrogato orfano in un
carattere di replacement (U+FFFD) in modo silenzioso - contesto IA corrotto senza nessun errore
visibile. Lato client stesso problema ma solo estetico (il testo completo resta comunque
raggiungibile espandendo). Corretto in entrambi i punti arretrando il taglio di una posizione
quando cade su un surrogato alto.

**Altre aree controllate, nessun problema trovato**: grep dell'intero repository per
`Get-M365OpsChatHistory`/`ChatHistory-` (10 file) - nessun altro punto dipendeva implicitamente
dal vecchio taglio; `$maxPairs = 8` confermato intatto; testo `$null`/vuoto e taglio esatto al
confine dei 3000 caratteri gestiti correttamente; toggle GUI funzionante identico su messaggi live
e su storico ricaricato. **Verificato dal vivo end-to-end su "vnsys-test"**: risposta di 5270
caratteri salvata per intero, turno successivo funzionante, toggle testato nel browser reale in
entrambe le direzioni dopo il fix. Nota di trasparenza: il test dal vivo ha aggiunto 2 turni di
chat innocui alla cronologia reale di "vnsys-test" (lasciati apposta, ripulirli avrebbe rischiato
di cancellare cronologia vera dell'utente nello stesso file).

## Seguito: 3 correzioni dal vivo sull'analizzatore intestazioni + conteggio token esteso alla chat generale (v0.9.95)

Tre segnalazioni dal vivo dell'utente dopo aver provato la funzionalita' spedita in v0.9.90-92 nel
proprio ambiente (non nel server di test sandboxato di questa sessione).

**1) "cmq ho incollaltpo oral 'header mica miha dato link verso analyzer dimsft . inoltree dice
Risposta generata da IA (Azure OpenAI) senza consultare dati del tenant ma m,ica mi ha detto il
numero dei token"** — l'utente aveva incollato delle intestazioni nella CHAT GENERALE, non nel
pannello dedicato (che a quel tempo viveva dentro "⚙ Impostazioni tenant" → tab "Intestazioni
email", poco scopribile). La chat generale non ha mai avuto ne' il link a Microsoft Message
Header Analyzer ne' la tabella hop - solo l'IA generica che risponde a un blocco di testo che non
sa scomporre. Fonte di confusione reale, non un bug del parser.

**2) "e cmq porco dio il conteggio token ti ho gia dettodeve stare nella risposta chat i basso
nella sezione dove cita le fonti"** — correzione esplicita di uno scoping deliberatamente troppo
stretto: il conteggio token (v0.9.92) era stato implementato SOLO per `/api/analyze-headers-ai`,
documentando a quel tempo "scope deliberatamente limitato alla sola route richiesta
dall'utente". L'utente intendeva invece "a partire da questo caso", non "solo questo caso" -
lezione per il futuro: per una richiesta di trasparenza sui costi ampiamente utile (non legata a
un dettaglio tecnico specifico di una sola route), preferire lo scope PIU' ampio per default.

**3) "Una volta aggiornata: ... nn va un cazzo bene.-.. altoglielo da li, la limite metti u tab
intesaaioni email vicino ai tasti in alto dove c' upload"** — correzione esplicita sul
posizionamento GUI: il pannello era stato messo dentro le Impostazioni (una tab tra tante) senza
chiedere, l'utente lo voleva invece come pulsante di primo livello sempre visibile nella barra
strumenti, accanto a Upload - lezione per il futuro: per una funzionalita' pensata per l'uso
estemporaneo/reattivo (non di configurazione), non dare per scontato che vada dentro una struttura
esistente di tab/impostazioni; default alla posizione piu' accessibile o chiedere prima.

**Implementato**:
- `Gui/index.html`: pannello analizzatore intestazioni spostato da `#settings-panel` (tab
  "headers") a un nuovo pannello di primo livello `#headers-panel`, sibling di `#upload-panel`,
  con pulsante dedicato `#headers-toggle-btn` ("📧 Intestazioni email") nella barra strumenti
  principale accanto a Upload - stesso pattern toggle/`.open`/`.active` gia' in uso per il
  pannello di caricamento file. Nessuna funzionalita' esistente toccata nello spostamento
  (`headers-input`, `headers-analyze-btn`, `headers-clear-btn`, `headers-ai-btn`,
  `headers-open-mha-btn`, rendering hop/auth/antispam) - solo posizione DOM e CSS.
- `Gui/CommandCatalog.ps1`: nuova voce `PastedEmailHeadersRedirect` (controllata PER PRIMA
  nell'array), stessa euristica di autorilevamento del parser (`Received:\s*from`,
  `RecipientStatus\s*:`, `\{LED=`) - se un utente incolla intestazioni/NDR nella chat generica,
  reindirizza al pulsante dedicato invece di sprecare una chiamata IA generica inadeguata.
  `RequiresAI = $false`, gestito interamente in locale.
- `Public/Invoke-M365OpsAgentTools.ps1`: nuovi accumulatori `$totalInputTokens`/
  `$totalOutputTokens`/`$totalCachedTokens` (dichiarati dopo `$aiProviderLabel`, sommati round per
  round subito dopo ogni chiamata riuscita sia nel ramo Azure sia nel ramo Claude, PRIMA del
  controllo di uscita dal round) - una singola risposta puo' attraversare piu' round (un round per
  ogni chiamata a uno strumento), la nota finale deve riflettere il costo REALE dell'intera
  risposta, non solo dell'ultimo round. Le 3 coppie di note finali (Azure con/senza dati, Claude
  con/senza dati, fallback MaxRounds esaurito) ora includono `$tokenNote` con la stessa formula
  gia' collaudata in v0.9.92 ("N token inviati, M ricevuti[, di cui K dalla cache]").

**Verificato dal vivo (server di test sandboxato, restart applicato)**:
- Sintassi: `Invoke-M365OpsAgentTools.ps1` (singolo file) e l'intero repository (387 file `.ps1`)
  puliti via `[System.Management.Automation.Language.Parser]::ParseFile`, 0 errori.
  `Gui/index.html`: bilanciamento tag invariato (div 114/114, button 53/53, span 37/37) e i 2
  blocchi `<script>` inline sintatticamente validi (`new Function()`).
- Conteggio token, caso senza strumenti ("ciao, come stai?"): nota mostra "31254 token inviati, 21
  ricevuti, di cui 3328 dalla cache" - confrontato riga per riga col log server
  (`Azure OpenAI cache: 3328/31254 token dalla cache`), coincide esattamente in un solo round.
- Conteggio token, caso multi-round ("quanti utenti ci sono nel tenant?"): 3 round reali nel log
  server (prompt tokens 30514 + 30738 + 32675 = 93927; cache 23808 + 29952 + 29952 = 83712) - la
  nota finale riporta "93927 token inviati ... di cui 83712 dalla cache", la SOMMA esatta dei 3
  round, non l'ultimo soltanto. Verifica matematica indipendente dal codice (confronto diretto coi
  log), non solo lettura del sorgente.
- Pannello riposizionato: pulsante toolbar presente e funzionante (apre/chiude `#headers-panel`,
  classe `.active` sincronizzata), vecchia tab "Intestazioni email" nelle Impostazioni confermata
  rimossa. Flusso Analizza testato con un'intestazione realistica (5 header, un varco temporale
  multi-hop) - riepilogo, tabella hop, badge SPF/DKIM/DMARC, pulsante copia+apri MHA tutti presenti
  e renderizzati correttamente dopo il trasloco DOM. Flusso "Chiedi all'IA" testato di seguito -
  nota con conteggio token presente nel risultato.
- Redirect: testato positivo (blocco intestazioni incollato in chat generale → messaggio di
  reindirizzamento, `"Fonte: comando locale 'PastedEmailHeadersRedirect', nessuna IA usata."`,
  zero chiamate IA) e negativo (domanda normale che nomina "email" e un mittente → risposta IA
  regolare con `graph_api_call`, nessun falso positivo).

Spedito in v0.9.95. Su richiesta esplicita dell'utente ("dopo che fai tuytto spinna lgli angernti
debug spero sia la volta definitiva"), agente/i di regressione da avviare subito dopo questa
dichiarazione - vedi sotto.

**Agente "Regression review v0.9.95 (panel relocation + redirect + token totals)"**
(general-purpose, background) — AVVIATO 25/08/2026. Scope: SOLO le modifiche di questo commit -
(a) `Gui/index.html`: qualunque riferimento residuo al vecchio ID/percorso del pannello dentro le
Impostazioni, comportamento del pannello su schermo piccolo/resize, interazione con altri pannelli
toolbar (upload) aperti contemporaneamente; (b) `Gui/CommandCatalog.ps1`: rischio di falsi positivi
della voce `PastedEmailHeadersRedirect` su messaggi legittimi che menzionano "received"/parole
simili in italiano o in un contesto non tecnico, corretta priorita' rispetto alle altre voci del
catalogo su un messaggio che matcha piu' trigger; (c) `Invoke-M365OpsAgentTools.ps1`: correttezza
dell'accumulo token su un numero di round diverso da quelli gia' testati a mano (1 e 3), gestione
`$null`/campi mancanti nella risposta usage, nessuna regressione alla nota "Fonte dati"/etichetta
motore IA gia' verificata nelle maratone precedenti (v0.9.86/87/88). — COMPLETATO, 1 bug reale
trovato e corretto, vedi sotto.

## Seguito: agente di regression review v0.9.95 — 1 bug reale trovato e corretto (v0.9.96)

**Trovato e corretto**: falso positivo nel trigger della nuova voce `PastedEmailHeadersRedirect`
(punto (b) sopra). `received:\s*from\s` non era ancorato a inizio riga - qualunque frase (anche
del tutto legittima) che contenesse quella sottostringa a meta' testo faceva scattare il redirect,
sottraendo la domanda all'IA generica senza che l'utente capisse perche'. Riprodotto dal vivo con
un messaggio di lavoro plausibile: `"Your payment has been received: from now on please send
invoices to billing@contoso.com"` veniva reindirizzato al pannello intestazioni invece di ricevere
la risposta AI normale (una traduzione/spiegazione del testo). Una vera intestazione `Received:`
e' invece sempre la prima cosa sulla propria riga nel testo grezzo incollato (mai a meta' di
un'altra frase) - corretto ancorando il trigger a inizio riga: `(?m)^\s*received:\s*from\s`
(spazi di indentazione opzionali per le righe di continuazione RFC 5322). Verificato dal vivo
tramite chiamate dirette a `/api/chat` DOPO il fix: la stessa frase inglese ora riceve la risposta
AI corretta (nessun redirect), mentre un vero blocco intestazioni multi-riga e un vero blocco NDR
(`RecipientStatus:`) continuano a scatenare il redirect come previsto - confermato anche nella
cronologia chat persistita su disco, con l'occorrenza pre-fix (redirect errato, 01:48) e quella
post-fix (risposta corretta, 01:51) sullo stesso identico messaggio in sequenza, uno dopo l'altro.

**Altre aree del punto (b), nessun problema oltre al bug sopra**: `recipientstatus\s*:` e `\{led=`
non hanno lo stesso rischio (sottostringhe troppo specifiche per comparire in una frase normale,
verificato con piu' messaggi avversariali in italiano e inglese); nessuna voce del catalogo ha un
trigger che l'ordinamento PRIMO di `PastedEmailHeadersRedirect` avrebbe rubato in modo scorretto
(le altre ~19 voci hanno trigger completamente disgiunti da "received:"/"recipientstatus"/"{led=");
la voce non ha `DeferWords` ma il ciclo di dispatch in `Gui/Server.ps1` gestisce correttamente la
loro assenza (`if ($entry.DeferWords)`), nessun errore.

**Punto (a), nessun problema trovato**: nessun riferimento residuo a `tab-headers`/vecchia
posizione in nessuna parte di `Gui/index.html`; `#headers-panel` e `#upload-panel` possono restare
aperti insieme senza rompersi (si impilano in verticale nel normale flusso di layout, zero
sovrapposizione, le classi `.active` dei due pulsanti restano indipendenti) - verificato via DOM
sia a 1280px sia a 375px (nessun overflow orizzontale a viewport stretto). Tutte le funzionalita'
pre-esistenti del pannello (Analizza, Pulisci, pulsante IA, pulsante combinato copia+apri MHA)
riverificate funzionanti dopo il trasloco nel DOM.

**Punto (c), nessun problema trovato**: `$totalInputTokens += $response.usage.input_tokens` e
affini restano sicuri anche con `$response.usage` assente/`$null` (l'accesso a proprieta' su
`$null` in PowerShell restituisce `$null`, sommato come zero, nessuna eccezione - verificato con
un test isolato sia su Windows PowerShell 5.1 sia su PowerShell 7). L'accumulo su un numero di
round diverso da quelli gia' testati (1 e 3) riverificato dal vivo su una NUOVA domanda a 3 round
("quanti utenti ci sono nel tenant?", round diversi da quelli del v0.9.95): log per-round
25401+25624+27561=78586 token in ingresso e 0+24832+24832=49664 dalla cache, entrambi coincidenti
ESATTAMENTE con quanto mostrato nella nota finale in chat - non l'ultimo round soltanto, prova
matematica indipendente dal codice. Formati "Fonte dati: X. Elaborata da IA: Y (...)." e "Risposta
generata da IA (Y, ...) senza consultare dati del tenant." confermati invariati nella struttura,
solo con il conteggio token aggiunto in coda come atteso dal v0.9.95.

**Nota fuori ambito, non corretta in questo giro** (pre-esistente da v0.9.90, non introdotta da
v0.9.95): durante il test e' stata osservata una chiamata a `/api/analyze-headers-ai` rimasta
bloccata oltre 3 minuti senza mai rispondere - e poiche' il listener HTTP del server e' sincrono a
thread singolo, quella singola chiamata bloccata ha reso l'INTERO server (comprese richieste
completamente scollegate, es. `/api/status`) irraggiungibile finche' il processo non e' stato
terminato e riavviato manualmente. Non riprodotto in modo sistematico (potrebbe essere un blocco
temporaneo lato rete/provider IA in questo ambiente sandbox, non necessariamente nell'ambiente
reale dell'utente), ma il rischio architetturale e' reale e indipendente dall'ambiente: qualunque
chiamata IA senza timeout esplicito puo' bloccare l'intero server per tutti gli utenti finche' non
risponde o non viene riavviato a mano. Segnalato per un giro dedicato separato (servirebbe un
timeout esplicito su `Invoke-RestMethod` verso i provider IA, con gestione dell'errore risultante),
non affrontato qui per restare nell'ambito della sola review del v0.9.95.

Fix verificato dal vivo, sintassi controllata (`ParseFile` nativo, 0 errori - un primo tentativo
di verifica via strumento Bash aveva dato falsi errori per un problema di codifica emoji nella
pipe di redirezione, non del file reale, confermato riparsando lo stesso identico file con
PowerShell nativo), versione bump a 0.9.96, changelog aggiunto, PDF rigenerato. Spedito in v0.9.96.

## Seguito: timeout esplicito su tutte le chiamate IA - un blocco a monte non ferma piu' l'intero server (v0.9.97)

Rischio architetturale segnalato (non corretto, fuori ambito) dall'agente di regression-review del
v0.9.96 - vedi sezione sopra. Su richiesta esplicita dell'utente di affrontarlo subito
("correggi certo") appena riportato il risultato dell'agente.

**Causa reale confermata leggendo il codice**: `Gui/Server.ps1` usa un `System.Net.HttpListener`
con un ciclo `while ($listener.IsListening) { $context = $listener.GetContext(); ... }` -
sincrono, a thread singolo, una richiesta HTTP alla volta (righe ~1424/1455-1456). Nessuna delle 6
chiamate `Invoke-RestMethod` verso le API IA (`Invoke-M365OpsAgent.ps1`: 1 Claude + 2 tentativi
Azure con retry `max_completion_tokens`; `Invoke-M365OpsAgentTools.ps1`: stessa coppia Azure + 1
Claude) specificava `-TimeoutSec` - senza, `Invoke-RestMethod` non applica nessun limite proprio
(attesa indefinita di default), quindi una chiamata rimasta appesa a monte blocca l'INTERO server
per chiunque altro, non solo per chi ha fatto quella domanda - esattamente il comportamento
riprodotto dal vivo dall'agente precedente (blocco di 3+ minuti su `/api/analyze-headers-ai`,
server irraggiungibile fino al riavvio manuale).

**Scelta architetturale deliberata, coerente con un precedente gia' in questo stesso progetto**:
riscrivere l'HttpListener per essere davvero multi-thread e' stato scartato di proposito, per lo
STESSO motivo gia' documentato per il login Teams asincrono (v0.9.81, sezione storica sopra): il
rischio concreto di bug di concorrenza su stato condiviso critico per la sicurezza delle scritture
(`$pendingWrite`, `$script:M365OpsContext`, i dizionari dei processi MCP - nessuno di questi e'
thread-safe) sarebbe peggiore del problema che risolverebbe. Un timeout esplicito sulle chiamate IA
e' la correzione MIRATA: non elimina il blocco (il server resta a thread singolo), ma lo rende
LIMITATO E PREVEDIBILE (max 120s) invece che potenzialmente indefinito.

**Corretto**: aggiunto `-TimeoutSec 120` a tutte e 6 le chiamate `Invoke-RestMethod` verso
Claude/Azure OpenAI, nei due file. 120s scelto perche' abbondante per una singola risposta anche su
un modello reasoning con contesto ampio - ogni round del ciclo tool-calling in
`Invoke-M365OpsAgentTools.ps1` ha il proprio budget separato, non condiviso con gli altri round
della stessa conversazione, quindi il limite per round non riduce la lunghezza massima di una
conversazione multi-round, solo il tempo massimo di attesa per UNA chiamata HTTP.

**Verificato dal vivo**:
- Meccanismo di timeout confermato ISOLATAMENTE prima di fidarsi che funzionasse nel contesto reale:
  `Invoke-RestMethod -Uri "https://httpbin.org/delay/5" -TimeoutSec 2 -ErrorAction Stop` lancia
  `System.Threading.Tasks.TaskCanceledException` ("The request was canceled due to the configured
  HttpClient.Timeout of 2 seconds elapsing"), catturabile da un normale `try/catch` - stesso
  identico pattern gia' presente attorno a tutte e 6 le chiamate reali (nessuna gestione nuova
  necessaria: il timeout ricade nei blocchi catch gia' esistenti, che a loro volta o ritentano con
  `max_completion_tokens`, o rilanciano un errore chiaro che `Gui/Server.ps1` intercetta gia' per
  ripiegare su `Invoke-M365OpsAgent` senza strumenti e infine su un messaggio d'errore pulito, o
  (per la route `/api/analyze-headers-ai`) ricade nel suo proprio `try/catch` che restituisce gia'
  un JSON di errore).
- Sintassi: entrambi i file puliti (`ParseFile`), poi l'intero repository (387 file `.ps1`), 0
  errori.
- Comportamento normale invariato: dopo restart del server di test, una domanda senza strumenti
  ("ciao, come stai?") continua a funzionare identica a prima (risposta corretta, nota "Elaborata
  da IA" con conteggio token invariata) - il timeout di 120s non ha alcun impatto su chiamate che
  rispondono in pochi secondi, come sempre osservato in questa sessione.

Spedito in v0.9.97 (versione bump, changelog `docs/Guida-Configurazione.html`, PDF rigenerato,
387 file verificati sintatticamente puliti). Nessun agente di regressione dedicato per questo giro
- fix chirurgico di 6 righe (una keyword aggiunta a 6 chiamate gia' esistenti), stesso pattern di
`-TimeoutSec` gia' in uso altrove nel progetto (`Invoke-M365OpsLookupMsDocs.ps1`,
`Invoke-M365OpsMcpRequest.ps1`, `Launch-M365Ops.ps1`), rischio di regressione minimo e verificato
direttamente. Se l'utente vuole comunque un ulteriore giro di verifica su tutta la maratona
(richiesto in precedenza con "spero sia la volta definitiva"), va dichiarato e avviato su richiesta
esplicita.

## Nuova funzionalita': editor "Infrastruttura tenant" - diagramma on-prem/ibrido/multi-cloud, leggibile dall'IA (v0.9.98)

Richiesta esplicita dell'utente, dopo una discussione esplorativa su possibili nuove feature
(brainstorm partito dall'analizzatore intestazioni, poi allargato su richiesta esplicita
dell'utente stesso - "nuove proposte anche oltre questa cosa dell'header, non focalizzarti solo
su quello"): una sezione GUI a parte, raggiungibile con un pulsante, per disegnare
l'infrastruttura del proprio tenant (nomi macchina, ruoli, IP, domain controller, Entra Connect,
ecc.) con una visualizzazione grafica che entri anche nella Knowledge Base fruibile dall'IA.
Portata poi esplicitamente estesa dall'utente OLTRE l'ibrido, a meta' implementazione: "il
disegno deve riguardare anche solo architetture solo online, magari multi-cloud. non fermarti
solo all'ibrido. mettici dentro tutto" - il set di tipi di nodo e' stato ampliato di conseguenza
DURANTE la costruzione (non dopo), da un elenco iniziale di 9 tipi orientati al solo
hybrid-M365 a 17 tipi che coprono anche reti virtuali/VPC, gateway, load balancer, container/
Kubernetes, database, storage, e un nodo esplicito "Cloud provider (account/subscription)" per
rappresentare i confini di sottoscrizione/account AWS/Azure/GCP in un diagramma multi-cloud.

**Decisione di design chiave, prima di scrivere codice**: diagramma STRUTTURATO (nodi tipizzati
con proprieta', collegamenti etichettati - dati JSON, non un disegno a mano libera) invece di una
lavagna a tratto libero. Motivo: un disegno a tratto libero sarebbe piu' naturale da usare ma
richiederebbe interpretazione a immagine (OCR/vision) per essere letto dall'IA - inaffidabile su
un diagramma tecnico con etichette/IP. Un diagramma strutturato resta comunque un disegno vero
(reso su SVG, trascinabile, collegabile visivamente) ma sotto e' dato interrogabile per davvero,
non un'immagine da indovinare.

**Architettura scelta - riuso deliberato del pattern gia' collaudato per la Knowledge Base**
(v0.9.86 e successivi: catalogo leggero SEMPRE nel prompt di sistema, testo completo on-demand
via `kb_query`) invece di inventare un meccanismo parallelo:
- Storage dedicato, NON dentro la Knowledge Base esistente: `Config\InfraDiagram-<tenant>.json`
  (nuovo `Public\Get-M365OpsInfraDiagram.ps1`/`Set-M365OpsInfraDiagram.ps1`, stesso schema di
  isolamento per-tenant di `Get-M365OpsChatHistory`). Deliberatamente SEPARATO dai documenti KB
  caricati dall'utente (`KnowledgeBase-<tenant>.json`) invece di rappresentare il diagramma come
  un "documento KB" travestito: quella lista e' gia' renderizzata in GUI con un pulsante Rimuovi
  per ogni voce (tab Documentazione, `#kb-doc-list`) - mescolarci il diagramma lo avrebbe reso
  eliminabile per errore insieme ai documenti caricati, e visivamente confuso in una lista pensata
  per file veri. Zero righe toccate in quel percorso gia' collaudato: rischio di regressione nullo
  sulla Knowledge Base esistente.
- Stesso principio "riassunto sempre, dettaglio on-demand" replicato pero' con la propria coppia
  simmetrica: un blocco nel prompt di sistema di `Invoke-M365OpsAgentTools.ps1` (SOLO se il
  diagramma ha almeno un nodo - silenzioso altrimenti, nessun costo su un tenant senza diagramma)
  + nuovo tool `get_tenant_infrastructure` (zero parametri, stesso isolamento per-tenant
  strutturale di `kb_query` - lo schema del tool non espone nemmeno un parametro tenant, quindi
  non e' possibile per costruzione chiedere l'infrastruttura di un tenant diverso da quello
  attivo). Nuovo `Private\Get-M365OpsInfraDiagramNarrative.ps1` trasforma nodi/collegamenti in
  entrambi i testi (riassunto breve + dettaglio completo).
- **Bug reale trovato durante il test dal vivo, corretto nello stesso giro**: la nota "Fonte dati"
  mostrata in chat etichettava sia `kb_query` sia il nuovo `get_tenant_infrastructure` come
  "moduli PowerShell interni di M365Ops" (il caso di default di `Get-M365OpsToolSourceLabel.ps1`,
  Private) - fuorviante per un dato dichiarato dall'operatore e mai verificato contro
  l'infrastruttura reale, ben diverso da una chiamata Graph/EXO vera. Corretto aggiungendo due
  case dedicati alla stessa funzione (regex switch gia' esistente) - `kb_query` -> "Knowledge
  Base (documentazione caricata dall'operatore)", `get_tenant_infrastructure` -> "diagramma
  infrastruttura (disegnato dall'operatore, non verificato dal vivo)". Riverificato dal vivo
  dopo il fix: la nota finale ora dice correttamente "_Fonte dati: diagramma infrastruttura
  (disegnato dall'operatore, non verificato dal vivo)._".

**GUI - editor SVG scritto a mano, zero librerie esterne** (coerente col resto dell'app):
`#infra-panel`, pulsante toolbar "🗺️ Infrastruttura" accanto a Upload/Intestazioni email (stesso
pattern toggle gia' consolidato, imparato dalla correzione di posizionamento del v0.9.95 - questa
volta il pulsante e' stato messo SUBITO nella toolbar, non nascosto nelle Impostazioni). Nodi
trascinabili (drag), collegamenti creati trascinando dal pallino sul bordo di un nodo verso un
altro, pannello proprieta' che cambia campi in base a cosa e' selezionato (nodo vs collegamento).

**Scelta tecnica non ovvia, documentata in un commento esteso nel codice**: lo stato di
trascinamento/collegamento vive in variabili JS globali, MAI in un pointer-capture legato a un
elemento SVG specifico. Motivo: ogni `renderInfraCanvas()` rigenera l'intero contenuto del
canvas via `innerHTML` (per semplicita' - un solo percorso di rendering, niente sincronizzazione
manuale DOM/modello) - un listener o una `setPointerCapture` legati al vecchio elemento
smetterebbero di ricevere eventi a meta' gesto nell'istante in cui quell'elemento viene sostituito
durante un re-render intermedio. I listener `pointermove`/`pointerup` sono quindi sul `document`,
attaccati UNA sola volta all'avvio, mai dentro la funzione di render - `pointerdown` invece resta
per-elemento e viene riattaccato ad ogni render (sempre sicuro: un pointerdown parte sempre su
qualunque elemento esiste in quel momento, non deve sopravvivere a un re-render).

**Validazione lato server, non stretta** (`Set-M365OpsInfraDiagram.ps1`): tetto di 500 nodi/1000
collegamenti (protezione contro un payload anomalo che gonfierebbe senza controllo il testo
passato poi all'IA ad ogni domanda, non contro contenuti malevoli - editor pensato per un singolo
operatore che disegna la propria infrastruttura, non input non fidato da un modulo esterno), scarto
silenzioso di collegamenti verso nodi rimossi (caso normale quando si elimina un nodo con un
collegamento ancora attivo, gia' filtrato lato client ma difeso una seconda volta lato server).

**Verificato dal vivo end-to-end** (non solo lettura del codice): sequenza REALE di eventi
puntatore (`PointerEvent` dispatchati via `javascript_tool`, non solo chiamate dirette alle
funzioni) per creare due nodi (Domain Controller "DC01" con IP/ruolo/dominio, Tenant
"contoso.onmicrosoft.com") e un collegamento etichettato ("sync ogni 30 min") trascinando dal
pallino di un nodo all'altro - confermato che l'edge si crea, si auto-seleziona, e il pannello
proprieta' passa correttamente ai soli campi del collegamento. Salvataggio confermato leggendo
`Config\InfraDiagram-vnsys-test.json` direttamente su disco (non solo la risposta HTTP). Riavvio
del server + ricaricamento del pannello: stato persistito identico. Eliminazione di un nodo
confermata rimuovere a cascata anche il collegamento associato. Una domanda IA reale in chat
("quale domain controller ha questo tenant e come e' sincronizzato con il cloud?") ha davvero
chiamato `get_tenant_infrastructure` (non un tool diverso, non una risposta indovinata) e
risposto con i dati esatti del diagramma, incluso l'avviso esplicito che si tratta di un dato
dichiarato e non di una verifica live. 390 file `.ps1` (387 + 3 nuovi) sintatticamente puliti,
tag HTML bilanciati (div/button/span), 2 blocchi `<script>` inline sintatticamente validi.

Spedito in v0.9.98. Su richiesta esplicita dell'utente ("dopo spinna agenti di controllo e stress
test di cio' appena implementato... piu' agenti che guardino... sia davvero ben integrato,
fruibile come KB e GUI etc"), TRE agenti paralleli avviati subito dopo questa dichiarazione,
scope deliberatamente non sovrapposto:

**Agente "Regression review v0.9.98 (infra diagram vs esistente)"** (general-purpose, background)
— AVVIATO 25/08/2026. Scope: SOLO verificare che il commit 4189d0e non abbia rotto nulla di
GIA' esistente - pannelli upload/intestazioni/impostazioni, tab Documentazione/KB, cambio tab,
layout della toolbar a piu' pulsanti, isolamento del blocco INFRASTRUTTURA nel prompt di sistema
rispetto ai blocchi KB gia' collaudati, round-invarianza dell'elenco strumenti (cache-hit ancora
~99%, v0.9.89), isolamento cross-tenant del diagramma (creato su un tenant, mai visibile su un
altro, sia lato IA sia lato GUI dopo uno switch). — COMPLETATO, nessun problema trovato: tutti
i pannelli esistenti confermati funzionanti dopo l'aggiunta del nuovo pulsante/pannello, isolamento
cross-tenant del diagramma confermato sia lato IA sia lato GUI, round-invarianza dell'elenco
strumenti intatta, nessuna modifica necessaria.

**Agente "Stress-test editor Infrastruttura (GUI)"** (general-purpose, background) — AVVIATO
25/08/2026. Scope: interazione pesante con l'editor stesso - molti nodi (50+), nomi/note con
caratteri speciali/HTML (verifica escaping reale, non solo lettura del codice), collegamento di
un nodo verso se stesso, doppio collegamento identico, eliminazione durante un trascinamento,
resize finestra/tema chiaro-scuro, comportamento con diagramma vuoto, pulsante Ricarica dopo
modifiche non salvate. — COMPLETATO, v0.9.99. Test dal vivo eseguiti su un tenant isolato
("AlePiras", diagramma vuoto in partenza) invece che su "vnsys-test", per non interferire con i
dati usati in parallelo dagli altri due agenti della stessa maratona sullo stesso tenant condiviso
(collisione osservata realmente all'inizio del test: un salvataggio proprio aveva
temporaneamente sovrascritto il diagramma di "vnsys-test" con dati di stress-test prima che
l'agente "Verifica fruibilita' IA/KB" lo risalvasse coi propri dati - nessun danno permanente,
ma lezione appresa e applicata per il resto del giro).

**2 bug reali trovati e corretti**: (1) `.infra-node-box` non aveva ne' un attributo `fill` ne'
una regola CSS - un `<rect>` SVG senza fill usa il nero di default per specifica, mai intonato al
tema; invisibile/quasi illeggibile in tema chiaro (testo quasi nero su casella nera piena,
confermato leggendo `rgb(0,0,0)` di fill contro `rgb(22,34,46)` di testo nel DOM reale). Corretto
con `fill: var(--surface)` sulla stessa regola. (2) Se il nodo di partenza di un collegamento
viene rimosso PRIMA che il gesto termini, il gestore `pointerup` creava comunque un collegamento
con `from` verso un id ormai inesistente (nessun crash - il render lo salta, il server lo
scarterebbe comunque al salvataggio - ma un oggetto fantasma restava in `infraEdges`,
contraddicendo il commento del codice che dava per scontato un filtro client gia' presente).
Corretto aggiungendo `infraNodes.some(n => n.id === fromId)` al controllo prima di creare
l'edge. Entrambi riverificati dal vivo dopo il fix con la stessa identica riproduzione.

**Altre 7 aree testate dal vivo, nessun problema**: 60 nodi + 55 collegamenti (rendering ~4ms,
salvataggio/ricaricamento corretti); XSS in nome/ruolo/etichetta sempre neutralizzato da
`escapeHtmlInfra()` (confermato sul DOM risultante, zero tag eseguibili, sia da modello diretto
sia dai veri campi del pannello proprieta'); self-loop correttamente rifiutato in silenzio; due
collegamenti identici coesistono senza problemi; nome vuoto -> "(senza nome)" sia client sia
server; "Ricarica" scarta correttamente le modifiche non salvate; tema chiaro/scuro e resize a
480px senza overflow di pagina (limite v1 di scroll-senza-pan/zoom confermato, non un difetto).
Nota fuori ambito non corretta: nome/nota da 250+ caratteri sborda dalla casella senza
troncamento (nessun crash, solo leggibilita' su un input estremo) - segnalato come possibile
miglioramento futuro (ellissi sul canvas), non affrontato per restare in ambito.

**Agente "Verifica fruibilita' IA/KB del diagramma infrastruttura"** (general-purpose, background)
— AVVIATO 25/08/2026. Scope: get_tenant_infrastructure su piu' formulazioni di domanda, diagramma
con un solo nodo, verifica che il tetto 500 nodi/1000 collegamenti in Set-M365OpsInfraDiagram.ps1
scatti davvero, che l'etichetta "Fonte dati" corretta in Get-M365OpsToolSourceLabel.ps1 non abbia
regredito le altre (graph_api_call/kb_query/cli_m365/ecc.), che il conteggio token (v0.9.97)
continui ad accumulare correttamente anche in una conversazione che include una chiamata a
get_tenant_infrastructure. — COMPLETATO, nessun problema trovato: 5 formulazioni diverse di
domande sull'infrastruttura tutte risposte correttamente (mai inventate) con la nota "Fonte dati"
corretta; diagramma a 1 nodo gestito senza crash (unico nit cosmetico e invisibile all'utente:
"1 nodi" invece di "1 nodo" nel riassunto grezzo per l'IA, mai mostrato all'utente cosi' com'e' -
non corretto); tetto 500 nodi verificato scattare davvero (550 inviati, 500 salvati); tetto 1000
collegamenti verificato scattare davvero (1050 inviati con 2 riferimenti a nodi inesistenti, 1000
salvati, zero riferimenti orfani); kb_query/graph_api_call/cli_m365_* tutti confermati con
l'etichetta "Fonte dati" corretta, nessuna regressione dai due nuovi case aggiunti allo stesso
switch; conteggio token riverificato matematicamente contro i log server, somma esatta anche con
get_tenant_infrastructure nel mix; iniezione nel prompt di sistema confermata sempre condizionata
a `Get-M365OpsInfraDiagramNarrative.Summary -ne $null`, nessun percorso di codice la aggira.

## Seguito: documentazione/diagramma condivisi per TENANT REALE, tipi Internet/Intranet, export/import cifrato (v0.10.0)

Quattro richieste esplicite dell'utente, arrivate in sequenza in un'unica conversazione dopo aver
notato un problema architetturale reale sul proprio ambiente.

**Osservazione iniziale dell'utente**: "mi confermi che l'infra che disegni dentro il tenant in
cui sei connesso resti per quel tenant specifico? potremmo forse metterla sotto documentazione?
siccome ogni tenant puo' avere accesso ibrido e app ma e' pur sempre lo stesso tenant come
consigli di fare si che la documentazione + disegno infra ci sia una sola volta per entrambi?" -
confermato l'isolamento (corretto), ma verificato concretamente in `Config\tenants.json` che
"vnsys-test" (AppOnly) e "vnsys delegata" (Delegato) hanno lo STESSO `TenantId`
("vnsysit.onmicrosoft.com") - stesso tenant fisico, due profili, quindi oggi due Knowledge
Base/diagrammi separati e vuoti invece di uno condiviso. Proposto di ri-chiavare lo storage per
Tenant ID risolto invece che per nome profilo - approvato dall'utente ("procedi con entrambe le
cose"), con una precisazione tecnica importante aggiunta subito dopo: "prevedi che il tenant id
sia numerico e testuale... prendi vnsysit.onmicrosoft.com e il suo riferimento numerico come
stessa cosa" - un tenant Microsoft ha sempre sia una forma dominio (es.
"vnsysit.onmicrosoft.com") sia una forma GUID, e due profili potrebbero avere il TenantId scritto
in forme diverse pur riferendosi allo stesso tenant.

**1) Risoluzione Tenant ID e ri-chiavatura storage**: nuovo `Private\Resolve-M365OpsTenantGuid.ps1`
- risolve QUALUNQUE forma (dominio o GUID) al GUID canonico interrogando l'endpoint pubblico di
discovery OIDC di Microsoft (`login.microsoftonline.com/<id>/v2.0/.well-known/openid-configuration`,
nessuna autenticazione richiesta, il campo `issuer` della risposta contiene sempre il GUID
canonico) - idempotente (risolvere un GUID gia' canonico restituisce se stesso), cache in-memory
per processo (una sola chiamata di rete per valore grezzo distinto), fallback SEMPRE al valore
grezzo se la rete non risponde (mai un'eccezione che romperebbe la lettura di Documentazione/
Diagramma - nel caso peggiore la condivisione semplicemente non scatta finche' la rete non torna).
Nuovo `Private\Get-M365OpsTenantStorageKey.ps1` (nome profilo -> chiave risolta, pass-through
invariato per un nome che non e' un profilo reale, es. il bucket KB globale `_global`).

**Migrazione automatica pigra**: nuovi `Private\Get-M365OpsInfraDiagramPath.ps1` e
`Private\Get-M365OpsKnowledgeBasePaths.ps1` - al primo accesso di un profilo, se esiste ancora un
file sotto il vecchio schema per NOME PROFILO, i suoi dati vengono UNITI (mai sovrascritti) nel
nuovo file per chiave risolta (gia' esistente o creato al volo), poi il file legacy viene
rinominato con un suffisso `.migrated-<data>` (mai eliminato - recuperabile). Idempotente: al
prossimo accesso non c'e' piu' nulla da migrare, un solo `Test-Path` economico. Gestisce
correttamente il caso con PIU' profili sullo stesso tenant reale che avevano gia' dati legacy
separati: qualunque profilo venga acceduto per primo crea/popola il file canonico, il successivo
unisce additivamente i propri dati in quello gia' esistente. Aggiornati per usare la nuova chiave:
`Get-/Set-M365OpsInfraDiagram.ps1`, `Get-M365OpsKnowledgeCatalog.ps1`,
`Get-M365OpsKnowledgeDocumentText.ps1`, `Add-/Remove-M365OpsKnowledgeDocument.ps1`. Uno storico
chat (`Get-M365OpsChatHistory`) resta DELIBERATAMENTE per profilo, non toccato - una conversazione
e' legata alla sessione/modalita' di lavoro attiva, non al tenant in astratto.

**2) Rimando dalla tab "Documentazione"**: box con pulsante "🗺️ Apri Infrastruttura" nella tab
Documentazione (`Gui/index.html`) - chiude le Impostazioni e apre `#infra-panel` al suo posto
(riusa il toggle di `settingsBtn` gia' esistente, che gestisce gia' correttamente mostrare/
nascondere chat e footer). L'editor resta un pannello dedicato in toolbar, non spostato dentro la
tab (un canvas grande starebbe stretto in una tab di impostazioni) - deciso insieme all'utente
prima di implementare, non assunto.

**3) Tipi di nodo Internet/Intranet**: richiesto esplicitamente a meta' di un turno successivo
("il disegno deve riguardare anche solo architetture solo online, magari multi-cloud, non
fermarti solo all'ibrido, mettici dentro tutto") - due nuovi tipi (🌐 Internet, 🔒 Intranet),
totale 19 tipi di nodo. Il campo IP esistente gia' accetta liberamente una classe di indirizzi
(placeholder aggiornato con un esempio CIDR), nessun campo nuovo necessario.

**4) Export/import cifrato**: richiesto esplicitamente ("verifica se e' possibile fare export +
import del file salvato per condividere tra app le infrastrutture... rendi cifrato l'export se
possibile"). Nuovi pulsanti "Esporta..."/"Importa..." nel pannello. Il file esportato porta
SEMPRE il Tenant ID risolto (stessa chiave del punto 1) - all'import, un confronto col tenant
attivo in quel momento produce un avviso non bloccante se diverso (l'import non salva mai da
solo, richiede comunque "Salva" esplicito). Cifratura con passphrase FACOLTATIVA (vuota = export
in chiaro): AES-256-CBC + HMAC-SHA256 (cifra-poi-autentica), non AES-GCM -
`System.Security.Cryptography.AesGcm` non e' disponibile in modo affidabile su Windows
PowerShell 5.1/.NET Framework (dichiarato supportato da questo modulo), CBC+HMAC funziona
identico li' e sotto PowerShell 7 (il runtime reale della GUI). Chiavi derivate via PBKDF2
(100.000 iterazioni, salt casuale) - due chiavi SEPARATE per cifratura/autenticazione dallo
stesso materiale derivato, mai la stessa chiave riusata per entrambe. Verifica HMAC SEMPRE prima
di decifrare (mai il contrario - decifrare per primo esporrebbe a un padding-oracle). Confronto a
tempo costante scritto a mano (non `CryptographicOperations.FixedTimeEquals`, anch'essa assente
su .NET Framework). Nuovi `Private\Protect-/Unprotect-M365OpsInfraExport.ps1`, due nuove route
`Gui/Server.ps1` (`/api/infra-diagram/export`, `/import`).

**Verificato dal vivo, non solo lettura del codice**:
- Crypto isolata prima dell'integrazione: round-trip cifra/decifra corretto, passphrase sbagliata
  rifiutata con un errore chiaro, ciphertext manomesso (1 byte capovolto) rifiutato - testato in
  isolamento via dot-sourcing diretto dei due file, PRIMA di collegarli alle route.
- Risoluzione Tenant ID confermata REALE (non simulata): "vnsysit.onmicrosoft.com" risolto al
  GUID canonico `6214cf15-ccd4-4eec-8171-da2ace0ebc91` tramite una vera chiamata di rete.
- Migrazione confermata sui dati reali gia' presenti nel repository di test: attivando
  "vnsys-test" (6 nodi legacy) poi "vnsys delegata" (1 nodo legacy, "PersistedNode") in
  sequenza, i due diagrammi si sono uniti additivamente nello stesso file condiviso (7 nodi
  totali) - i due file legacy correttamente rinominati `.migrated-20260825`. "AlePiras" (tenant
  reale diverso, GUID diverso) rimasto isolato con la propria Knowledge Base/diagramma intatti.
- Stesso test ripetuto con successo per la Knowledge Base: un documento di test caricato su
  "vnsys-test" via `Add-M365OpsKnowledgeDocument` immediatamente leggibile - testo completo
  incluso via `Get-M365OpsKnowledgeDocumentText` - da "vnsys delegata", assente su "AlePiras";
  rimozione (`Remove-M365OpsKnowledgeDocument`) confermata sparire da entrambi i profili
  condivisi contemporaneamente.
- Domanda IA reale dopo la migrazione ("quanti nodi ci sono nel diagramma infrastruttura di
  questo tenant?") ha risposto correttamente "7 nodi" con la nota fonte corretta - confermato che
  `get_tenant_infrastructure` legge in modo trasparente la nuova chiave, nessuna modifica
  necessaria in `Invoke-M365OpsAgentTools.ps1` per questo (gia' passava solo il nome profilo).
- Export/import testati nel browser reale con veri `PointerEvent`/eventi file (tecnica
  `DataTransfer` per simulare la selezione di un file su `<input type=file>`, `window.prompt`
  temporaneamente sovrascritto per fornire la passphrase senza un vero dialogo di sistema):
  round-trip in chiaro corretto, round-trip cifrato corretto, passphrase errata rifiutata con un
  errore chiaro (nessun dato corrotto, canvas rimasto vuoto), avviso di tenant diverso mostrato
  correttamente importando deliberatamente un export di "vnsys-test" mentre "AlePiras" era
  attivo, confermato che quell'import cross-tenant NON ha scritto nulla su disco (diagramma di
  "AlePiras" verificato invariato dopo, prima di premere "Salva").
- 396 file `.ps1` sintatticamente puliti, tag HTML bilanciati, 2 blocchi `<script>` inline
  sintatticamente validi.

Spedito in v0.10.0 (bump minore invece che di patch, a segnare che questo e' un blocco di lavoro
piu' sostanzioso del solito giro di fix puntuale - non un cambio di disciplina, la stessa identica
verifica dal vivo/changelog/PDF/marathon-state e' stata applicata). Nessun agente di regressione
dedicato per questo giro specifico: cambiamento verificato a fondo direttamente, in modo end-to-end,
prima di considerarlo chiuso (crypto isolata, migrazione sui dati reali del repository di test,
isolamento cross-tenant, integrazione IA, GUI export/import) - se l'utente vuole comunque un altro
giro di agenti dedicati, va richiesto esplicitamente come nei giri precedenti.

Richiesto esplicitamente subito dopo ("fai un giro") - TRE agenti paralleli avviati, scope non
sovrapposto:

**Agente "Regression review v0.10.0"** (general-purpose, background) — AVVIATO 25/08/2026. Scope:
SOLO verificare che il commit 6d2704f non abbia rotto nulla di gia' esistente - flusso upload/
rimozione documenti KB dalla GUI (tab Documentazione), storico chat (deliberatamente NON toccato
da questo commit, deve restare per-profilo), le funzionalita' gia' collaudate dell'editor
Infrastruttura (v0.9.98/99: drag nodi, collegamenti, tema chiaro/scuro), round-invarianza
dell'elenco strumenti IA (cache-hit), pannelli GUI esistenti. — COMPLETATO (dopo un'interruzione
di connessione a meta' lavoro, ripreso dallo stesso punto), nessuna regressione trovata: upload/
rimozione documenti KB via GUI reale confermati funzionanti col nuovo box di rimando, storico chat
confermato rimasto per-profilo (non toccato dal commit), editor Infrastruttura funzionante dopo il
cambio di chiave di storage, cache-hit al round 2 confermata al 94,8% (in linea con l'obiettivo
~90%+ del v0.9.89), 396 file `.ps1` sintatticamente puliti.

**Agente "Stress-test migrazione/isolamento Tenant ID"** (general-purpose, background) — AVVIATO
25/08/2026. Scope: casi limite della risoluzione/migrazione - profilo senza campo TenantId,
TenantId non risolvibile (dominio inesistente), Config\tenants.json assente, file legacy con JSON
corrotto, collisione di id tra nodi/documenti durante un merge, copia effettiva dei FILE caricati
(non solo il catalogo JSON) durante la migrazione Knowledge Base. — COMPLETATO, 1 bug reale
trovato e corretto (v0.10.1).

**Esito agente "Stress-test migrazione/isolamento Tenant ID" (v0.10.1)**: 5 dei 6 casi limite
testati dal vivo senza problemi (profilo senza `TenantId` → fallback silenzioso al nome profilo;
dominio non risolvibile → fallback al valore grezzo, `Warn` confermato in log;
`Config\tenants.json` assente → fallback al nome profilo, ripristinato subito e verificato
bit-per-bit; JSON legacy corrotto → `catch` gestito, nessun crash, nessun file canonico fantasma,
il legacy corrotto viene comunque rinominato `.migrated-*` - non peggiora nulla, era gia'
irrecuperabile; collisione di `id` tra due sorgenti legacy con lo stesso Tenant ID risolto →
`Sort-Object -Unique` scarta deterministicamente e silenziosamente il duplicato piu' recente,
nessuna corruzione - comportamento accettato, id reali timestamp+sequenza).

**1 bug reale trovato e corretto** in `Private\Get-M365OpsKnowledgeBasePaths.ps1` (piu' serio del
caso JSON-corrotto sopra, specifico alla Knowledge Base perche' - a differenza del diagramma
infrastruttura, puro JSON - la sua migrazione copia anche i FILE caricati fisicamente): il ciclo
`Get-ChildItem ... | ForEach-Object { Copy-Item ... }` non aveva un `try/catch` proprio - un solo
file bloccato (lock esclusivo, permessi, qualunque causa transitoria) interrompeva l'INTERO ciclo
(zero file copiati, non solo quello bloccato, riprodotto dal vivo tenendo un file legacy aperto in
esclusiva durante la migrazione), mentre il catalogo unito (scritto PRIMA della copia) e il
rinominare-come-migrato del catalogo legacy (eseguito INCONDIZIONATAMENTE subito dopo, anche a
copia fallita) procedevano comunque - catalogo canonico con voci "fantasma" puntate a documenti
mai arrivati a destinazione, nessun modo automatico di ritentare dato che il catalogo legacy (unico
segnale che fa scattare la migrazione) risultava gia' rinominato via. Corretto con due modifiche
mirate: (1) ogni singola `Copy-Item` ha ora il proprio `try/catch` (un file bloccato non blocca piu'
gli altri file dello stesso batch); (2) il rinominare-come-migrato del catalogo legacy scatta ora
SOLO se nessuna copia e' fallita in quel passaggio - altrimenti il catalogo legacy resta
deliberatamente al suo posto, cosi' il prossimo accesso ritenta automaticamente la copia dei soli
file ancora mancanti (retry economico e idempotente, i file gia' arrivati vengono saltati).
Riverificato dal vivo con lo stesso scenario esatto: primo tentativo (file ancora bloccato) - altri
file del batch copiati correttamente, catalogo legacy correttamente NON rinominato; rilasciato il
lock, secondo tentativo (nessuna azione manuale oltre un nuovo accesso al profilo) - file rimasto
indietro copiato con successo, catalogo legacy finalmente rinominato `.migrated-*`,
`Get-M365OpsKnowledgeDocumentText` ha letto il testo completo del documento in precedenza bloccato
senza errori. Profili/dati temporanei di stress-test (`zzstress-*`) rimossi al termine del giro; i
profili reali (`vnsys-test`, "vnsys delegata", `AlePiras`) e i loro dati non sono mai stati toccati.

**Esito agente "Review sicurezza crypto + edge case export/import" (v0.10.2)**: crypto isolata
verificata dal vivo, non solo letta - salt (16 byte) e IV freschi ad ogni chiamata (due export
consecutivi dello stesso diagramma: salt/IV/ciphertext tutti e tre diversi), chiavi AES/HMAC meta'
distinte dei 64 byte PBKDF2 mai riusate, HMAC verificato SEMPRE prima di decifrare (letto nel
codice: il `throw` sul confronto precede `CreateDecryptor()`), confronto a tempo costante scritto
a mano corretto (itera l'intera lunghezza a prescindere da dove cade la prima differenza; il
controllo di lunghezza diversa short-circuita prima del loop - accademico in un tool locale, non
un problema pratico), 100.000 iterazioni PBKDF2-SHA256 ragionevole per un export locale facoltativo
(nota per il futuro, non un difetto). Passphrase errata, ciphertext manomesso (1 byte) e HMAC
manomesso (1 byte) producono dal vivo il MEDESIMO errore generico, nessun dettaglio interno,
nessuno stack trace verso il client.

**2 bug reali trovati e corretti**, entrambi nella gestione di un envelope di import non fidato
(mai nella crypto isolata in se'). **(1) Blocco totale del server, il piu' serio**:
`Unprotect-M365OpsInfraExport.ps1` leggeva `iterations` dall'envelope importato senza alcun
limite - un envelope con `iterations: 2000000000` mandava `Rfc2898DeriveBytes` a macinare per un
tempo indefinito, e siccome `Gui/Server.ps1` e' un processo unico single-threaded questo bloccava
l'INTERO server per QUALUNQUE richiesta successiva, persino `/api/restart` stesso (servito dallo
stesso processo bloccato) - riprodotto dal vivo: una richiesta parallela e' andata in timeout dopo
10s, persino la chiamata di restart e' rimasta senza risposta, servito un kill manuale del
processo (`Stop-Process -Force` + rilancio identico) per riprendersi - collateral reale sull'altro
agente parallelo "Stress-test migrazione/isolamento Tenant ID", che in quella finestra stava
attivamente lavorando sullo stesso server condiviso (confermato dal log: le sue richieste hanno
ripreso a comparire solo dopo il kill/rilancio). Corretto validando `iterations` PRIMA di
qualunque lavoro costoso: assente → default 100.000 (retrocompatibile), presente ma fuori
dall'intervallo 1..2.000.000 → rifiutato immediatamente con lo stesso errore generico gia' usato
per l'HMAC che non torna. Riverificato dal vivo: la stessa richiesta ora risponde in ~150ms invece
di bloccare tutto; negative e non-numeriche rifiutate allo stesso modo; iterazioni legittime
(100.000) restano intatte, round-trip a 7 nodi confermato invariato. **(2) Canvas rotto su un
import senza il campo `diagram`**: un envelope non cifrato con `diagram` mancante/manomesso
produceva lato server `nodes:[null]` invece di un array vuoto (`@($null)` in PowerShell produce un
array con UN elemento `null` dentro, non un array vuoto) - quel `null` sarebbe arrivato cosi'
com'era al canvas GUI, dove `renderInfraCanvas` legge `n.id` su ogni nodo e avrebbe lanciato
un'eccezione JavaScript non gestita (verificato leggendo `Gui/index.html`, non solo ipotizzato).
Corretto filtrando i null lato server (`Where-Object { $_ }`) prima di rispondere - riverificato
dal vivo, lo stesso import ora degrada correttamente a un diagramma vuoto.

**Edge case delle route verificati dal vivo senza problemi**: envelope vuoto/`{}`/senza il
marcatore `m365opsExport`/con versione sconosciuta → errore chiaro uniforme, mai un crash;
`encrypted: true` senza passphrase (sia omessa che stringa vuota esplicita) → messaggio dedicato
"serve la passphrase"; tetto dimensionale (500 nodi/1000 collegamenti) confermato non aggirabile
dall'import - l'import non salva mai nulla da solo (restituisce solo nodi/collegamenti per il
canvas), il tetto vive nel percorso di salvataggio condiviso `Set-M365OpsInfraDiagram.ps1` e si
applica comunque a "Salva", confermato salvando in isolamento (tenant temporaneo dedicato,
rimosso subito dopo, mai toccato lo storage condiviso reale) 600 nodi/1200 collegamenti sintetici
→ troncati correttamente a 500/998; passphrase con caratteri unicode accentati, emoji, e fino a
2000 caratteri, e passphrase vuota esplicita vs. omessa → tutte gestite correttamente in un
round-trip export/import completo.

Spedito in v0.10.2. Nessuna osservazione discrezionale oltre alle 100.000 iterazioni PBKDF2 gia'
citata (non un difetto, solo una nota per un eventuale rialzo futuro dello standard).

## Seguito: editor Infrastruttura meno scomodo su schermo portatile (v0.10.3)

Segnalato dal vivo dall'utente: "in uno schermo portatile l'editing della infrastruttura appare un
po' complicato dovendo scorrere su e giu'. e' possibile fare qualcosa?" - domanda esplorativa,
risposto con una raccomandazione concisa (pannello proprieta' a fianco invece che sotto il canvas,
altezza del canvas responsive, testo esplicativo piu' corto) e chiesta conferma prima di
implementare, coerentemente con le altre volte in questa sessione in cui l'utente ha corretto
scelte di design GUI fatte senza chiedere prima (v0.9.95, posizione del pannello intestazioni).
Confermato ("va bene"), implementato.

**Causa**: il pannello proprieta' (`#infra-props-panel`) appariva SOTTO il canvas - selezionare un
nodo lo faceva comparire in fondo, spingendo il resto della pagina piu' in basso (seleziona ->
scorri giu' per modificare -> scorri su per tornare a disegnare). Il canvas aveva inoltre
un'altezza FISSA di 420px indipendente dallo spazio realmente disponibile in verticale.

**Corretto**: nuovo contenitore `#infra-workspace` (flexbox) che affianca canvas e pannello
proprieta' quando c'e' spazio orizzontale (oltre 900px, media query), tornano impilati sotto quella
soglia. Altezza del canvas cambiata da fissa a `min(420px, 55vh)`. Testo esplicativo sopra la
toolbar accorciato da un paragrafo lungo a una frase.

**Bug reale trovato durante la verifica dal vivo dello stesso cambiamento (non pre-esistente,
introdotto da questa stessa modifica), corretto nello stesso giro**: nel layout impilato (schermo
stretto), `#infra-canvas-wrap` non rispettava la larghezza del viewport - `flex: 1` su un elemento
dentro un contenitore `flex-direction: column` regola l'asse PRINCIPALE (verticale in quel layout),
non la larghezza; senza un vincolo esplicito sulla larghezza, il contenitore restava largo quanto
il suo contenuto (l'SVG interno e' largo 1800px) invece di restringersi al contenitore. Riprodotto
dal vivo: a 800px di larghezza il contenitore del canvas restava largo 1802px, causando uno
scorrimento ORIZZONTALE indesiderato dell'intera pagina (non solo del canvas, che ha gia' il
proprio scroll interno voluto). Corretto aggiungendo `width: 100%; max-width: 100%;` esplicito -
riverificato che il layout a due colonne (largo) non ne risente, dove `flex:1` si applica davvero
all'asse orizzontale e domina comunque su `width:100%` nell'algoritmo flessibile.

**Verificato dal vivo a tre larghezze** (non solo lettura del codice): 1366×768 (laptop tipico) -
due colonne fianco a fianco confermate (`flexDirection: row`, canvas 1036px + proprieta' 280px),
nessuno scorrimento di pagina. 1366×650 (laptop con finestra piu' bassa) - canvas ridotto a 358px,
esattamente il 55% di 650 (formula CSS confermata corretta via `getBoundingClientRect`), scorrimento
di pagina ridotto (54px residui, dovuti all'intestazione/toolbar sopra, non al canvas) invece che
il pieno overflow di prima. 800×700 (schermo stretto) - layout correttamente impilato in colonna
(`flexDirection: column`), nessuno scorrimento orizzontale dopo il fix del bug sopra. Riverificate
anche le funzionalita' esistenti con il nuovo layout: trascinamento reale di un nodo (sequenza
`PointerEvent` autentica: pointerdown -> pointermove -> pointerup, non solo lettura del codice)
sposta correttamente le coordinate salvate in `infraNodes`; tema chiaro/scuro applicato
correttamente (colore della casella nodo confermato mai nero in nessuno dei due temi, stesso
controllo del fix v0.9.99). 396 file `.ps1` sintatticamente puliti, tag HTML bilanciati (div/
button/span), 2 blocchi `<script>` inline sintatticamente validi.

Spedito in v0.10.3. Su richiesta esplicita dell'utente ("poi fai un giro di stresstest gui e codice
e bug fix"), DUE agenti paralleli avviati subito dopo questa dichiarazione:

**Agente "Stress-test approfondito layout Infrastruttura v0.10.3"** (general-purpose, background)
— AVVIATO 26/08/2026. Scope: il layout a due colonne appena spedito, oltre le tre larghezze gia'
verificate a mano - viewport tablet/portrait, zoom del browser, il confine esatto della soglia
900px, interazione tra drag/collegamento e i nuovi bordi del canvas piu' stretto, molti nodi in
entrambi i layout. — COMPLETATO, un bug reale trovato e corretto, vedi sezione dedicata sotto.

**Agente "Stress-test generale GUI/codice, ricerca bug nuovi"** (general-purpose, background) —
AVVIATO 26/08/2026. Scope: giro ampio non legato a una singola feature recente - percorsi utente
tipici end-to-end (connessione tenant, report, proposta di scrittura con conferma, chat multi-turno),
ricerca di bug NUOVI non gia' coperti dalle maratone precedenti, non ri-verifica di cio' che e'
gia' stato testato a fondo in giri precedenti. — COMPLETATO, 1 bug reale trovato e corretto
(v0.10.5, voci del catalogo comandi locale che ignoravano "invia/manda a email" - vedi sezione
dedicata sotto), molte altre aree stress-testate senza problemi (coesistenza pannelli, richieste
concorrenti, ciclo completo proposta scrittura, percorsi di errore su piu' route).

## Stress-test approfondito layout Infrastruttura v0.10.3: canvas che non rispettava l'altezza sul layout impilato (v0.10.4)

Agente dedicato, scope deliberatamente ristretto al layout a due colonne appena spedito in v0.10.3
(non sovrapposto con l'agente "generale" in corso in parallelo). Oltre le tre larghezze gia'
verificate a mano (1366×768, 1366×650, 800×700), testati: viewport tablet/portrait (768×1024 e
1024×768), il confine esatto della soglia 900px (899/900/901px), zoom del browser (proxy: 1600×900
e 1920×1080), drag/collegamento sul canvas ora piu' stretto, 30 nodi/15 collegamenti in entrambi i
layout, scorrimento interno del pannello proprieta' su viewport molto bassi.

**Bug reale trovato dal vivo (non riletto dal codice, riprodotto con `getBoundingClientRect`),
stessa causa di quello gia' corretto nello stesso giro v0.10.3 ma sull'asse perpendicolare**:
`#infra-canvas-wrap` ha `flex: 1` (scorciatoia per `flex-basis: 0%` + `flex-grow: 1`), che governa
sempre l'asse PRINCIPALE del contenitore flessibile - orizzontale nel layout a due colonne (dove
`height: min(420px, 55vh)` funziona correttamente, perche' li' l'altezza e' sull'asse trasversale,
non toccato da `flex-grow`), ma VERTICALE nel layout impilato sotto i 900px, esattamente dove
quell'altezza avrebbe dovuto contare di piu'. Risultato: sotto i 900px, `flex-grow` ignorava
l'altezza dichiarata ed espandeva il canvas a riempire tutto lo spazio verticale libero del
contenitore genitore. Riprodotto dal vivo a 768×1024 (tablet verticale, layout impilato): altezza
reale del canvas 1017px invece del massimo atteso di 420px (`getComputedStyle` confermava
`flex-basis: 0%`), pannello proprieta' spinto a `top: 1853px`, irraggiungibile senza scorrere la
pagina - la stessa esperienza scomoda (seleziona un nodo, scorri per trovare le proprieta') che
l'intera modifica di v0.10.3 doveva eliminare, qui reintrodotta su viewport alti e stretti invece
che su quelli bassi e larghi.

**Corretto** con lo stesso pattern gia' usato per `#infra-props-panel` nella stessa media query
(`Gui/index.html`, dentro `@media (max-width: 900px)`): aggiunto
`#infra-canvas-wrap { flex: none !important; height: min(420px, 55vh); }` - disattiva
`flex-grow`/`flex-shrink` e riporta `flex-basis` ad `auto`, cosi' l'altezza dichiarata torna a
governare davvero la dimensione. Riverificato dal vivo dopo il fix: altezza corretta a 420px (o al
55vh quando inferiore, es. 275px a 500px di altezza viewport) sia a 768×1024 che a 800×500, pannello
proprieta' tornato raggiungibile, nessuna regressione sul layout a due colonne (dove `flex:1` resta
comunque quello che governa la larghezza, invariato).

**Resto della checklist verificato dal vivo senza altri problemi**: soglia dei 900px collaudata a
899/900/901px con un nodo selezionato (caso peggiore, pannello aperto) - transizione netta tra
impilato e due colonne, nessuno stato intermedio rotto, a larghezza zero o invisibile (899px e
900px entrambi impilati, coerente con `max-width: 900px` inclusivo; 901px passa a due colonne,
556px canvas + 280px pannello, nessuno scorrimento orizzontale in nessuno dei tre casi); tablet
768×1024 (verticale, impilato, dopo il fix) e 1024×768 (orizzontale, due colonne) entrambi corretti,
nessuno scorrimento orizzontale ne' altezza fuori controllo; desktop largo 1600×900/1920×1080 - il
canvas riempie correttamente lo spazio restante via `flex:1` orizzontale (1590px a 1920px), pannello
proprieta' a 280px fissi rimane leggibile ma visivamente stretto su schermi molto larghi
(osservazione estetica soggettiva, non un difetto funzionale - non modificato, per non introdurre
una scelta di design non richiesta); trascinamento reale (sequenza `PointerEvent` autentica -
`pointerdown`/`pointermove`/`pointerup`, non solo lettura del codice) di un nodo vicino al bordo
destro del canvas ora piu' stretto (layout impilato, 800px) - spostamento pixel-esatto confermato
(delta schermo 221px, delta coordinate salvate in `infraNodes` 221px, identico); creazione di un
collegamento trascinando dal pallino di connessione di un nodo a un altro nello stesso layout
stretto - funzionante, edge creato con `from`/`to` corretti; 30 nodi/15 collegamenti sintetici in
entrambi i layout - nessun collasso, scorrimento interno del canvas (`scrollWidth`/`scrollHeight`
1800×1000) ancora disponibile, nessuno scorrimento di pagina indesiderato; pannello proprieta' con
altezza fortemente compressa (1366×500, dove 55vh=275px vince su 420px) - tutti i campi (Tipo, Nome,
Ruolo, IP, Dominio, Note) raggiungibili tramite lo scorrimento interno gia' presente del pannello
(`overflow-y: auto`), confermato scrollando programmaticamente fino in fondo. 396 file `.ps1`
sintatticamente puliti (`ParseFile`), i 2 blocchi `<script>` inline sintatticamente validi (parsati
con `new Function`), tag `div`/`button`/`span` bilanciati in `Gui/index.html` (0 aperture/chiusure
spaiate).

Spedito in v0.10.4.

**Esito agente "Stress-test generale GUI/codice, ricerca bug nuovi"** (general-purpose, background)
— giro ampio non legato a una singola feature recente, deliberatamente non sovrapposto al secondo
agente in parallelo (solo layout Infrastruttura v0.10.3/v0.10.4). Skimmata la cronologia di questo
file per evitare di ri-verificare cio' gia' collaudato ripetutamente (isolamento Knowledge Base,
migrazione Tenant ID, round-invarianza cache, crypto export/import, meccaniche nodi/edge
dell'editor Infrastruttura) e concentrarsi su superficie NON ancora toccata.

**Verificato senza trovare problemi**: 396 file `.ps1` sintatticamente puliti (`ParseFile`), i 2
blocchi `<script>` inline di `Gui/index.html` validi come JS (`node --check`), tag `div`/`button`/
`span` bilanciati (129/61/40 rispettivamente, diff zero su tutti); coesistenza reale dei quattro
pannelli toolbar (Upload, Intestazioni email, Infrastruttura, Impostazioni) aperti tutti insieme -
sono `<div>` fratelli in flusso normale (mai posizionati in modo assoluto), quindi si limitano a
impilarsi verticalmente senza mai sovrapporsi - nessuna collisione visiva/di z-index, nessuno stato
incrociato tra un toggle e l'altro (verificato dal vivo via `PointerEvent`/click reali in browser,
non solo lettura del codice - un primo test aveva mostrato il pannello Infrastruttura sparire dopo
l'apertura in sequenza di tutti e quattro, ma si e' rivelato un artefatto di un'altra tab del
browser condivisa con l'agente parallelo che ha rubato il focus di `javascript_exec`, non un bug
reale - non riproducibile isolando esplicitamente il tabId proprio); due richieste concorrenti
reali a `/api/chat` (fetch in parallelo, non simulate) servite correttamente in sequenza dal server
single-threaded, nessuna risposta incrociata, storico chat coerente in ordine cronologico; percorsi
di errore su piu' route (`/api/chat` con JSON malformato o corpo vuoto, `/api/tenants/activate` su
un profilo inesistente, `/api/reports/download` con un tentativo di path traversal - bloccato
correttamente con 400 "Nome file non valido" sia con `../` sia con `..\`, `/api/kb/upload` con
base64 non valido o `filename` mancante, `/api/ai-status/test` con un provider fuori dal
`ValidateSet`) tutti degradati con un messaggio chiaro e mai un crash del server o uno stato GUI a
meta'; flusso end-to-end completo di una proposta di scrittura reale (`propose_new_custom_script`,
scelto perche' non richiede una sessione tenant attiva) sia in conferma - script salvato, riavvio
automatico del server verificato (il server torna a rispondere entro pochi secondi), il nuovo
strumento `Get-M365OpsStressTestPing` immediatamente richiamabile dall'IA subito dopo il riavvio -
sia in annullamento - nessun file creato, `pending` ripulito lato server; script/dati di test
(incluso lo script temporaneo sopra) rimossi al termine, nessun artefatto lasciato oltre a qualche
messaggio di prova nello storico chat del tenant isolato "AlePiras" (storico comunque a finestra
limitata, non persistente indefinitamente).

**1 bug reale trovato e corretto (v0.10.5)**: `Gui\CommandCatalog.ps1` ha gia', dal 19/08/2026, un
pattern consolidato per cui le voci `ExportDevices`/`ExportMailboxUsageReport`/
`ExportSharedMailboxReport`/`ExportAllMailboxesReport`/`ExportMailFlowReport`/
`ExportForwardingReport`/`ExportInboxRulesReport`/`CompliancePatterns` si fanno da parte (passano
all'IA) quando il messaggio contiene un verbo di invio ('invia'/'manda'/'spedisci') insieme a un
indirizzo email - cosi' una richiesta composta ("...e mandalo a X") viene gestita per intero
dall'IA invece che a meta' dal solo export locale. Questo pattern non era pero' mai stato propagato
a quattro voci gemelle - `ListNonCompliant`, `MfaStatus`, `UserOverview`, `GroupOverview` -
individuate testando in massa (script offline, replica esatta della logica trigger/DeferWords di
`Gui/Server.ps1` senza chiamare l'AI) una quarantina di formulazioni italiane plausibilmente
ambigue tra piu' voci del catalogo. Messaggi come "invia il report dei dispositivi non conformi a
mario@contoso.com" o "manda la panoramica utente di X al mio collega Y@dominio.it" continuavano a
essere intercettati localmente, rispondendo SOLO con il dato richiesto (lista dispositivi, stato
MFA, panoramica) e ignorando in silenzio "invia/manda a" - nessun errore, nessuna proposta di
invio, l'utente senza modo di accorgersi che meta' della richiesta era sparita. Riprodotto dal vivo
su tutti e quattro i casi PRIMA del fix (risposta con "_Fonte: comando locale 'ListNonCompliant'_"
ecc., mai "Elaborata da IA").

Corretto aggiungendo lo stesso segnale di invio ai `DeferWords` delle quattro voci, con un
accorgimento in piu' su `MfaStatus`/`UserOverview`: a differenza delle voci `Export*` (dove un
indirizzo email nel messaggio e' gia' un segnale forte di invio), queste due richiedono SEMPRE un
indirizzo email come soggetto della richiesta stessa (l'UPN dell'utente) - un semplice `@\S+\.\S+`
come DeferWord avrebbe fatto deviare all'IA anche l'uso normale ("stato mfa di mario@contoso.com"),
aumentando inutilmente il costo AI. Usato invece `(invia|manda|spedisci)\w*.*@\S+\.\S+` - verbo di
invio SEGUITO da un indirizzo piu' avanti nella frase, sicuro perche' l'uso normale non contiene
mai un verbo di invio prima dell'indirizzo. Su `GroupOverview` (nessuna email nell'uso normale, il
soggetto e' un nome di gruppo) lo stesso pattern basta da solo, con un vantaggio aggiuntivo: evita
anche che il vecchio `CaptureRegex` non-greedy catturi "IT e mandala a capo@contoso.com" come nome
di gruppo letterale (nessuno dei suoi verbi di continuazione noti include "mandala"), che avrebbe
altrimenti fallito con "nessun gruppo trovato" invece di deviare correttamente.

Riverificato dal vivo dopo il fix (server riavviato, non solo lettura del codice): tutti e quattro
i casi ora rispondono tramite l'IA - risposta reale osservata per `ListNonCompliant`: "Non posso
generare e quindi inviare il report: la sessione Graph delegata non e' attiva... Non e' stata
inviata alcuna email a mario@contoso.com" (riconosce l'intento composto E riporta lo stato reale,
invece di ignorarlo in silenzio); uso normale (senza invio) di tutte e quattro le voci riverificato
invariato, ancora gestito localmente a costo zero IA. Rieseguita l'intera batteria di ~40 casi
ambigui gia' collaudati nei giri precedenti (17-23/08/2026) contro il catalogo corretto: nessuna
variazione di comportamento su nessuno di essi, zero regressioni. 396 file `.ps1` sintatticamente
puliti dopo la modifica.

Spedito in v0.10.5.

## Seguito: "Stato permessi" su tenant Delegato nascondeva il controllo Graph dietro un Exchange non connesso (v0.10.6)

Segnalato dal vivo dall'utente subito dopo aver ricevuto il messaggio di errore Exchange atteso
("Sessione Exchange Online non ancora attiva... vai al tab Tenant...") - corretto in se', ma:
"perche' cita solo EXO? dovrebbe guardare permessi per tutto non solo exo".

**Causa reale**: `Private\Get-M365OpsDelegatedPermissionsCheck.ps1` (il percorso "Stato permessi"
per i tenant Delegato, dove non esiste un'App Registration da verificare - si controllano invece i
ruoli RBAC reali dell'utente) chiamava `Connect-M365OpsExchange` SENZA nessuna protezione come
primissimo passo della funzione. Su un tenant Delegato senza sessione Exchange gia' attiva, quella
funzione lancia deliberatamente un errore invece di avviare un login interattivo da sola (comportamento
corretto e voluto - il server e' a thread singolo, un login bloccante congelerebbe l'intera app per
tutti, non solo per chi ha fatto la richiesta - NON toccato da questo fix). Il problema vero era che
nulla catturava quell'errore: l'intera funzione moriva li', PRIMA di raggiungere un blocco di codice
gia' esistente e COMPLETAMENTE indipendente da Exchange - il controllo dei ruoli DIRECTORY Entra ID
(Intune/Entra ID/Teams/SharePoint via Graph, aggiunto il 21/08/2026, usa lo stesso token del login
Graph delegato) - che non veniva mai raggiunto. Un solo prerequisito mancante (Exchange) nascondeva
quindi il risultato di un controllo del tutto slegato che avrebbe potuto rispondere comunque.

**Corretto** racchiudendo l'intero blocco Exchange (connessione + lettura ruoli RBAC + le sei aree
derivate) in un `try/catch`: un fallimento produce ora una riga informativa dedicata ("Ruoli RBAC
Exchange Online (tutte le aree sopra) - non verificabile", con lo stesso messaggio gia' prodotto da
`Connect-M365OpsExchange` cosi' l'utente sa esattamente cosa fare) invece di interrompere l'intera
funzione - il codice prosegue poi regolarmente sul blocco Graph/Entra ID gia' esistente (che ha gia'
il proprio try/catch indipendente per il proprio possibile fallimento, invariato).

**Verificato dal vivo**: riprodotto lo scenario esatto segnalato dall'utente - attivato "AlePiras"
(tenant Delegato) appena dopo un riavvio del server, ne' sessione Exchange ne' login Graph delegato
attivi, poi inviato "verifica permessi app" via `/api/chat` (lo stesso percorso reale della GUI). La
risposta ora mostra ENTRAMBE le informazioni nello stesso messaggio: "Ruoli RBAC Exchange Online...
non verificabile" (con l'istruzione su come connettere Exchange) E "Elenco completo ruoli DIRECTORY
Entra ID... Lettura fallita (serve prima un login Graph delegato attivo - vedi tab Tenant, 'Accedi a
Microsoft Graph con il mio utente')" - prima del fix la seconda riga non sarebbe MAI comparsa,
l'intera risposta si sarebbe fermata al primo errore Exchange. Il controllo raggiunge quindi ora
davvero l'area Graph, riportando onestamente lo stato di ENTRAMBE le aree invece di una sola. 396
file `.ps1` sintatticamente puliti dopo la modifica.

Spedito in v0.10.6. Nessun agente dedicato per questo giro - fix mirato (un `try/catch` attorno a un
blocco gia' isolato), verificato direttamente end-to-end riproducendo lo scenario esatto segnalato
dall'utente prima di considerarlo chiuso.

## Correzione di rotta: la regola "verificare TUTTO il codice" non stava venendo rispettata

L'utente ha segnalato (giustamente, senza mezzi termini) che gli ultimi giri di stress-test erano
stati scope-ati SOLO sulle feature appena spedite, in violazione diretta della regola #2 della
maratona gia' scritta in cima a questo file ("Obiettivo reale: verificare TUTTO il codice, non solo
le aree toccate di recente... Non dare per assodato nulla solo perche' una maratona passata lo ha
gia' 'chiuso'"). Il bug v0.10.6 ("Stato permessi" su Delegato) e' rimasto nascosto per giorni proprio
per questo motivo - una prima risposta che spiegava il perche' senza correggere subito la rotta e'
stata giustamente respinta come una scusa invece che un'azione.

**Osservazione di valore reale emersa comunque**: il bug v0.10.6 e' il TERZO caso nella stessa
sessione dello stesso identico schema - una funzione con PIU' controlli/operazioni indipendenti in
sequenza, dove un'eccezione nel passo 1 fa morire silenziosamente anche i passi 2..N pur non
dipendendo dal primo (v0.10.1: un file bloccato durante la migrazione KB bloccava la copia di TUTTI
gli altri file; v0.10.2: un campo malformato nell'import del diagramma bloccava l'INTERO server;
v0.10.6: Exchange non connesso bloccava anche il controllo Graph/Entra ID indipendente). Vale la
pena cercare questo pattern specifico in tutto il codice, non solo continuare a scoprirlo per caso.

Su richiesta esplicita dell'utente ("parti subito con la fix gia' proposta e dopo fai un giro piu'
ampio su tutto"), CINQUE agenti avviati in parallelo, nessuno scope-ato a commit recenti:

**Agente "Audit pattern 'un passo fallito blocca i passi fratelli indipendenti'"** (general-purpose,
background) — AVVIATO 26/08/2026. Scope: TUTTO il codice (non solo file recenti) - cercare funzioni
con piu' controlli/operazioni indipendenti in sequenza/loop dove un'eccezione in un passo non e'
isolata e blocca silenziosamente i successivi, stesso schema dei tre bug gia' trovati. — IN CORSO.

**Agente "Stress-test funzioni Exchange/mail-flow, tutto il codice"** (general-purpose, background)
— AVVIATO 26/08/2026. Scope: mailbox, gruppi di distribuzione, regole di trasporto, inoltri,
anti-spam, message trace/NDR - non limitato a modifiche recenti. — IN CORSO.

**Agente "Stress-test funzioni Intune/Entra ID/sicurezza, tutto il codice"** (general-purpose,
background) — AVVIATO 26/08/2026. Scope: dispositivi, criteri di conformita', app protection,
conditional access, utenti/gruppi, MFA, ruoli - non limitato a modifiche recenti. — IN CORSO.

**Agente "Stress-test funzioni Teams/SharePoint/report/script personalizzati, tutto il codice"**
(general-purpose, background) — AVVIATO 26/08/2026. Scope: policy Teams, siti/permessi SharePoint,
generazione report, catalogo script personalizzati - non limitato a modifiche recenti. —
COMPLETATO, 5 bug reali trovati e corretti (v0.10.14, vedi sezione dedicata sotto).

**Agente "Stress-test GUI ampio, tutta l'app"** (general-purpose, background) — AVVIATO 26/08/2026.
Scope: percorsi utente end-to-end su TUTTE le sezioni della GUI (non solo quelle aggiunte di
recente), inclusi flussi piu' vecchi mai ri-testati in questa maratona. — IN CORSO.

## Esito "Stress-test funzioni Exchange/mail-flow, tutto il codice" (v0.10.7)

Agente COMPLETATO. Scope: mailbox, gruppi di distribuzione, regole di trasporto, connettori,
anti-spam/anti-phishing, domini accettati/remoti, forwarding, message trace/NDR, litigation hold,
isolamento reattivo Exchange (worker separato), permessi app/delegati RBAC Exchange - 105 file
`.ps1` Public+Private dell'area Exchange/mail-flow, tutti sintatticamente puliti (verificato con
`[System.Management.Automation.Language.Parser]::ParseFile`).

**4 bug reali trovati e corretti, stesso schema "un passo fallito blocca i passi fratelli
indipendenti" gia' visto in v0.10.1/v0.10.2/v0.10.6** (cercato deliberatamente su richiesta
esplicita, non trovato per caso):
1. `Public\Get-M365OpsMailboxDelegatesReport.ps1` - ciclo su TUTTE le mailbox che chiamava
   `Get-M365OpsMailboxPermissions` senza protezione: un errore su una sola mailbox uccideva il
   resto del report. Isolato con try/catch per mailbox.
2. `Public\Get-M365OpsSharedMailboxReport.ps1` - `Get-EXOMailboxPermission`/
   `Get-EXORecipientPermission` per mailbox condivisa senza la stessa protezione gia' presente
   due righe sopra per le statistiche (`-ErrorAction SilentlyContinue`). Allineato.
3. `Public\Get-M365OpsMailboxStatistics.ps1` - `Get-EXOMailboxStatistics` per mailbox (percorso
   "tutte le mailbox", senza `-Identity`) senza `-ErrorAction SilentlyContinue`, a differenza
   delle due funzioni sorelle che gia' lo fanno (`Get-M365OpsInactiveMailboxes`,
   `Get-M365OpsMailboxUsageReport`). Allineato.
4. `Public\Get-M365OpsAppPermissionsCheck.ps1` - ciclo di risoluzione appRoles per RISORSA Graph
   (Microsoft Graph / Exchange Online / SharePoint Online / Teams Admin API, passi indipendenti)
   senza protezione per risorsa: un errore su una sola risorsa uccideva l'intera funzione,
   azzerando anche le aree di risorse gia' risolte con successo. Isolato con try/catch per
   risorsa (fallback: quella risorsa risulta "nessun accesso" invece di un errore secco).

**5° bug reale, area diversa**: `Private\Get-M365OpsMessageHeaderAnalysis.ps1` (analizzatore
locale intestazioni email/NDR, mai esercitato a fondo prima d'ora) - il nome del giorno della
settimana in un header `Received`/`Date` viene VALIDATO da .NET contro la data numerica (non
letto come testo decorativo): un giorno sbagliato (capita nel mondo reale - orologio/fuso
configurato male su un gateway, header composti a mano) fa fallire ENTRAMBI i tentativi di
parsing gia' presenti nel codice con "day of week was incorrect", diverso da tutti i casi di
tolleranza gia' gestiti (giorno omesso, fuso tra parentesi). Riprodotto dal vivo con un header
"Tue" su una data che cadeva di mercoledi'. Corretto rimuovendo il nome del giorno dal testo
PRIMA del parsing (informazione ridondante, mai necessaria per il calcolo).

**Verificato dal vivo, non solo letto**: server riavviato dopo ogni fix (poll fino a 200 su `/`),
tutti e 5 i fix testati sul tenant reale `vnsys-test` (App-only) - `Get-M365OpsMailboxDelegatesReport`
(24 righe, nessun errore), `Get-M365OpsMailboxStatistics` (25 righe), report mailbox condivise
via `/api/chat` in linguaggio naturale (7 righe), "verifica permessi app" via `/api/chat` (tutte
le aree risolte), `POST /api/analyze-headers` con header sintetico realistico (Gmail multi-hop,
SPF/DKIM/DMARC, X-Forefront-Antispam-Report, giorno-della-settimana errato) - orario correttamente
parsato/formattato e ritardo calcolato per entrambi gli hop dopo il fix, invece del testo grezzo
di prima. Nessuna regressione sul percorso normale in nessuno dei 5 casi.

**Aree riverificate senza trovare problemi**: ciclo di vita del worker isolato reattivo Exchange
(`Connect-M365OpsIsolatedModule`, `Complete-M365OpsIsolatedModuleConnect`, percorso asincrono
`Start-/Get-M365OpsIsolatedModuleConnectAsync*`) riletto per intero - gia' ben corretto e
documentato dai fix precedenti (v0.10.6 e prima), nessun problema nuovo; forwarding report, mail
flow report, litigation hold report, message trace, transport rule report, connettori partner
Intune-Exchange, stato login mailbox condivise - gia' correttamente isolati con lo stesso pattern
(molti usano gia' `-ErrorAction SilentlyContinue`/try-catch per elemento, verificato leggendoli
uno per uno); workaround OneDrive delegate access a 5 passi (dominio SharePoint, coperto
principalmente dall'agente Teams/SharePoint parallelo) - dato solo un'occhiata rapida per
l'overlap Exchange-adiacente citato nel task, nessun problema Exchange-rilevante notato.

Spedito in v0.10.7. Nessun agente di autoreview dedicato per QUESTI fix specifici (compito
dell'agente autoreview generale della maratona, se presente) - ogni fix verificato dal vivo
individualmente prima di essere considerato chiuso, come sopra.

## Esito "Stress-test funzioni Teams/SharePoint/OneDrive/report/script personalizzati, tutto il codice" (v0.10.14)

Agente COMPLETATO. Scope: creazione/gestione Team, policy Teams (meeting/messaging/app-setup/
app-permission, limite documentato "solo assegnazione, non creazione contenuto"), siti SharePoint
(creazione, membership, ereditarieta' permessi, sharing, quota), workaround OneDrive delegate
access a 5 passi, generazione report multi-sezione (xlsx/pdf), catalogo script personalizzati -
non limitato a modifiche recenti. 396 file `.ps1` di tutto il repo sintatticamente puliti
(verificato con `[System.Management.Automation.Language.Parser]::ParseFile`).

**5 bug reali trovati e corretti**, quattro della stessa famiglia "un passo fallito blocca i
passi fratelli indipendenti" gia' vista in v0.10.1/v0.10.2/v0.10.6/v0.10.7 (cercata
deliberatamente su richiesta esplicita, non trovata per caso):
1. `Public\Export-M365OpsDataReport.ps1` - il ciclo che costruisce le sezioni del PDF (grafici +
   tabella) viveva in UN SOLO try/catch attorno all'INTERO ciclo, non uno per sezione: un errore
   imprevisto in UNA sezione faceva perdere anche le sezioni PRECEDENTI gia' costruite con
   successo nello stesso giro (un report con 5 sezioni valide + 1 malformata produceva un PDF
   con ZERO sezioni, non 5 + una nota). Il percorso xlsx gemello (`Export-M365OpsReport.ps1`,
   ramo 'xlsx') aveva gia' questo isolamento per-foglio dal 17/08/2026. Isolato con try/catch
   per sezione, riprodotto dal vivo forzando un'eccezione in una sezione su tre (via un throw
   temporaneo di test in `New-M365OpsSvgChart`, poi rimosso): le altre due sezioni restano
   intatte nel PDF, solo quella rotta mostra una nota d'errore invece di far sparire tutto.
2. `Public\Remove-M365OpsOneDriveSharingRecipient.ps1` (terzo passo del workaround OneDrive) -
   la chiamata Graph DELETE per rimuovere un permesso non aveva protezione: un fallimento su UN
   elemento perdeva sia i permessi GIA' rimossi con successo nelle iterazioni precedenti (persi
   dal valore di ritorno pur essendo davvero rimossi su SharePoint) sia gli elementi restanti mai
   raggiunti. Isolato con try/catch per permesso, nuovo campo `Failed`/`FailedCount` nel risultato.
3. `Public\Get-M365OpsSharePointSitePermissions.ps1` - amministratori raccolta siti + i tre
   gruppi standard (Owners/Members/Visitors) senza isolamento reciproco: un fallimento su UNO dei
   quattro controlli perdeva anche gli altri tre gia' letti con successo. Isolato con try/catch
   per area, verificato dal vivo su un sito reale (vnsysit.sharepoint.com/sites/test): tutte e
   quattro le aree risolte correttamente (System Account + test Owners come admin, gruppi Owners/
   Members/Visitors letti singolarmente).
4. `Public\Get-M365OpsTeamsPolicies.ps1` e `Public\Get-M365OpsTeamsExternalAccessConfig.ps1` -
   stesso schema sulle chiamate `Get-CsTeams*Policy`/`Get-CsTeams*Configuration` indipendenti
   (Meeting/Calling/Messaging e Federazione/Chat ospiti/Riunioni ospiti/Chiamate ospiti). Isolato
   ciascuna nel proprio try/catch, MA preservando invariato il meccanismo di retry via isolamento
   reattivo gia' esistente (`Get-M365OpsModuleConflictHint`: se riconosce il conflitto .NET
   sezione 6.6, l'eccezione viene sempre rilanciata invece di essere degradata a nota, cosi' il
   retry esterno tramite `Connect-M365OpsIsolatedModule` continua a scattare esattamente come
   prima) - verificato dal vivo: 19 criteri Teams (10 Meeting, 5 Calling, 4 Messaging) e le 4 aree
   di accesso esterno/ospiti (federazione abilitata, chat/Giphy ospiti, video/MeetNow riunioni,
   chiamate private) risolte correttamente su vnsys-test dopo il fix, nessuna regressione.

**6° bug reale, causa diversa**: `Public\Export-M365OpsReport.ps1` (ramo 'pdf') - dopo il lancio
di Edge headless, un `Start-Sleep -Seconds 2` fisso seguito da `Test-Path` produceva un falso
negativo intermittente. **Riprodotto dal vivo** chiedendo "elenca i team del tenant e genera un
report PDF con quella lista" via `/api/chat` (percorso reale, non un test sintetico): la risposta
ha riportato "Edge non ha prodotto il file", ma il file .pdf era gia' presente su disco con la
dimensione corretta (79-84 KB) subito dopo, con timestamp coerente con la richiesta - falso
negativo confermato confrontando file e timestamp. Il processo msedge.exe avviato con `&` non
garantisce che il file sia scritto su disco al ritorno del comando, specialmente con altri
processi Edge/Chromium gia' attivi sulla macchina (plausibile in questo ambiente: strumenti di
automazione browser di altre sessioni/agenti in esecuzione in parallelo). Corretto sostituendo
l'attesa fissa con un polling fino a 20 secondi (dimensione del file stabile per due controlli
consecutivi consecutivi, invece di sperare che 2 secondi bastino sempre) - stesso principio gia'
in uso in questa maratona per il polling di riavvio del server ("allow 15-20+ seconds, multiple
poll attempts"). **Riverificato dal vivo lo stesso identico scenario dopo il fix**: PDF generato
e offerto correttamente come allegato in chat, nessun falso negativo.

**Verificato dal vivo, non solo letto**: server riavviato dopo ogni fix (poll fino a 200 su `/`),
ogni fix testato sul tenant reale `vnsys-test` (App-only) via `/api/chat` in linguaggio naturale
o chiamata diretta della funzione. Nota metodologica: il server di test e' CONDIVISO dai 5 agenti
paralleli di questa maratona - due volte una richiesta ha ricevuto una risposta con una proposta
di scrittura Intune pendente lasciata da un altro agente concorrente (non mia), cancellata con
"no" prima di procedere con i propri test, nessuna azione presa su proposte non originate dal
proprio turno.

**Aree coperte senza trovare problemi**: creazione Team/siti SharePoint, membership siti,
ereditarieta' permessi, sharing esterno, quota sito, sync App Registration SharePoint, report
utilizzo OneDrive/account inattivi (gia' correttamente isolati con try/catch per riga), invio
report via email con allegato (`Send-M365OpsReportEmail`); catalogo script personalizzati
(`Get-M365OpsCustomScriptCatalog`, caricamento in `M365Ops.psm1`) verificato dal vivo con uno
script di test deliberatamente rotto (sintassi non valida) creato accanto a quello reale gia'
presente: lo script valido (`Get-M365OpsOneDriveSharingReport`) ha continuato a caricarsi e a
funzionare, il warning ha nominato correttamente il file rotto, il catalogo lo ha segnalato
`Valid=$false` con motivo chiaro - fix gia' presente da un giro precedente, nessuna regressione,
script di test rimosso subito dopo.

Spedito in v0.10.14. Nessun agente di autoreview dedicato per QUESTI fix specifici (compito
dell'agente autoreview generale della maratona, se presente) - ogni fix verificato dal vivo
individualmente prima di essere considerato chiuso, come sopra.

## Agente "Stress-test GUI ampio, tutta l'app" — COMPLETATO (v0.10.15)

Uno dei cinque agenti avviati in parallelo dopo la correzione di rotta ("verificare TUTTO il
codice", non solo le feature appena spedite - vedi sezione sopra). Scope: l'INTERA superficie
GUI/UX (`Gui/index.html` + `Gui/Server.ps1`), tab per tab/pulsante per pulsante, non limitato a
quanto toccato di recente - inclusi flussi piu' vecchi mai ri-verificati dopo l'accumulo di
funzionalita' successive (regola #4 della maratona: "testare ogni elemento della GUI... non solo
le funzionalita' principali").

**Copertura**: 396 file `.ps1` sintatticamente puliti (`ParseFile`) prima di iniziare. Tab
Impostazioni - Motore AI (cambio provider Claude/Azure OpenAI, campi mostrati/nascosti, stato e
utilizzo), MCP/Connettori (aggiunta/rimozione server generico, non solo Lokka), Email (sender
config), Manutenzione (versione, porta, ricerca/filtri log, "Controlla aggiornamenti", canale
Stabile/Test - non toccato lo script personalizzato ne' il pulsante Riavvia oltre alle verifiche
gia' necessarie per i miei fix). CRUD profilo tenant completo (aggiungi/modifica/annulla/rimuovi)
con toggle campi AuthMode App-only/Delegata. Avvio del login Delegato a codice dispositivo (solo
il percorso di errore - completamento reale con MFA umano resta non testabile da questo ambiente
sandboxato, limite gia' noto e documentato sopra per l'isolamento reattivo). Pannello Upload (tre
slot). Banner di aggiornamento e il suo pulsante "Vedi in Manutenzione". Tastiera (Invio per
inviare in chat, verificato end-to-end con una vera risposta AI). Layout a 375px di larghezza
(header, tab Impostazioni per intero, non solo Infrastruttura gia' coperta da un giro precedente).

**3 bug reali trovati e corretti, tutti riverificati dal vivo - v0.10.15**:

1. **`POST /api/upload` (file principale/icona/CSV migrazione) - upload fallito mostrato come
   riuscito**: la rotta non aveva un proprio `try/catch` - un errore (base64 malformato, file
   troppo grande, percorso non scrivibile...) cadeva nel catch generico esterno del server, che
   risponde correttamente con `{ role: 'error' }` e HTTP 500. Il problema vero era lato client:
   `fetch()` non lancia un'eccezione JS per uno status HTTP di errore, e nessuno dei tre handler
   (file/icona/CSV - la Knowledge Base invece gia' controllava `data.ok` correttamente) verificava
   `res.ok`/`data.role` prima di questo fix - un upload fallito finiva comunque nel ramo
   "successo": l'etichetta mostrava il nome del file come se fosse stato caricato davvero, e il
   testo dell'errore appariva come un normale messaggio di sistema invece che un errore.
   Riprodotto dal vivo forzando un base64 non valido via `/api/upload` diretto (sia con `curl` sia
   eseguendo il vero handler client nel browser): prima del fix l'etichetta diventava il nome del
   file "caricato" e il messaggio appariva in stile normale; dopo il fix l'etichetta resta "Nessun
   file caricato" e il messaggio appare correttamente come errore (rosso). Corretto sia lato
   server (`try/catch` dedicato sulla rotta, stesso pattern gia' in uso in `/api/kb/upload`) sia
   lato client (controllo esplicito su tutti e tre gli handler upload). Non e' stato possibile
   testare dal vivo un file DAVVERO oversize (nessun limite esplicito di dimensione configurato
   lato server - HttpListener non ne impone uno di default) - il fix comunque copre correttamente
   qualunque causa di fallimento della rotta, oversize incluso, dato che passa tutte per lo stesso
   catch generico gia' verificato.
2. **`.settings-tabs` (le 6 schede del pannello Impostazioni) - overflow orizzontale dell'INTERA
   pagina a 375px**: stesso schema del bug header gia' corretto in v0.9.73 (nessun `flex-wrap`),
   qui pero' mai verificato prima. Misurato dal vivo: le 6 schede (551px) forzavano
   `document.body.scrollWidth` a superare la larghezza reale dello schermo - non il solito "non
   sta benissimo" accettabile per un'app dichiaratamente desktop-first, un vero overflow di
   pagina. Corretto aggiungendo `flex-wrap: wrap` alla regola, riverificato con screenshot e
   misure DOM dirette: le schede ora vanno su due righe, nessun overflow, nessun impatto sul
   layout desktop.
3. **`.profile-row` (riga di ogni profilo tenant salvato) - pulsanti "Modifica"/"✕" DAVVERO
   irraggiungibili a 375px**: stesso pattern del punto 2, ma piu' grave - misurato dal vivo che
   `getBoundingClientRect().left` del pulsante Modifica era 382px su una viewport di soli 375px
   disponibili, e l'overflow restava clippato (non scrollabile) invece di allargare la pagina: un
   profilo diverso da quello attivo diventava impossibile da modificare o rimuovere da mobile,
   nessuno scroll orizzontale lo rendeva raggiungibile. Corretto con lo stesso `flex-wrap: wrap`,
   riverificato dal vivo: entrambi i pulsanti ora dentro la viewport (right edge a 153px e 195px),
   `document.body.scrollWidth` torna a coincidere esattamente con la larghezza reale (375px).

**Aree coperte senza trovare problemi**: validazione client-side gia' corretta sul salvataggio
profilo (rifiuta App-only senza secret ne' certificato); avvio login Delegato con tenant cambiato
nel frattempo da un'altro agente concorrente (errore corretto mostrato, pulsante riabilitato -
solo piu' lento del previsto per la contesa reale sul server a singolo thread condiviso con altri
quattro agenti, non un bug); tag `<br>` dentro un contenitore `display:flex` (dubbio teorico
sollevato durante l'indagine, smentito da verifica visiva diretta - il browser lo rispetta
comunque); rendering "Documentazione" (KB) su tenant senza documenti; `checkUpdateBanner` e "Vedi
in Manutenzione" (simulato forzando `data.UpdateAvailable`, click verificato apre Impostazioni sul
tab giusto); "Controlla aggiornamenti" reale (canale Stabile, risposta corretta "sei alla versione
piu' recente").

**Non testato dal vivo in questo giro** (rischio concreto su stato condiviso con altri quattro
agenti in esecuzione sullo stesso server/tenant in parallelo, coerente con la nota di cautela
ricevuta a inizio compito): esperienza "primo avvio" a zero configurazione - verificata solo
leggendo il codice (`FIRST_RUN_TEXT`, coerente con i campi form reali, nessuna incongruenza
trovata, ma non eseguita dal vivo per non azzerare i profili tenant che altri agenti stavano
usando); completamento reale con MFA umano del login Delegato a codice dispositivo (limite gia'
noto, richiede un utente reale al tavolo, non solo l'avvio del flow che invece e' stato
verificato). Nessuna tastiera "Escape per chiudere un pannello" implementata da nessuna parte
della GUI (solo Invio-per-inviare esiste) - annotato come osservazione di design, non un bug: i
pannelli sono sezioni espandibili in pagina, non modali veri, quindi Escape non e' un requisito
scontato: proposta libera per un giro futuro se l'utente lo ritiene utile.

**Dati di test creati e rimossi entro fine turno, nessun residuo lasciato**: profilo tenant
`ZZTEST-marathon-gui-profile` (creato/modificato/rimosso), server MCP
`ZZTEST-marathon-gui-mcp` (aggiunto/rimosso), file `Uploads\app\ZZTEST-marathon-good.ps1`
(caricato per verificare il percorso di successo dell'upload, rimosso manualmente a fine test).
Nota collaterale: `$script:LoadedFilePath` lato server puo' essere rimasto per un momento puntato
a quel file poi cancellato, prima del riavvio successivo per caricare i fix - nessun impatto
oltre quella finestra (il riavvio pulisce lo stato in memoria).

Spedito in v0.10.15. Nessun agente di autoreview dedicato per QUESTI fix specifici (stesso
principio delle sessioni precedenti) - ogni fix verificato dal vivo individualmente (screenshot +
misure DOM dirette prima/dopo, chiamate dirette alla rotta `/api/upload` con payload validi e
invalidi) prima di essere considerato chiuso.
