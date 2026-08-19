function Get-M365OpsCustomRoles {
    <#
    .SYNOPSIS
        Elenca/legge i ruoli RBAC Intune (incorporati e personalizzati), con le assegnazioni
        quando si specifica -Identity.
    #>
    param([string]$Identity)
    if ($Identity) {
        $role = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleDefinitions/$Identity"
        $role | Add-Member -NotePropertyName RoleAssignments -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleDefinitions/$Identity/roleAssignments").value -Force
        return $role
    }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleDefinitions").value
}
