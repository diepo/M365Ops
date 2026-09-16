function Set-M365OpsCliMicrosoft365UpdateCheckTimestamp {
    <#
    .SYNOPSIS
        Registra ORA come ultimo controllo aggiornamento CLI Microsoft 365 - vedi
        Test-M365OpsCliMicrosoft365UpdateCheckDue.ps1 per il perche'. Chiamata sempre,
        indipendentemente dall'esito del controllo (trovato un aggiornamento o no) - solo un
        fallimento del controllo stesso (es. rete assente) lascia il timestamp invariato, per
        riprovare davvero al prossimo giro invece di aspettare 24h su un controllo mai riuscito.
    #>
    $path = Join-Path $script:M365OpsModuleRoot 'Config\cli-m365-last-update-check.txt'
    try {
        $configDir = Split-Path -Parent $path
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Force -Path $configDir | Out-Null }
        Set-Content -Path $path -Value (Get-Date -Format 'o') -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
