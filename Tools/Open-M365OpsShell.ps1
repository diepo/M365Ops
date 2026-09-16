<#
    Sessione PowerShell interattiva gia' collegata al tenant attivo di M365Ops - lanciata dal
    pulsante "🖥️ PowerShell" in toolbar (Gui\Server.ps1, POST /api/open-powershell), richiesto
    esplicitamente dall'utente l'11/09/2026: "puoi aggiungere un pulsante in alto che apre
    powershell in modo che lo utente lo possa usare? il ps aperto deve essere ovviamente
    loggato seguendo le autenticazioni del tenant".

    Gira con -NoExit (vedi lo spawn in Server.ps1): dopo la connessione resta al prompt
    interattivo, pronta per qualunque cmdlet Get-M365Ops*/Set-M365Ops* dello stesso identico
    modulo usato dalla GUI e dall'IA - stessa risoluzione di identita' (AppOnly a certificato/
    secret, o Delegato con eventuale login interattivo, completabile qui perche' questa e' una
    finestra vera davanti all'operatore, a differenza del processo server che non puo' mai
    bloccarsi in attesa di un click umano).

    BUG REALE trovato dal vivo il 16/09/2026, STESSO giorno della prima versione di questo file:
    l'utente ha aperto la finestra e provato una cmdlet Exchange NATIVA (Get-Mailbox, non
    Get-M365OpsMailboxDetail) - "non risulta connesso... non riconosce il cmdlet". La prima
    versione chiamava SOLO Connect-M365Ops, che imposta esclusivamente il CONTESTO (tenant/
    credenziali) - le sessioni Exchange/Teams/SharePoint vengono aperte (e le loro cmdlet native
    importate) solo dentro le funzioni Get-M365Ops* stesse (Connect-M365OpsExchange ecc., lazy
    connect), MAI da una chiamata diretta a Get-Mailbox scritta a mano dall'operatore - quel
    "lazy connect" copre solo le cmdlet DI QUESTO modulo, non le cmdlet native di
    ExchangeOnlineManagement/MicrosoftTeams/PnP che l'operatore potrebbe voler usare direttamente
    in una shell vera. Corretto chiamando qui Connect-M365OpsAllConnections (la stessa funzione
    dietro il pulsante "Connetti tutto" della GUI, vedi Gui\Server.ps1/POST /api/reconnect-all) -
    stesso -OnProgress riusato qui per stampare il progresso reale passo per passo con Write-Host
    (perfetto in una console interattiva, a differenza della GUI che ha dovuto costruirsi un
    meccanismo di polling apposta) invece del solito silenzio "sembra bloccato" gia' segnalato
    una volta dall'utente proprio per questa stessa funzione lato GUI.

    "Deve seguire il tenant" (richiesta esplicita, stessa frase): questa finestra NON e' isolata
    per tenant come i sottoprocessi MCP (Connect-M365OpsMcpServer.ps1, che restano vivi apposta
    cambiando tenant) - e' intenzionalmente legata al tenant che era attivo al momento
    dell'apertura, e Server.ps1 la chiude (CloseMainWindow, poi Kill se necessario) ad ogni
    cambio tenant da GUI (POST /api/tenants/activate), esattamente come le sessioni Exchange/
    Teams/SharePoint/Compliance dentro Connect-M365Ops - lasciarla aperta lascerebbe un terminale
    autenticato sul tenant SBAGLIATO rispetto a quanto mostrato nella GUI.
#>
param(
    [Parameter(Mandatory)] [string]$ModuleRoot,
    [Parameter(Mandatory)] [string]$TenantProfile
)

$Host.UI.RawUI.WindowTitle = "M365Ops - $TenantProfile"

Import-Module (Join-Path $ModuleRoot 'M365Ops.psd1') -Force
Connect-M365Ops -TenantProfile $TenantProfile

Write-Host ""
Write-Host "Connessione al tenant '$TenantProfile' in corso - Exchange/Teams/SharePoint/Purview/Intune/MCP..." -ForegroundColor Cyan
$connectResult = Connect-M365OpsAllConnections -OnProgress { param($stage) Write-Host "  -> $stage" -ForegroundColor DarkCyan }
foreach ($r in $connectResult.Results) {
    if ($r.Ok) { Write-Host "  OK  $($r.Name)" -ForegroundColor Green }
    else { Write-Host "  ERR $($r.Name): $($r.Message)" -ForegroundColor Red }
}
if ($connectResult.Message) { Write-Host $connectResult.Message -ForegroundColor Yellow }

Write-Host ""
Write-Host "Sessione PowerShell M365Ops pronta - tenant attivo: $TenantProfile" -ForegroundColor Cyan
Write-Host "Usa una qualunque cmdlet Get-M365Ops*/Set-M365Ops*, o le cmdlet native (Get-Mailbox, Get-Team, ...) appena connesse sopra." -ForegroundColor Cyan
Write-Host "Questa finestra si disconnette/chiude automaticamente cambiando tenant dalla GUI." -ForegroundColor DarkGray
Write-Host ""
