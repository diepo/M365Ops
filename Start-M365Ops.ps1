param(
    [string]$TenantProfile = "contoso-test"
)

Import-Module (Join-Path $PSScriptRoot 'M365Ops.psd1') -Force

# Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore): su un'installazione DAVVERO
# pulita (nessun Config\tenants.json, nessun profilo salvato) Connect-M365Ops lancia
# un'eccezione ("Nessun profilo salvato. Usa prima Set-M365OpsTenant.") - Gui\Server.ps1 ha
# gia' questo stesso identico caso protetto con un try/catch (commento del 22/08/2026 li',
# stessa causa: un crash immediato invece di un messaggio chiaro), ma questo script - il
# punto di ingresso console del modulo, elencato esplicitamente accanto alla GUI - non era
# mai stato corretto allo stesso modo: chi lo esegue per primo su un PC pulito vede solo
# un'eccezione PowerShell grezza invece di sapere cosa fare dopo.
try {
    Connect-M365Ops -TenantProfile $TenantProfile
    Write-Host "`nPronto. Esempi:" -ForegroundColor Cyan
    Write-Host "  Get-M365OpsManagedDevices"
    Write-Host "  Get-M365OpsCompliancePatterns"
    Write-Host "  Get-Command -Module M365Ops   # elenco completo cmdlet"
} catch {
    Write-Host "`nNessun tenant attivo ancora: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Configura un profilo prima, ad esempio:" -ForegroundColor Cyan
    Write-Host "  Set-M365OpsTenant -Name 'nome-profilo' -TenantId '...' -ClientId '...' -SecretEnvVar 'NOME_VARIABILE_AMBIENTE'"
    Write-Host "Poi richiama Connect-M365Ops -TenantProfile 'nome-profilo' (o rilancia questo script con -TenantProfile)."
    Write-Host "In alternativa, la GUI (M365Ops.bat) guida l'intero setup passo per passo, incluso su un PC senza nessun profilo."
}
