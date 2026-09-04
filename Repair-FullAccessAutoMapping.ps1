<#
    Script LOCALE interattivo (da lanciare direttamente in un terminale, non tramite la
    chat IA) - richiesto esplicitamente dall'utente il 31/08/2026: individua i permessi
    FullAccess assegnati a GRUPPI su un elenco di mailbox, li esplode nei membri e assegna
    a ciascuno un accesso DIRETTO con AutoMapping esplicito (limite reale di Exchange: un
    grant a un gruppo non abilita mai l'AutoMapping per i suoi membri - vedi il commento in
    Get-M365OpsFullAccessAutoMapPlan.ps1 per il dettaglio completo).

    Perche' uno script separato e non un'azione proposta in chat: il meccanismo di
    conferma della chat (propose_exo_write) accetta UNA sola proposta di scrittura per
    risposta - su un elenco di 20+ mailbox con gruppi da esplodere questo significherebbe
    decine o centinaia di conferme "si" in sequenza. Qui invece l'intero piano viene
    calcolato PRIMA, mostrato per intero, e confermato una volta sola.

    Uso:
      .\Repair-FullAccessAutoMapping.ps1 -TenantProfile vnsys-test
      .\Repair-FullAccessAutoMapping.ps1 -TenantProfile vnsys-test -CsvPath .\shared.csv
      (il CSV deve avere una colonna "Identity" con indirizzo email o UPN di ogni mailbox -
      senza -CsvPath vengono analizzate TUTTE le mailbox condivise del tenant attivo)
#>
param(
    [Parameter(Mandatory)] [string]$TenantProfile,
    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'M365Ops.psd1') -Force
Connect-M365Ops -TenantProfile $TenantProfile

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) { throw "File CSV non trovato: $CsvPath" }
    $rows = Import-Csv -Path $CsvPath
    if (-not ($rows | Get-Member -Name Identity -ErrorAction SilentlyContinue)) {
        throw "Il CSV deve avere una colonna intestata 'Identity' (indirizzo email o UPN di ogni mailbox)."
    }
    $identities = @($rows | Select-Object -ExpandProperty Identity | Where-Object { $_ })
    Write-Host "Mailbox da analizzare (da CSV): $($identities.Count)" -ForegroundColor Cyan
} else {
    Write-Host "Nessun -CsvPath specificato: analizzo TUTTE le mailbox condivise del tenant '$TenantProfile'..." -ForegroundColor Cyan
    $identities = @(Get-M365OpsSharedMailboxes | Select-Object -ExpandProperty PrimarySmtpAddress)
    Write-Host "Mailbox condivise trovate: $($identities.Count)" -ForegroundColor Cyan
}

if ($identities.Count -eq 0) {
    Write-Host "Nessuna mailbox da analizzare - fine." -ForegroundColor Yellow
    return
}

Write-Host "`nAnalisi permessi FullAccess in corso (puo' richiedere qualche minuto su elenchi grandi)..." -ForegroundColor Cyan
$plan = Get-M365OpsFullAccessAutoMapPlan -Identities $identities

Write-Host "`n=== RIEPILOGO PIANO ===" -ForegroundColor Cyan
$plan.Summary | Format-List

if ($plan.Errors.Count -gt 0) {
    Write-Host "`n=== ERRORI DI LETTURA (non bloccanti, mailbox/gruppi saltati) ===" -ForegroundColor Yellow
    $plan.Errors | Format-Table Mailbox, Stage, Group, Error -AutoSize -Wrap
}

if ($plan.Actions.Count -eq 0) {
    Write-Host "`nNessuna azione necessaria - tutti i grant FullAccess via gruppo risultano gia' senza sovrapposizioni dirette da correggere, o nessun grant a gruppi trovato." -ForegroundColor Green
    return
}

Write-Host "`n=== AZIONI PREVISTE ($($plan.Actions.Count)) ===" -ForegroundColor Cyan
$plan.Actions | Format-Table Mailbox, User, SourceGroup, NeedsRevoke -AutoSize

Write-Host "`nNOTA: il grant FullAccess sul GRUPPO non viene rimosso (resta per la gestione futura dei nuovi membri) - viene solo AGGIUNTO un grant diretto con AutoMapping esplicito per ogni membro attuale. Un membro aggiunto al gruppo in futuro non avra' l'AutoMapping finche' questo script non viene rieseguito." -ForegroundColor DarkYellow

$confirm = Read-Host "`nProcedere con queste $($plan.Actions.Count) azioni? (si/no)"
if ($confirm -ne 'si') {
    Write-Host "Annullato - nessuna modifica effettuata." -ForegroundColor Yellow
    return
}

Write-Host "`nEsecuzione in corso..." -ForegroundColor Cyan
$results = @(Invoke-M365OpsFullAccessAutoMapPlan -Actions $plan.Actions)

$failed = @($results | Where-Object { $_.Error })
$succeeded = $results.Count - $failed.Count

Write-Host "`n=== RISULTATO ===" -ForegroundColor Cyan
Write-Host "Completate con successo: $succeeded/$($results.Count)" -ForegroundColor Green
if ($failed.Count -gt 0) {
    Write-Host "Fallite: $($failed.Count)" -ForegroundColor Red
    $failed | Format-Table Mailbox, User, SourceGroup, Error -AutoSize -Wrap
}
Write-Host "`nDettaglio completo in Logs\m365ops-$(Get-Date -Format 'yyyyMMdd').log" -ForegroundColor DarkGray
