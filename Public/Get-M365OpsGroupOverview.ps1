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

    # Try/catch per ciascuna delle tre categorie (26/08/2026, stesso schema gia' trovato piu'
    # volte in questo progetto - vedi Get-M365OpsDelegatedPermissionsCheck, commit 0dfc6fd; e lo
    # stesso fix appena applicato a Get-M365OpsUserOverview, il gemello di questa funzione): app
    # assegnate, profili di configurazione e criteri di compliance sono tre chiamate Graph
    # indipendenti fra loro - prima di questo fix, un errore su UNA sola faceva fallire l'intera
    # panoramica gruppo, incluse le due categorie indipendenti gia' recuperate con successo.
    $assignmentErrors = @()
    try { $assignedApps = Get-M365OpsAssignmentMatches -Path "/deviceAppManagement/mobileApps" -GroupIds $groupIds -GroupNamesById $groupNamesById }
    catch { $assignedApps = @(); $assignmentErrors += "App assegnate: $($_.Exception.Message)" }
    try { $assignedConfigs = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceConfigurations" -GroupIds $groupIds -GroupNamesById $groupNamesById }
    catch { $assignedConfigs = @(); $assignmentErrors += "Profili di configurazione assegnati: $($_.Exception.Message)" }
    try { $assignedCompliance = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceCompliancePolicies" -GroupIds $groupIds -GroupNamesById $groupNamesById }
    catch { $assignedCompliance = @(); $assignmentErrors += "Criteri di compliance assegnati: $($_.Exception.Message)" }

    $overview = [pscustomobject]@{
        Group                      = $GroupName
        GroupId                    = $GroupId
        Members                    = $members | Select-Object displayName, userPrincipalName
        Devices                    = $devices | Select-Object deviceName, userPrincipalName, complianceState
        AssignedApps               = $assignedApps
        AssignedConfigProfiles     = $assignedConfigs
        AssignedCompliancePolicies = $assignedCompliance
    }
    if ($assignmentErrors) {
        $overview | Add-Member -NotePropertyName AssignmentCheckErrors -NotePropertyValue $assignmentErrors -Force
        Write-M365OpsLog "Get-M365OpsGroupOverview ($GroupName): $($assignmentErrors -join '; ')" -Level Warn
    }
    $overview
}
