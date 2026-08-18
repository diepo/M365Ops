# Scripts\Custom — script personalizzati usabili dall'AI

Questa cartella è pensata per gli script "home made" scritti per casi d'uso concreti di
**questo** tenant/cliente — es. estrazione permessi OneDrive/SharePoint, un report ad hoc,
un'integrazione specifica — che non fanno parte del modulo core (`Public\`) ma che vuoi
comunque richiamabili dall'assistente in chat, esattamente come le cmdlet ufficiali.

## Come diventano usabili

Non serve modificare nessun file del modulo. Basta:

1. Copiare `_TEMPLATE.ps1`, rinominarlo con il nome della funzione che definisce (es.
   `Get-M365OpsOneDriveSharingReport.ps1` per una funzione `Get-M365OpsOneDriveSharingReport`).
2. Scriverci dentro la funzione, rispettando la convenzione sotto.
3. Riavviare il server (tab **Manutenzione → Riavvia**) — i file vengono caricati all'avvio
   del modulo, non serve altro.

Da quel momento lo script compare nel catalogo (`Get-M365OpsCustomScriptCatalog`) e l'AI lo
vede tra gli strumenti disponibili al prossimo messaggio in chat.

## Convenzione obbligatoria

| Requisito | Perché |
|---|---|
| **Un file = una funzione**, nome file = nome funzione | Stessa convenzione di `Public\` — permette la scoperta automatica senza registrazione manuale. |
| Blocco di help PowerShell (`<# .SYNOPSIS ... #>`) | È l'UNICA descrizione che l'AI riceve per decidere se/come usare lo script. |
| `.SYNOPSIS` in una riga, **specifico** | Vedi checklist sotto — una riga vaga porta l'AI a usarlo male o a ignorarlo. |
| `.PARAMETER <nome>` per ogni parametro | L'AI lo usa per capire cosa passare (formato atteso: UPN, GUID, nome esatto...). |
| `.NOTES` con **`Mode: ReadOnly`** oppure **`Mode: Write`** | **Obbligatorio.** Determina se l'AI può eseguirlo subito (ReadOnly) o solo proporlo, mai eseguirlo senza conferma umana esplicita (Write) — stesso principio non negoziabile di ogni altra scrittura in questo modulo. Senza questo tag lo script viene **ignorato**, mai esposto all'AI: meglio uno script silenziosamente non disponibile che uno con natura ambigua eseguito per errore. |
| Nessun input interattivo (`Read-Host`, popup) | Deve essere una funzione pura: parametri in ingresso, oggetti PowerShell in uscita. |
| Usa le funzioni di accesso dati **già esistenti** del modulo | Mai gestire token/credenziali proprie. Usa `Invoke-M365OpsGraphRequest` per Graph, `Connect-M365OpsExchange` + cmdlet native per Exchange Online. Così lo script funziona automaticamente sia sui tenant **AppOnly** (client credentials) sia **Delegated** (login utente + MFA, sezione 10 della guida) — non deve mai assumere quale delle due modalità è attiva. |
| Consulta Microsoft Learn per i parametri, mai a memoria | Prima di scrivere una chiamata a una cmdlet Exchange/Graph nativa con parametri poco comuni, verifica il nome/formato esatto con `Invoke-M365OpsLookupMsDocs -Topic "Nome-Cmdlet"` — non indovinare un parametro plausibile-ma-forse-sbagliato. Vale anche per chi/cosa corregge lo script dopo un errore (sezione "Se uno script fallisce" sotto). |

## Checklist per un buon `.SYNOPSIS`

Scrivi una riga che risponda a tutte queste domande, non solo "cosa fa" in astratto:

1. **Quale dato specifico restituisce o quale azione specifica compie** — non "esegue una query su SharePoint", ma "elenca i link di condivisione pubblici attivi su OneDrive, con proprietario e data".
2. **Permessi/scope non standard richiesti**, se ce ne sono — es. `Sites.Read.All` non è tra i permessi Graph configurati di default (sezione 4.2 della guida): se lo script ne ha bisogno, va detto qui, così l'operatore lo sa *prima* di lanciarlo e non scopre un 403 a metà.
3. **Per gli script `Mode: Write`**: quali effetti reali ha (cosa crea/modifica/elimina) — l'AI userà questo testo, quasi alla lettera, per spiegare la proposta all'utente in chat prima della conferma. Vago qui significa una proposta vaga in chat.
4. **Forma dei dati restituiti**, se non ovvia — es. "oggetti con SiteUrl, User, Role" aiuta l'AI a incatenare più chiamate.

## Se uno script fallisce

Non blocca il resto dell'app. In lettura, l'errore torna all'AI che prova a diagnosticarlo
(stesso motore di `Invoke-M365OpsErrorTriage` usato per le scritture confermate) e, se
individua una correzione precisa, la propone in chat con lo stesso flusso *proponi → conferma
→ applica* — mai una riscrittura automatica senza conferma. Le correzioni proposte devono
restare compatibili con entrambe le modalità di autenticazione, per lo stesso motivo del punto
sopra sull'accesso ai dati.

## File non caricati

Qualunque file il cui nome inizia con `_` (come questo `_TEMPLATE.ps1`) viene ignorato dallo
scanner — usali per esempi o bozze non ancora pronte.
