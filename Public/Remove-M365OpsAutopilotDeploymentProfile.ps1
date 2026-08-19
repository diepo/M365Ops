function Remove-M365OpsAutopilotDeploymentProfile {
    <#
    .SYNOPSIS
        Elimina un profilo di distribuzione Windows Autopilot.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/windowsAutopilotDeploymentProfiles/$Identity" -Beta | Out-Null
    Write-Host "Profilo Autopilot rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
