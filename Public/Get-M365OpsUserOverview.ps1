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

    # Try/catch per ciascuna delle tre categorie (26/08/2026, stesso schema gia' trovato piu'
    # volte in questo progetto - vedi Get-M365OpsDelegatedPermissionsCheck, commit 0dfc6fd): app
    # assegnate, profili di configurazione e criteri di compliance sono tre chiamate Graph
    # indipendenti fra loro - prima di questo fix, un errore su UNA sola (es. throttling, o un
    # tipo di risorsa momentaneamente non raggiungibile) faceva fallire l'intera panoramica
    # utente, incluse le due categorie indipendenti gia' recuperate con successo.
    $assignmentErrors = @()
    try { $assignedApps = Get-M365OpsAssignmentMatches -Path "/deviceAppManagement/mobileApps" -GroupIds $groupIds -GroupNamesById $groupNamesById }
    catch { $assignedApps = @(); $assignmentErrors += "App assegnate: $($_.Exception.Message)" }
    try { $assignedConfigs = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceConfigurations" -GroupIds $groupIds -GroupNamesById $groupNamesById }
    catch { $assignedConfigs = @(); $assignmentErrors += "Profili di configurazione assegnati: $($_.Exception.Message)" }
    try { $assignedCompliance = Get-M365OpsAssignmentMatches -Path "/deviceManagement/deviceCompliancePolicies" -GroupIds $groupIds -GroupNamesById $groupNamesById }
    catch { $assignedCompliance = @(); $assignmentErrors += "Criteri di compliance assegnati: $($_.Exception.Message)" }

    $overview = [pscustomobject]@{
        User                       = $Upn
        Groups                     = $groups | Select-Object displayName, id
        Devices                    = $devices | Select-Object deviceName, complianceState, model, osVersion
        AssignedApps               = $assignedApps
        AssignedConfigProfiles     = $assignedConfigs
        AssignedCompliancePolicies = $assignedCompliance
    }
    if ($assignmentErrors) {
        # Campo aggiuntivo, non sostituisce le liste sopra (che restano @() e non spariscono):
        # segnala esplicitamente quali categorie non sono state verificabili invece di lasciar
        # intendere "nessuna assegnazione" quando in realta' e' "verifica fallita".
        $overview | Add-Member -NotePropertyName AssignmentCheckErrors -NotePropertyValue $assignmentErrors -Force
        Write-M365OpsLog "Get-M365OpsUserOverview ($Upn): $($assignmentErrors -join '; ')" -Level Warn
    }
    $overview
}
