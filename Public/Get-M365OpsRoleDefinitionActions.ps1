function Get-M365OpsRoleDefinitionActions {
    <#
    .SYNOPSIS
        Elenca le azioni disponibili (allowedResourceActions) lette da un ruolo Intune
        incorporato esistente (es. "Application Manager"), da usare come catalogo di riferimento
        per -AllowedResourceActions di New-M365OpsCustomRole: Graph non espone un endpoint
        dedicato per il catalogo completo delle azioni, solo le azioni gia' presenti nei ruoli
        incorporati (che coprono comunque l'intera superficie funzionale di Intune).
    #>
    param([string]$BuiltInRoleDisplayName = "Application Manager")
    $role = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleDefinitions").value | Where-Object { $_.displayName -eq $BuiltInRoleDisplayName -and $_.isBuiltIn } | Select-Object -First 1
    if (-not $role) { throw "Ruolo incorporato '$BuiltInRoleDisplayName' non trovato." }
    $full = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleDefinitions/$($role.id)"
    $full.rolePermissions.resourceActions.allowedResourceActions
}
