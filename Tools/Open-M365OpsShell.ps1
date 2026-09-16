<#
    Sessione PowerShell interattiva gia' collegata al tenant attivo di M365Ops - lanciata dal
    pulsante "🖥️ PowerShell" in toolbar (Gui\Server.ps1, POST /api/open-powershell), richiesto
    esplicitamente dall'utente l'11/09/2026: "puoi aggiungere un pulsante in alto che apre
    powershell in modo che lo utente lo possa usare? il ps aperto deve essere ovviamente
    loggato seguendo le autenticazioni del tenant".

    Gira con -NoExit (vedi lo spawn in Server.ps1): dopo Connect-M365Ops resta al prompt
    interattivo, pronta per qualunque cmdlet Get-M365Ops*/Set-M365Ops* dello stesso identico
    modulo usato dalla GUI e dall'IA - stessa risoluzione di identita' (AppOnly a certificato/
    secret, o Delegato con eventuale prompt interattivo al primo comando che ne ha bisogno),
    nessuna scorciatoia o token condiviso col processo server: Connect-M365Ops imposta solo il
    CONTESTO (tenant/credenziali), le singole cmdlet si collegano da sole ai servizi che servono
    davvero (stesso modello "lazy connect" gia' in uso in tutto il resto del modulo).

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
Write-Host "Sessione PowerShell M365Ops pronta - tenant attivo: $TenantProfile" -ForegroundColor Cyan
Write-Host "Usa una qualunque cmdlet Get-M365Ops*/Set-M365Ops* di questo modulo (le stesse della chat/IA)." -ForegroundColor Cyan
Write-Host "Questa finestra si disconnette/chiude automaticamente cambiando tenant dalla GUI." -ForegroundColor DarkGray
Write-Host ""
