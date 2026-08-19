function Set-M365OpsConfigurationPolicyAssignment {
    <#
    .SYNOPSIS
        Assegna una policy Settings Catalog/Endpoint Security/Security Baseline a uno o piu'
        gruppi (o a tutti i dispositivi/utenti) - SOSTITUISCE l'intero elenco di assegnazioni
        esistenti (comportamento nativo dell'azione Graph 'assign', non incrementale: per
        aggiungere un gruppo a un'assegnazione gia' esistente, includi anche i gruppi gia'
        assegnati in TargetGroupIds).
    .PARAMETER TargetGroupIds
        Uno o piu' Id di gruppo. Omesso insieme a -AllDevices/-AllUsers = nessuna assegnazione
        (rimuove tutte quelle esistenti).
    .PARAMETER ExcludeGroupIds
        Gruppi esplicitamente esclusi dall'assegnazione.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string[]]$TargetGroupIds,
        [string[]]$ExcludeGroupIds,
        [switch]$AllDevices,
        [switch]$AllUsers
    )

    $assignments = @()
    if ($AllDevices) { $assignments += @{ target = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" } } }
    if ($AllUsers) { $assignments += @{ target = @{ "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget" } } }
    foreach ($groupId in $TargetGroupIds) { $assignments += @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } } }
    foreach ($groupId in $ExcludeGroupIds) { $assignments += @{ target = @{ "@odata.type" = "#microsoft.graph.exclusionGroupAssignmentTarget"; groupId = $groupId } } }

    $body = @{ assignments = $assignments }
    $result = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/configurationPolicies/$Identity/assign" -Body $body -Beta
    Write-Host "Assegnazioni aggiornate per la policy $Identity ($($assignments.Count) destinatari)." -ForegroundColor Green
    $result
}
