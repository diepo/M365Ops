function Set-M365OpsAdminTemplateAssignment {
    <#
    .SYNOPSIS
        Assegna un profilo Modelli amministrativi a uno o piu' gruppi - SOSTITUISCE l'intero
        elenco di assegnazioni esistenti (azione "assign" documentata per groupPolicyConfiguration).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds
    )
    $assignments = @($TargetGroupIds | ForEach-Object { @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $_ } } })
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/groupPolicyConfigurations/$Identity/assign" -Body @{ assignments = $assignments } -Beta | Out-Null
    Write-Host "Profilo Modelli amministrativi $Identity assegnato a $($TargetGroupIds.Count) gruppo/i." -ForegroundColor Green
}
