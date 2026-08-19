function Get-M365OpsAutopilotDeploymentProfiles {
    <#
    .SYNOPSIS
        Elenca/legge i profili di distribuzione Windows Autopilot.
    #>
    param([string]$Identity)
    if ($Identity) { return Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/windowsAutopilotDeploymentProfiles/$Identity" -Beta }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/windowsAutopilotDeploymentProfiles" -Beta).value
}
