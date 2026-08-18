# M365Ops

Modulo PowerShell per automazione M365 Modern Workplace (Intune/Entra ID), multi-tenant,
con motore di ragionamento AI pluggable (Claude o Azure OpenAI).

## Principio di fondo

La logica di dominio (interpretare dati, raggruppare pattern, spiegare cause) vive nel
motore AI (`Invoke-M365OpsAgent`), **non** in regole scritte a mano nel codice. Le cmdlet
del modulo forniscono solo dati grezzi e azioni — mai interpretazione cablata.
Vedi `Get-M365OpsCompliancePatterns.ps1` come esempio di riferimento.

## Setup rapido

```powershell
Import-Module .\M365Ops.psd1

# 1. Registra un tenant (il secret NON viene mai scritto su disco da questo comando)
Set-M365OpsTenant -Name "contoso-test" -TenantId "contoso.onmicrosoft.com" `
    -ClientId "00000000-0000-0000-0000-000000000001" -SecretEnvVar "M365_CLIENT_SECRET"

# 2. Imposta il secret UNA VOLTA sul tuo PC (fuori da PowerShell/da questo modulo)
#    setx M365_CLIENT_SECRET "il-valore-dal-portale"
#    setx ANTHROPIC_API_KEY "la-tua-api-key-claude"

# 3. Attiva il tenant
Connect-M365Ops -TenantProfile "contoso-test"

# 4. Usa le cmdlet
Get-M365OpsCompliancePatterns
```

## Aggiungere un secondo tenant

```powershell
Set-M365OpsTenant -Name "cliente-x" -TenantId "clientex.onmicrosoft.com" `
    -ClientId "<app-registration-id-cliente-x>" -SecretEnvVar "M365_CLIENT_SECRET_CLIENTEX"
# setx M365_CLIENT_SECRET_CLIENTEX "..."
Connect-M365Ops -TenantProfile "cliente-x"
```

Ogni tenant ha la propria App Registration (permessi Application, client credentials —
vedi sotto) e la propria variabile d'ambiente per il secret. Nessun dato di un tenant
finisce mai nel file di configurazione dell'altro.

## Permessi Graph richiesti sull'App Registration (Application, non Delegated)

- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementApps.ReadWrite.All`
- `Group.ReadWrite.All`
- `User.Read.All`

Con **Grant admin consent** per il tenant.

## Dipendenze esterne

- Modulo `IntuneWin32App` (PowerShell Gallery) — richiesto solo da `New-M365OpsWin32App`.
  Va installato sia per PowerShell 7 che per Windows PowerShell 5.1 se userai entrambi:
  `Install-Module IntuneWin32App -Scope CurrentUser`
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
