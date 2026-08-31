<#
    Lock file per impedire avvii concorrenti del server M365Ops (31/08/2026, richiesto
    esplicitamente dall'utente dopo un bug reale segnalato dal vivo: cliccare piu' volte
    l'icona "Avvia" o "Termina e riavvia" mentre un avvio precedente e' ancora in corso -
    perche' invisibile per fino a 30s durante un avvio a freddo - faceva partire PIU' server
    concorrenti, ognuno finito su una porta diversa (Server.ps1 sceglie da sola la prima porta
    libera successiva se quella di partenza e' occupata), aprendo tutte le istanze insieme nel
    browser.

    Basato su un handle di file esclusivo del sistema operativo (FileShare::None), non su un
    "controlla-poi-scrivi" a due passi (che sarebbe di nuovo una race condition tra due
    processi che controllano nello stesso istante prima che uno dei due scriva). Robusto anche
    a un processo che tiene il lock e crasha/viene killato: Windows rilascia da solo l'handle
    esclusivo quando il processo termina in QUALUNQUE modo, quindi non serve nessuna logica di
    rilevamento "lock stantio" basata su PID salvato/Get-Process - il file stesso torna
    acquisibile automaticamente.

    PS 5.1 + PS7 compatibile (nessuna sintassi PS7-only) - dot-sourcabile sia da
    Launch-M365Ops.ps1 (pwsh.exe) sia da Kill-And-Restart-M365Ops.ps1 (powershell.exe).
#>

function Lock-M365OpsStartup {
    param(
        [Parameter(Mandatory)] [string]$LockPath,
        # 0 = un solo tentativo, non attende. >0 = riprova ogni 300ms fino al timeout.
        [int]$TimeoutMs = 0
    )
    $dir = Split-Path -Parent $LockPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $deadline = (Get-Date).AddMilliseconds([Math]::Max($TimeoutMs, 0))
    while ($true) {
        try {
            $stream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("PID $PID - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
                $stream.SetLength(0)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } catch {}
            return $stream
        } catch [System.IO.IOException] {
            if ($TimeoutMs -le 0 -or (Get-Date) -ge $deadline) { return $null }
            Start-Sleep -Milliseconds 300
        }
    }
}

function Unlock-M365OpsStartup {
    param($LockHandle)
    if ($LockHandle) { try { $LockHandle.Dispose() } catch {} }
}
