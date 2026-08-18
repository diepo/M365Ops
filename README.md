# M365Ops

Assistente AI per l'amministrazione di Microsoft 365 (Entra ID/Intune, Exchange Online,
SharePoint/OneDrive, Teams, Purview) — si usa interamente da una webapp locale in
linguaggio naturale, multi-tenant, con motore AI pluggable (Claude o Azure OpenAI). Sotto
il cofano è un modulo PowerShell, ma non serve scrivere comandi per usarlo: si scarica e
si avvia con un doppio clic (vedi sotto).

## Principio di fondo

La logica di dominio (interpretare dati, raggruppare pattern, spiegare cause) vive nel
motore AI (`Invoke-M365OpsAgent`), **non** in regole scritte a mano nel codice. Le cmdlet
del modulo forniscono solo dati grezzi e azioni — mai interpretazione cablata.
Vedi `Get-M365OpsCompliancePatterns.ps1` come esempio di riferimento.

## Setup rapido

Tutto passa dalla webapp — non serve scrivere nessun comando ne' installare nulla a mano:

1. Scarica/clona il repository.
2. Doppio clic su `M365Ops.bat`. Installa da solo PowerShell 7 se manca (tramite winget),
   poi avvia il server locale e apre il browser.
3. Alla prima apertura, se mancano Node.js o Microsoft Edge la webapp mostra un banner con
   un pulsante "Installa automaticamente" (anche questi via winget, un clic e basta). Tutti
   gli altri moduli PowerShell richiesti (Exchange Online, SharePoint/PnP, Teams, Excel,
   PdfLexer, IntuneWin32App) si installano da soli al primo utilizzo della funzione
   corrispondente — non serve alcun `Install-Module` manuale.
4. Nella pagina che si apre, **⚙ Impostazioni tenant** → compila "Aggiungi/aggiorna
   profilo" (nome, Tenant ID, modalita' di autenticazione, Client ID e secret se App-only).
   Il secret viene salvato SOLO nella variabile d'ambiente del tuo utente Windows, mai su
   disco.
5. Tab **Motore AI** → scegli il provider (Claude o Azure OpenAI) e incolla la API key —
   anche questa finisce solo in una variabile d'ambiente, mai su disco.
6. Torna alla chat e usa l'assistente in linguaggio naturale.

## Aggiungere un secondo tenant

Stesso modulo "Aggiungi/aggiorna profilo" nel tab Tenant, con un nome profilo diverso —
appare subito nell'elenco dei profili salvati, con un pulsante per attivarlo. Ogni tenant
ha la propria App Registration (permessi Application, client credentials — vedi sotto) e
la propria variabile d'ambiente per il secret. Nessun dato di un tenant finisce mai nel
profilo di un altro.

## Permessi Graph richiesti sull'App Registration (Application, non Delegated)

- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementApps.ReadWrite.All`
- `Group.ReadWrite.All`
- `User.Read.All`

Con **Grant admin consent** per il tenant.

## Dipendenze esterne

- Modulo `IntuneWin32App` (PowerShell Gallery) — richiesto solo da `New-M365OpsWin32App`,
  si installa da solo al primo uso (`Install-Module -Scope CurrentUser`), nessun passo
  manuale necessario.
  (Nota: `Connect-MSIntuneGraph` di questo modulo ha un bug di compatibilita' con PowerShell 7
  nel flusso device-code — non rilevante qui perche' usiamo client credentials, ma se
  emergono errori strani con `New-M365OpsWin32App`, prova a lanciarlo da `powershell.exe`
  invece di `pwsh`.)
- `Tools\IntuneWinAppUtil.exe` — incluso nel modulo, scaricato da
  github.com/microsoft/Microsoft-Win32-Content-Prep-Tool.

## Motore AI — provider disponibili

- **Claude** (default): richiede `ANTHROPIC_API_KEY`.
- **AzureOpenAI**: richiede `AZURE_OPENAI_KEY`, `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`.
  E' il provider da usare se si vuole restare nell'ecosistema Microsoft — M365 Copilot in
  se' non ha un'API generica richiamabile per questo scopo, Azure OpenAI si'.

## Convenzioni per chi (o cosa) estende questo modulo

Queste sono le regole seguite finora — un agente AI che scrive nuove cmdlet dovrebbe rispettarle:

1. **Ogni cmdlet di scrittura crea SENZA assegnare/attivare per default.** L'assegnazione o
   attivazione e' sempre un passo separato ed esplicito (vedi `Set-M365OpsAppAssignment`).
2. **Zero credenziali in chiaro nei file.** Solo nomi di variabili d'ambiente (vedi
   `Get-M365OpsSecret`, `Config\tenants.json`).
3. **Le cmdlet di lettura non interpretano mai i dati** — restituiscono JSON/oggetti grezzi.
   L'interpretazione passa sempre da `Invoke-M365OpsAgent`.
4. **Mai eseguire un file scaricato o fornito dall'utente** per "testarlo" — solo ispezione
   passiva dei metadati (vedi `Get-M365OpsInstallerInsight`).
5. **Nuove cmdlet di scrittura vanno proposte e confermate da un umano prima di essere
   usate contro un tenant reale** — anche se scritte da un agente AI invece che a mano.
6. **Mai scrivere o correggere una chiamata a una cmdlet Exchange/Graph nativa a memoria.**
   Prima di aggiungere/proporre un parametro, consulta la documentazione reale e aggiornata
   con `Invoke-M365OpsLookupMsDocs -Topic "Nome-Cmdlet"` (o il tool AI `lookup_ms_docs` in
   chat) — la conoscenza pregressa del modello sui parametri disponibili puo' essere
   incompleta o superata, la pagina Microsoft Learn no. Ogni cmdlet di scrittura del modulo
   accetta un `-ExtraParams` generico proprio per questo: passare qualunque parametro nativo
   verificato, non solo quelli gia' previsti esplicitamente.
