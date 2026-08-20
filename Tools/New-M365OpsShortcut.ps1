<#
    Crea (o aggiorna) un collegamento M365Ops.lnk sul Desktop dell'utente corrente, puntato
    a M365Ops.bat con l'icona Assets\M365Ops.ico. Un file .bat non puo' avere un'icona
    propria (limite di Windows: mostra sempre l'icona generica di cmd.exe/scroll) - un
    collegamento .lnk e' l'unico modo per farlo apparire con un'icona dedicata sul Desktop.

    Pensato per essere richiamato da Launch-M365Ops.ps1 al primo avvio (idempotente: se il
    collegamento esiste gia', lo aggiorna solo se punta a un M365Ops.bat diverso, altrimenti
    non tocca nulla) - Windows PowerShell 5.1 compatibile (COM WScript.Shell, nessuna
    dipendenza da PowerShell 7).
#>
param(
    [Parameter(Mandatory)] [string]$Root
)

$batPath = Join-Path $Root 'M365Ops.bat'
$iconPath = Join-Path $Root 'Assets\M365Ops.ico'
if (-not (Test-Path $batPath) -or -not (Test-Path $iconPath)) { return }

$desktop = [System.Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'M365Ops.lnk'

$needsUpdate = $true
if (Test-Path $shortcutPath) {
    try {
        $existingShell = New-Object -ComObject WScript.Shell
        $existing = $existingShell.CreateShortcut($shortcutPath)
        if ($existing.TargetPath -eq $batPath) { $needsUpdate = $false }
    } catch {}
}
if (-not $needsUpdate) { return }

try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $batPath
    $shortcut.WorkingDirectory = $Root
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Description = 'M365Ops - Automazione Microsoft 365'
    $shortcut.Save()
} catch {}
