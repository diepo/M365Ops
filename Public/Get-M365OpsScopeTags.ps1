function Get-M365OpsScopeTags {
    <#
    .SYNOPSIS
        Elenca/legge gli Scope Tag Intune (roleScopeTag).
    #>
    param([string]$Identity)
    if ($Identity) { return Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleScopeTags/$Identity" -Beta }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/roleScopeTags" -Beta).value
}
