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

    SECONDO BUG REALE, stesso giorno, trovato SUBITO dopo aver corretto il primo: l'utente si e'
    connesso a Exchange delegato dalla GUI ("Accedi con il mio utente"), poi ha aperto QUESTA
    finestra - Connect-M365OpsAllConnections ha comunque riportato Exchange Online come "richiede
    un nuovo login interattivo", nonostante fosse GIA' connesso un attimo prima. Non e' un
    controllo che sbaglia: e' un limite architetturale reale. Questa finestra e' un PROCESSO
    (pwsh.exe) SEPARATO dal processo server della GUI - ciascuno ha la propria copia isolata
    dello stato del modulo ($script:M365OpsExchangeConnected ecc.), e soprattutto la SESSIONE
    Exchange/Teams/SharePoint vera (un oggetto .NET/PSSession vivo in memoria) non puo' in alcun
    modo essere condivisa tra due processi diversi solo perche' entrambi hanno importato lo
    stesso modulo - va sempre stabilita da capo in OGNI processo che la usa. La domanda giusta
    dell'utente ("non fa a prendersi la sessione gia' connessa?") ha quindi risposta NO per
    costruzione, non per un bug risolvibile lato codice.
    Corretto rendendo il percorso in avanti chiaro invece di lasciare l'utente a chiedersi perche':
    per ogni area Delegata NON ancora connessa IN QUESTO PROCESSO, stampa qui sotto il comando
    -AllowInteractive pronto da incollare - completabile SUBITO in questa stessa finestra (mostra
    un vero device code, l'operatore lo completa nel browser che preferisce), perche' bloccare
    QUESTA console mentre aspetta e' del tutto accettabile (l'utente la sta guardando apposta),
    a differenza del processo server della GUI che non puo' mai permetterselo (thread singolo,
    bloccherebbe tutti). Nessun login viene avviato automaticamente all'apertura (5 device code
    di fila non richiesti sarebbero fastidiosi) - l'operatore sceglie quali aree gli servono
    davvero in QUESTA sessione.

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

# Su Delegato, per ciascuna area NON connessa IN QUESTO PROCESSO (vedi .SYNOPSIS per il perche'
# una sessione gia' attiva nel processo server non e' mai visibile qui), il comando pronto da
# incollare per completarla subito, qui, con un vero login interattivo - questa finestra puo'
# permettersi di bloccarsi in attesa (l'operatore la sta guardando), a differenza del server.
if ($connectResult.AuthMode -eq 'Delegated') {
    $interactiveCmdByArea = [ordered]@{
        'Exchange Online'                  = 'Connect-M365OpsExchange -AllowInteractive'
        'Microsoft Teams'                  = 'Connect-M365OpsTeams -AllowInteractive'
        'SharePoint'                        = 'Connect-M365OpsSharePoint -AllowInteractive'
        'Security & Compliance (Purview)'  = 'Connect-M365OpsCompliance -AllowInteractive'
        'Intune'                            = 'Connect-M365OpsIntune -AllowInteractive'
    }
    $missing = @($connectResult.Results | Where-Object { -not $_.Ok -and $interactiveCmdByArea.Contains($_.Name) })
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "Per usare le cmdlet native di un'area sopra segnata ERR, in QUESTA finestra (login interattivo, un vero device code da completare nel browser):" -ForegroundColor Yellow
        foreach ($r in $missing) { Write-Host "  $($interactiveCmdByArea[$r.Name])" -ForegroundColor White }
    }
}

Write-Host ""
Write-Host "Sessione PowerShell M365Ops pronta - tenant attivo: $TenantProfile" -ForegroundColor Cyan
Write-Host "Usa una qualunque cmdlet Get-M365Ops*/Set-M365Ops*, o le cmdlet native (Get-Mailbox, Get-Team, ...) appena connesse sopra." -ForegroundColor Cyan
Write-Host "Questa finestra si disconnette/chiude automaticamente cambiando tenant dalla GUI." -ForegroundColor DarkGray
Write-Host ""
