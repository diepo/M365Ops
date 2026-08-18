function Invoke-M365OpsApplyFix {
    <#
    .SYNOPSIS
        Applica la correzione proposta da Invoke-M365OpsErrorTriage (gia' verificata con
        Test-M365OpsFixApplicable), con backup automatico del file originale.
    .NOTES
        Non tenta un hot-reload della funzione modificata: dot-sorgente da dentro una funzione
        del modulo aggiorna solo lo scope locale della funzione stessa, non quello del modulo
        (limite di scoping di PowerShell) - un tentativo di "ricarica senza riavvio" qui
        sarebbe silenziosamente inefficace, e servire codice vecchio dopo aver detto
        all'utente che e' stato corretto sarebbe peggio che chiedere un riavvio esplicito.
        Riavvia il server (tab Manutenzione) dopo l'applicazione per caricare la correzione.
    #>
    param($Triage, [string]$ModuleRoot)

    $fullPath = Join-Path $ModuleRoot $Triage.fix.file
    $backupPath = "$fullPath.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $fullPath $backupPath

    $content = Get-Content $fullPath -Raw
    $newContent = $content.Replace($Triage.fix.search, $Triage.fix.replace)
    Set-Content -Path $fullPath -Value $newContent -Encoding UTF8 -NoNewline

    return "Corretto $($Triage.fix.file) (backup: $(Split-Path -Leaf $backupPath)). Riavvia il server (tab Manutenzione -> Riavvia) per caricare la correzione - nessuna modifica di codice prende effetto senza ricaricare il modulo."
}
