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
- **Prioritario, trovato dal vivo il 23/08/2026 durante il setup pre-maratona**: `propose_graph_write`
  (strumento primario per le scritture Graph) su un tenant Delegato con SOLO CLI Microsoft 365
  connesso fallisce allo stesso modo scoperto per `graph_api_call` (v0.9.68, sessione delegata
  generica mancante) - ma qui NON è stato corretto un fallback verso `propose_cli_m365_command`
  come per le letture, deliberatamente: una write mal instradata ha conseguenze più serie di una
  lettura, e CLI 365 (`m365 entra user add`) potrebbe normalizzare/validare i parametri in modo
  diverso da un POST Graph diretto - va indagato con calma, non patchato al volo. Riprodotto dal
  vivo: "crea un account" su AlePiras (solo CLI365 connesso) → proposta registrata correttamente,
  esecuzione fallita con "Nessuna sessione delegata attiva per 'AlePiras'" - la diagnosi
  automatica post-fallimento ha correttamente NON inventato una correzione (buon segno, nessuna
  fabbricazione), ma il vero limite (nessun fallback su CLI365 per le scritture) resta aperto.
  Task per la maratona: valutare se/come estendere la logica di fallback letture→CLI365 (v0.9.68)
  anche alle scritture Entra-only, con test reali di entrambi i percorsi a confronto.
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

1. **Investigatore affidabilità login/popup** — (io stesso, non un agente separato, essendo
   l'indagine appena iniziata e a bassa parallelizzabilità: richiede letture di codice mirate +
   test dal vivo in sequenza) - obiettivo: capire perché il click su "Connetti" impiega molto
   prima di aprire il browser, e perché a volte non si apre affatto, su tutte le connessioni
   interessate (Graph/Exchange/Teams/SharePoint/Purview/Intune/CLI365).
2. *(altri agenti da dichiarare qui appena spinnati - copertura GUI, comandi lettura/scrittura
   per area, autoreview dei fix di questa maratona)*
