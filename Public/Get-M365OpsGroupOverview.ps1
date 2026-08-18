function Get-M365OpsGroupOverview {
    <#
    .SYNOPSIS
        Panoramica completa di un gruppo: membri, dispositivi dei membri, app assegnate,
        profili di configurazione assegnati, criteri di compliance assegnati.

    .EXAMPLE
        Get-M365OpsGroupOverview -GroupName "Test-M365Ops-Verify"
    #>
    param(
        [string]$GroupName,
        [string]$GroupId
    )

    if (-not $GroupId) {
        if (-not $GroupName) { throw "Specifica -GroupName oppure -GroupId." }
        $encodedName = $GroupName.Replace("'", "''")
        $found = (Invoke-M365OpsGraphRequest -Method GET -Path "/groups?`$filter=displayName eq '$encodedName'&`$select=id,displayName").value
        if (-not $found) { throw "Nessun gruppo trovato con nome '$GroupName'." }
        $GroupId = $found[0].id
        $GroupName = $found[0].displayName
    }
    else {
        $GroupName = (Invoke-M365OpsGraphRequest -Method GET -Path "/groups/$GroupId`?`$select=displayName").displayName
    }

    $members = (Invoke-M365OpsGraphRequest -Method GET -Path "/groups/$GroupId/members?`$select=id,displayName,userPrincipalName").value

    $memberUpns = @($members.userPrincipalName | Where-Object { $_ })
    $devices = if ($memberUpns) { Get-M365OpsManagedDevices | Where-Object { $_.userPrincipalName -in $memberUpns } } else { @() }

    $groupIds = @($GroupId)
    $groupNamesById = @{ $GroupId = $GroupName }

    $assignedApps = Get-M365OpsAssignmentMatches -Path "/deviceAppManagement/mobileApps" -GroupIds $groupIds -GroupNamesById $groupNamesById
    $assignedConfigs = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceConfigurations" -GroupIds $groupIds -GroupNamesById $groupNamesById
    $assignedCompliance = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceCompliancePolicies" -GroupIds $groupIds -GroupNamesById $groupNamesById

    [pscustomobject]@{
        Group                      = $GroupName
        GroupId                    = $GroupId
        Members                    = $members | Select-Object displayName, userPrincipalName
        Devices                    = $devices | Select-Object deviceName, userPrincipalName, complianceState
        AssignedApps               = $assignedApps
        AssignedConfigProfiles     = $assignedConfigs
        AssignedCompliancePolicies = $assignedCompliance
    }
}
