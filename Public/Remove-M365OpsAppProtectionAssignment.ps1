function Remove-M365OpsAppProtectionAssignment {
    <#
    .SYNOPSIS
        Rimuove una singola assegnazione (per Id di assegnazione, non di gruppo) da un criterio
        di protezione app MAM. Usa Get-M365OpsAppProtectionPolicies -Identity per leggere gli Id
        di assegnazione correnti (proprieta' Assignments).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$AssignmentId
    )
    $base = if ($Platform -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
    Invoke-M365OpsGraphRequest -Method DELETE -Path "$base/$Identity/assignments/$AssignmentId" | Out-Null
    Write-Host "Assegnazione $AssignmentId rimossa dal criterio $Identity ($Platform)." -ForegroundColor Green
}
