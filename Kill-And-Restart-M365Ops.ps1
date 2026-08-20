<#
    Termina forzatamente il processo del server M365Ops (anche se bloccato/non risponde a
    nessuna richiesta HTTP) e lo riavvia da M365Ops.bat - pensato per essere lanciato da
    fuori, quando il server e' congelato e non puo' aiutarsi da solo (un pulsante DENTRO la
    pagina web non funzionerebbe in questo caso: se il server e' bloccato, non puo' nemmeno
    ricevere/processare il click sul proprio pulsante - stesso motivo per cui, durante un
    blocco reale, anche il tab Log smette di rispondere).

    Richiesto esplicitamente dall'utente il 22/08/2026 dopo aver dovuto chiudere a mano
    pwsh.exe da Task Manager durante il blocco Teams/WAM (poi risolto in v0.9.35, ma questo
    resta uno strumento utile per qualunque futuro blocco imprevisto).

    Windows PowerShell 5.1 compatibile (non richiede che pwsh.exe funzioni - e' proprio
    pwsh.exe il processo che questo script deve poter terminare anche se e' lui stesso
    a essere bloccato).

    Termina SOLO i processi pwsh.exe che stanno eseguendo Gui\Server.ps1 DI QUESTA
    installazione specifica (percorso della cartella confrontato esplicitamente) - mai
    "tutti i pwsh.exe di sistema", che potrebbero appartenere a tutt'altro.
#>
$root = $PSScriptRoot
$serverScriptPath = (Join-Path $root 'Gui\Server.ps1')

Write-Host "M365Ops - Termina e riavvia" -ForegroundColor Cyan
Write-Host "Cerco processi del server bloccato..."

$killed = 0
try {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction Stop
    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine.Contains($serverScriptPath)) {
            Write-Host "Termino processo PID $($p.ProcessId)..." -ForegroundColor Yellow
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                $killed++
            } catch {
                Write-Host "Impossibile terminare PID $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "Errore cercando i processi: $($_.Exception.Message)" -ForegroundColor Red
}

if ($killed -eq 0) {
    Write-Host "Nessun processo server trovato in esecuzione (forse era gia' fermo)." -ForegroundColor Yellow
} else {
    Write-Host "$killed processo(i) terminato(i)." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

Write-Host "Riavvio M365Ops..."
Start-Process -FilePath (Join-Path $root 'M365Ops.bat') -WorkingDirectory $root
Write-Host "Fatto - il browser si aprira' automaticamente tra pochi secondi." -ForegroundColor Green
Start-Sleep -Seconds 3
