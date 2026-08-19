function Set-M365OpsUpdateRingAssignment {
    <#
    .SYNOPSIS
        Assegna un anello di aggiornamento a uno o piu' gruppi - SOSTITUISCE l'intero elenco di
        assegnazioni esistenti, azione "assign" standard di deviceConfiguration.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds,
        [switch]$Exclude
    )
    $targetType = if ($Exclude) { "#microsoft.graph.exclusionGroupAssignmentTarget" } else { "#microsoft.graph.groupAssignmentTarget" }
    $assignments = @($TargetGroupIds | ForEach-Object { @{ target = @{ "@odata.type" = $targetType; groupId = $_ } } })
    $body = @{ assignments = $assignments }
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceConfigurations/$Identity/assign" -Body $body | Out-Null
    Write-Host "Anello di aggiornamento $Identity assegnato a $($TargetGroupIds.Count) gruppo/i." -ForegroundColor Green
}
