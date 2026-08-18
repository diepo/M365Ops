function Disconnect-M365OpsLokka {
    <#
    .SYNOPSIS
        Ferma il sottoprocesso Lokka, se attivo.
    #>
    if ($script:M365OpsLokkaProcess -and -not $script:M365OpsLokkaProcess.HasExited) {
        $script:M365OpsLokkaProcess.Kill()
        Write-Host "Lokka fermato." -ForegroundColor Yellow
    }
    $script:M365OpsLokkaProcess = $null
    $script:M365OpsLokkaTools = $null
}
