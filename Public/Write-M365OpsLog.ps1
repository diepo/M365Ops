function Write-M365OpsLog {
    <#
    .SYNOPSIS
        Scrive una riga in Logs\m365ops-YYYYMMDD.log (append, un file al giorno) - storico
        persistente di cosa ha fatto/tentato l'app, per debug e verifica a posteriori.
        Non lancia mai eccezioni: un problema nel logging non deve mai rompere l'azione
        reale che si stava loggando.
    #>
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info', 'Warn', 'Error')] [string]$Level = 'Info'
    )
    try {
        $logDir = Join-Path $script:M365OpsModuleRoot 'Logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        $logFile = Join-Path $logDir "m365ops-$(Get-Date -Format 'yyyyMMdd').log"
        $tenant = if ($script:M365OpsContext) { "$($script:M365OpsContext.Name)[$($script:M365OpsContext.AuthMode)]" } else { '(nessun tenant)' }
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t[$Level]`t$tenant`t$Message"
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    }
    catch { }
}
