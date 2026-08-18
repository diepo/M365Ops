function Set-M365OpsAppAssignment {
    <#
    .SYNOPSIS
        Assegna un'app Intune a un gruppo o a 'All Devices'. Questa e' l'unica cmdlet che
        rende un'app effettivamente attiva su dispositivi reali — usala con intenzione.

    .PARAMETER Intent
        'available' (opzionale dal Company Portal) o 'required' (installazione forzata).

    .PARAMETER TargetGroupId
        Omesso = assegna a All Devices. Valorizzato = assegna solo a quel gruppo.

    .EXAMPLE
        Set-M365OpsAppAssignment -AppId $app.id -Intent available -TargetGroupId $group.id
        Set-M365OpsAppAssignment -AppId $app.id -Intent required   # All Devices
    #>
    param(
        [Parameter(Mandatory)] [string]$AppId,
        [Parameter(Mandatory)] [ValidateSet('available', 'required')] [string]$Intent,
        [string]$TargetGroupId
    )

    $target = if ($TargetGroupId) {
        @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $TargetGroupId }
    } else {
        @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
    }

    $body = @{
        mobileAppAssignments = @(
            @{
                "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                intent        = $Intent
                target        = $target
            }
        )
    }

    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceAppManagement/mobileApps/$AppId/assign" -Body $body -Beta | Out-Null
    $scope = if ($TargetGroupId) { "gruppo $TargetGroupId" } else { "All Devices" }
    Write-Host "Assegnata come '$Intent' a $scope." -ForegroundColor Green
}
