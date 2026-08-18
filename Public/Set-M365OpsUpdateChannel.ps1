function Set-M365OpsUpdateChannel {
    <#
    .SYNOPSIS
        Imposta il canale aggiornamenti su QUESTA installazione ('Stable' o 'Testing').
        Preferenza locale (Config\update-channel.txt, escluso da git) - non ha alcun
        effetto sul repository, solo su quali Release questa copia dell'app propone.
    .NOTES
        Mode: Write
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Stable', 'Testing')] [string]$Channel
    )
    $configDir = Join-Path $script:M365OpsModuleRoot 'Config'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    Set-Content -Path (Join-Path $configDir 'update-channel.txt') -Value $Channel -Encoding UTF8 -NoNewline
    [pscustomobject]@{ Channel = $Channel }
}
