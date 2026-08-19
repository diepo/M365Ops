function Get-M365OpsAdminTemplates {
    <#
    .SYNOPSIS
        Elenca/legge i profili Modelli amministrativi (Group Policy), con le impostazioni
        configurate quando si specifica -Identity.
    #>
    param([string]$Identity)
    if ($Identity) {
        $tmpl = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/groupPolicyConfigurations/$Identity" -Beta
        $tmpl | Add-Member -NotePropertyName DefinitionValues -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/groupPolicyConfigurations/$Identity/definitionValues" -Beta).value -Force
        $tmpl | Add-Member -NotePropertyName Assignments -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/groupPolicyConfigurations/$Identity/assignments" -Beta).value -Force
        return $tmpl
    }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/groupPolicyConfigurations" -Beta).value
}
