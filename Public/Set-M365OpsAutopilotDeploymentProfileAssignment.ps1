function Set-M365OpsAutopilotDeploymentProfileAssignment {
    <#
    .SYNOPSIS
        Assegna un profilo di distribuzione Autopilot a uno o piu' gruppi (SOSTITUISCE l'intero
        elenco di assegnazioni esistenti, stesso principio di Set-M365OpsConfigurationPolicyAssignment).
        I gruppi target devono essere gruppi di DISPOSITIVI (dynamic device group basato su
        seriale/gruppo Autopilot, tipico "groupTag"), non gruppi di utenti.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds
    )
    $assignments = @($TargetGroupIds | ForEach-Object { @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $_ } } })
    $body = @{ assignments = $assignments }
    $result = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/windowsAutopilotDeploymentProfiles/$Identity/assign" -Body $body -Beta
    Write-Host "Profilo Autopilot $Identity assegnato a $($TargetGroupIds.Count) gruppo/i." -ForegroundColor Green
    $result
}
