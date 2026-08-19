function Set-M365OpsProactiveRemediationAssignment {
    <#
    .SYNOPSIS
        Assegna uno script di Proactive Remediation a uno o piu' gruppi con una pianificazione -
        schema (deviceHealthScriptAssignment, runSchedule) verificato dal vivo su Microsoft
        Learn il 19/08/2026. SOSTITUISCE l'intero elenco di assegnazioni esistenti.
    .PARAMETER ScheduleType
        'Daily' (default) o 'Hourly'. -RunRemediationScript $false = solo rilevamento, mai
        correzione automatica (default $true).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds,
        [bool]$RunRemediationScript = $true,
        [ValidateSet('Daily', 'Hourly')] [string]$ScheduleType = 'Daily',
        [int]$Interval = 1,
        [string]$TimeOfDay = "03:00:00",
        [bool]$UseUtc = $false
    )

    $schedule = if ($ScheduleType -eq 'Daily') {
        @{ "@odata.type" = "microsoft.graph.deviceHealthScriptDailySchedule"; interval = $Interval; useUtc = $UseUtc; time = $TimeOfDay }
    } else {
        @{ "@odata.type" = "microsoft.graph.deviceHealthScriptHourlySchedule"; interval = $Interval }
    }

    $assignments = @($TargetGroupIds | ForEach-Object {
        @{
            target              = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $_ }
            runRemediationScript = $RunRemediationScript
            runSchedule         = $schedule
        }
    })
    $body = @{ deviceHealthScriptAssignments = $assignments }

    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceHealthScripts/$Identity/assign" -Body $body -Beta | Out-Null
    Write-Host "Proactive Remediation $Identity assegnata a $($TargetGroupIds.Count) gruppo/i ($ScheduleType, ogni $Interval)." -ForegroundColor Green
}
