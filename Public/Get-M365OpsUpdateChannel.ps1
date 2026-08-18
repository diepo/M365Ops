function Get-M365OpsUpdateChannel {
    <#
    .SYNOPSIS
        Legge il canale aggiornamenti scelto su QUESTA installazione ('Stable' o 'Testing',
        default 'Stable' se non ancora impostato). Preferenza locale, mai nel repository
        (vedi Config\update-channel.txt, escluso da git).
    .NOTES
        Mode: ReadOnly
    #>
    $path = Join-Path $script:M365OpsModuleRoot 'Config\update-channel.txt'
    if (Test-Path $path) {
        $value = (Get-Content $path -Raw -ErrorAction SilentlyContinue).Trim()
        if ($value -in @('Stable', 'Testing')) { return $value }
    }
    'Stable'
}
