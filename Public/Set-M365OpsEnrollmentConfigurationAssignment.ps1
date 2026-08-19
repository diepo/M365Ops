function Set-M365OpsEnrollmentConfigurationAssignment {
    <#
    .SYNOPSIS
        Assegna una configurazione di iscrizione a uno o piu' gruppi - SOSTITUISCE l'intero
        elenco di assegnazioni esistenti (azione "assign" standard).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds
    )
    $assignments = @($TargetGroupIds | ForEach-Object { @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $_ } } })
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceEnrollmentConfigurations/$Identity/assign" -Body @{ enrollmentConfigurationAssignments = $assignments } | Out-Null
    Write-Host "Configurazione iscrizione $Identity assegnata a $($TargetGroupIds.Count) gruppo/i." -ForegroundColor Green
}
