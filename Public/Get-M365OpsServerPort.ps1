function Get-M365OpsServerPort {
    <#
    .SYNOPSIS
        Legge la porta preferita per il server web (Config\server-port.txt), 8743 se non
        ancora impostata. E' solo la porta DI PARTENZA che si prova per prima ad ogni avvio
        completo dell'app (M365Ops.bat) - se occupata da un altro programma, Server.ps1
        sceglie da solo la prima libera successiva (vedi sezione 3 della guida) e quella
        reale, non questa preferenza, resta valida per tutta la sessione anche attraverso un
        "Riavvia server" dalla GUI.
    .NOTES
        Mode: ReadOnly
    #>
    $path = Join-Path $script:M365OpsModuleRoot 'Config\server-port.txt'
    if (Test-Path $path) {
        $value = (Get-Content $path -Raw -ErrorAction SilentlyContinue).Trim()
        if ($value -match '^\d+$' -and [int]$value -ge 1024 -and [int]$value -le 65535) { return [int]$value }
    }
    8743
}
