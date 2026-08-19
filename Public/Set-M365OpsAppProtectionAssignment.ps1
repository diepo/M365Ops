function Set-M365OpsAppProtectionAssignment {
    <#
    .SYNOPSIS
        Assegna un criterio di protezione app (MAM) a uno o piu' gruppi - AGGIUNGE alle
        assegnazioni esistenti (non le sostituisce): a differenza delle azioni "assign" usate
        altrove in questo modulo (Win32 app, script, Autopilot, ecc.), assignments qui e' una
        collezione OData standard (verificato dal vivo: GET .../assignments e' documentato,
        senza una action "assign" dedicata) - quindi ogni gruppo si aggiunge con un POST
        separato alla collezione. Per rimuovere un'assegnazione usa Remove-M365OpsAppProtectionAssignment.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds,
        [switch]$Exclude
    )
    $base = if ($Platform -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
    $targetType = if ($Exclude) { "#microsoft.graph.exclusionGroupAssignmentTarget" } else { "#microsoft.graph.groupAssignmentTarget" }

    foreach ($groupId in $TargetGroupIds) {
        $body = @{
            "@odata.type" = "#microsoft.graph.targetedManagedAppPolicyAssignment"
            target        = @{ "@odata.type" = $targetType; groupId = $groupId }
        }
        Invoke-M365OpsGraphRequest -Method POST -Path "$base/$Identity/assignments" -Body $body | Out-Null
    }
    $mode = if ($Exclude) { "esclusione" } else { "inclusione" }
    Write-Host "Criterio $Identity ($Platform): aggiunti $($TargetGroupIds.Count) gruppo/i in $mode." -ForegroundColor Green
}
