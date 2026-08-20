<#
    Crea (o aggiorna) due collegamenti sul Desktop dell'utente corrente, entrambi con l'icona
    Assets\M365Ops.ico: M365Ops.lnk (avvio normale, punta a M365Ops.bat) e
    "M365Ops - Termina e riavvia.lnk" (punta a Kill-And-Restart-M365Ops.bat, per quando il
    server e' bloccato e va terminato/riavviato da fuori - 22/08/2026, richiesto
    esplicitamente dall'utente dopo aver dovuto usare Task Manager a mano durante un blocco
    Teams/WAM). Un file .bat non puo' avere un'icona propria (limite di Windows: mostra
    sempre l'icona generica di cmd.exe/scroll) - un collegamento .lnk e' l'unico modo per
    farli apparire con un'icona dedicata sul Desktop.

    Pensato per essere richiamato da Launch-M365Ops.ps1 al primo avvio (idempotente per
    ENTRAMBI i collegamenti: se esistono gia' e puntano gia' al file giusto, non li tocca) -
    Windows PowerShell 5.1 compatibile (COM WScript.Shell, nessuna dipendenza da PowerShell 7).
#>
param(
    [Parameter(Mandatory)] [string]$Root
)

function New-M365OpsDesktopShortcut {
    param(
        [string]$TargetPath,
        [string]$IconPath,
        [string]$ShortcutName,
        [string]$Description,
        [string]$WorkingDirectory
    )
    if (-not (Test-Path $TargetPath) -or -not (Test-Path $IconPath)) { return }

    $desktop = [System.Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop "$ShortcutName.lnk"

    $needsUpdate = $true
    if (Test-Path $shortcutPath) {
        try {
            $existingShell = New-Object -ComObject WScript.Shell
            $existing = $existingShell.CreateShortcut($shortcutPath)
            if ($existing.TargetPath -eq $TargetPath) { $needsUpdate = $false }
        } catch {}
    }
    if (-not $needsUpdate) { return }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.IconLocation = "$IconPath,0"
        $shortcut.Description = $Description
        $shortcut.Save()
    } catch {}
}

$iconPath = Join-Path $Root 'Assets\M365Ops.ico'

New-M365OpsDesktopShortcut -TargetPath (Join-Path $Root 'M365Ops.bat') -IconPath $iconPath `
    -ShortcutName 'M365Ops' -Description 'M365Ops - Automazione Microsoft 365' -WorkingDirectory $Root

New-M365OpsDesktopShortcut -TargetPath (Join-Path $Root 'Kill-And-Restart-M365Ops.bat') -IconPath $iconPath `
    -ShortcutName 'M365Ops - Termina e riavvia' `
    -Description 'M365Ops - Termina il server (anche se bloccato) e lo riavvia. Usa solo se il server non risponde piu.' `
    -WorkingDirectory $Root
