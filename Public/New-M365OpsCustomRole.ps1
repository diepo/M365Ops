function New-M365OpsCustomRole {
    <#
    .SYNOPSIS
        Crea un ruolo RBAC personalizzato Intune (roleDefinition) - schema verificato dal vivo
        su Microsoft Learn il 19/08/2026. -AllowedResourceActions accetta le stringhe azione
        Intune complete (es. "Microsoft.Intune_MobileApps_Read",
        "Microsoft.Intune_DeviceConfigurations_Assign") - l'elenco completo delle migliaia di
        azioni disponibili si legge da Get-M365OpsRoleDefinitionActions (basato su un ruolo
        incorporato esistente, poiche' Graph non espone un catalogo azioni separato).
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [string[]]$AllowedResourceActions
    )
    $body = @{
        displayName    = $DisplayName
        description    = $Description
        rolePermissions = @(
            @{
                "@odata.type"   = "microsoft.graph.rolePermission"
                resourceActions = @(
                    @{
                        "@odata.type"              = "microsoft.graph.resourceAction"
                        allowedResourceActions     = $AllowedResourceActions
                        notAllowedResourceActions  = @()
                    }
                )
            }
        )
    }
    $role = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/roleDefinitions" -Body $body
    Write-Host "Ruolo personalizzato creato: $($role.displayName) ($($role.id)), $($AllowedResourceActions.Count) azioni consentite. NON ancora assegnato: usa Set-M365OpsRoleAssignment." -ForegroundColor Green
    $role
}
