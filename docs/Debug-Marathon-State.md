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
