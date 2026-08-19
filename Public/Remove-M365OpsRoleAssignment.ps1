function Remove-M365OpsRoleAssignment {
    <#
    .SYNOPSIS
        Rimuove un'assegnazione di ruolo RBAC Intune.
    #>
    param(
        [Parameter(Mandatory)] [string]$RoleDefinitionId,
        [Parameter(Mandatory)] [string]$AssignmentId
    )
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/roleDefinitions/$RoleDefinitionId/roleAssignments/$AssignmentId" -Beta | Out-Null
    Write-Host "Assegnazione ruolo $AssignmentId rimossa dal ruolo $RoleDefinitionId." -ForegroundColor Green
}
