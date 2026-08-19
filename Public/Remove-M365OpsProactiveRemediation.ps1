function Remove-M365OpsProactiveRemediation {
    <#
    .SYNOPSIS
        Elimina uno script di Proactive Remediation.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/deviceHealthScripts/$Identity" -Beta | Out-Null
    Write-Host "Proactive Remediation rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
