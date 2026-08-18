function Get-M365OpsUserOverview {
    <#
    .SYNOPSIS
        Panoramica completa di un utente: gruppi (transitivi), dispositivi Intune,
        app assegnate, profili di configurazione assegnati, criteri di compliance assegnati.
        Sola lettura, nessuna interpretazione — dati grezzi organizzati.

    .EXAMPLE
        Get-M365OpsUserOverview -Upn diego@contoso.com
    #>
    param(
        [Parameter(Mandatory)] [string]$Upn
    )

    $groups = (Invoke-M365OpsGraphRequest -Method GET -Path "/users/$Upn/transitiveMemberOf?`$select=id,displayName").value |
        Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
    $groupIds = @($groups.id)
    $groupNamesById = @{}
    foreach ($g in $groups) { $groupNamesById[$g.id] = $g.displayName }

    $devices = Get-M365OpsManagedDevices | Where-Object { $_.userPrincipalName -eq $Upn }

    $assignedApps = Get-M365OpsAssignmentMatches -Path "/deviceAppManagement/mobileApps" -GroupIds $groupIds -GroupNamesById $groupNamesById
    $assignedConfigs = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceConfigurations" -GroupIds $groupIds -GroupNamesById $groupNamesById
    $assignedCompliance = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceCompliancePolicies" -GroupIds $groupIds -GroupNamesById $groupNamesById

    [pscustomobject]@{
        User                       = $Upn
        Groups                     = $groups | Select-Object displayName, id
        Devices                    = $devices | Select-Object deviceName, complianceState, model, osVersion
        AssignedApps               = $assignedApps
        AssignedConfigProfiles     = $assignedConfigs
        AssignedCompliancePolicies = $assignedCompliance
    }
}
