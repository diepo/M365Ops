function Set-M365OpsServerPort {
    <#
    .SYNOPSIS
        Imposta la porta preferita per il server web (Config\server-port.txt). Ha effetto
        SOLO al prossimo avvio completo dell'app (chiudi tutto e rilancia M365Ops.bat) - un
        "Riavvia server" dalla GUI resta volutamente sulla porta gia' in uso in questa
        sessione, per non lasciare la scheda del browser gia' aperta puntata su un indirizzo
        morto senza nessun modo di segnalarglielo.
    .NOTES
        Mode: Write
    #>
    param(
        [Parameter(Mandatory)] [ValidateRange(1024, 65535)] [int]$Port
    )
    $configDir = Join-Path $script:M365OpsModuleRoot 'Config'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    Set-Content -Path (Join-Path $configDir 'server-port.txt') -Value $Port -Encoding UTF8 -NoNewline
    [pscustomobject]@{ Port = $Port }
}
