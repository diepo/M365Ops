function Write-M365OpsWriteLog {
    <#
    .SYNOPSIS
        Scrive una riga in Logs\writes-YYYYMMDD.log (append, un file al giorno, SEPARATO dal
        log generale Logs\m365ops-YYYYMMDD.log) - storico dedicato SOLO alle azioni che
        modificano qualcosa sul tenant (scritture confermate dall'utente), con sorgente
        (Lokka/CLI Microsoft 365/moduli interni/script personalizzato) e comando esatto
        eseguito per ciascuna. Richiesto esplicitamente dall'utente il 27/08/2026: "una
        finestra di log/file di log separata per mettere solo i comandi che eseguono write
        su settings" - separato dal log generale (che macina anche letture, errori AI,
        eventi di sistema) apposta per rendere immediato un controllo "cosa ha modificato
        davvero questa sessione" senza dover filtrare centinaia di righe di rumore.

        Nome file "writes-*" (non "m365ops-writes-*"): deliberatamente FUORI dal pattern
        glob "m365ops-*.log" gia' usato da Get-M365OpsLogHistory per il log generale - se
        avesse iniziato per "m365ops-" i due log si sarebbero mescolati nelle ricerche
        esistenti (bug evitato in fase di progettazione, non trovato dopo).

        Stesso formato a 4 colonne tab-separated del log generale (Timestamp, Level, Tenant,
        Message) cosi' Get-M365OpsLogHistory puo' leggere ENTRAMBI i log con lo stesso
        codice, passando solo un prefisso di file diverso (-LogFilePrefix 'writes') - nessun
        parser duplicato. Level riusa la stessa semantica gia' esistente: 'Info' per una
        scrittura riuscita, 'Error' per una fallita (cosi' anche il filtro "Tutti i livelli/
        Info/Warn/Error" gia' presente in GUI funziona su questo log senza modifiche).
        Non lancia mai eccezioni, stesso principio di Write-M365OpsLog.
    .PARAMETER Source
        Etichetta della sorgente reale (vedi Get-M365OpsWriteActionSourceLabel) - es. "Lokka
        (MCP)", "CLI Microsoft 365 (MCP)", "moduli PowerShell interni di M365Ops".
    .PARAMETER Command
        Rappresentazione leggibile ESATTA di cosa e' stato eseguito (vedi
        Format-M365OpsCommandLine per i casi cmdlet+parametri, o costruita a mano per
        Graph/CLI Microsoft 365 - es. "POST /groups {...}" o "m365 spo site set ...").
    .PARAMETER Outcome
        'OK' se la scrittura e' riuscita, 'FAIL' se e' fallita (mappato su Level Info/Error).
    .PARAMETER Detail
        Testo libero opzionale - per un fallimento, il messaggio d'errore reale.
    #>
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [ValidateSet('OK', 'FAIL')] [string]$Outcome,
        [string]$Detail
    )
    try {
        $logDir = Join-Path $script:M365OpsModuleRoot 'Logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        $logFile = Join-Path $logDir "writes-$(Get-Date -Format 'yyyyMMdd').log"
        $tenant = if ($script:M365OpsContext) { "$($script:M365OpsContext.Name)[$($script:M365OpsContext.AuthMode)]" } else { '(nessun tenant)' }
        $level = if ($Outcome -eq 'OK') { 'Info' } else { 'Error' }
        $message = "[$Outcome] Fonte: $Source | Comando: $Command"
        if ($Detail) { $message += " | Dettaglio: $Detail" }
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t[$level]`t$tenant`t$message"
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    }
    catch { }
}
