function Set-M365OpsRoleAssignment {
    <#
    .SYNOPSIS
        Crea un'assegnazione per un ruolo RBAC Intune: collega gruppi di amministratori
        (-AdminGroupIds, chi puo' usare il ruolo) a uno scope di gestione (-ScopeType e/o
        -ScopeGroupIds, su cosa puo' agire). Schema roleAssignment con scopeMembers/scopeType
        esiste solo in Graph beta (verificato dal vivo su Microsoft Learn il 19/08/2026: v1.0
        espone solo resourceScopes, non scopeMembers/scopeType) - uso -Beta di conseguenza.
    #>
    param(
        [Parameter(Mandatory)] [string]$RoleDefinitionId,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [string[]]$AdminGroupIds,
        [ValidateSet('resourceScope', 'allDevices', 'allLicensedUsers', 'allDevicesAndLicensedUsers')] [string]$ScopeType = 'resourceScope',
        [string[]]$ScopeGroupIds
    )
    if ($ScopeType -eq 'resourceScope' -and -not $ScopeGroupIds) { throw "-ScopeGroupIds e' obbligatorio quando -ScopeType e' 'resourceScope'." }

    $body = @{
        displayName    = $DisplayName
        description    = $Description
        scopeMembers   = $AdminGroupIds
        scopeType      = $ScopeType
        resourceScopes = if ($ScopeGroupIds) { $ScopeGroupIds } else { @() }
    }
    $assignment = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/roleDefinitions/$RoleDefinitionId/roleAssignments" -Body $body -Beta
    Write-Host "Assegnazione ruolo creata: $($assignment.displayName) ($($assignment.id)) su ruolo $RoleDefinitionId." -ForegroundColor Green
    $assignment
}
