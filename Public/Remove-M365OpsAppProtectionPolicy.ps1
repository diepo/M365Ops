function Remove-M365OpsAppProtectionPolicy {
    <#
    .SYNOPSIS
        Elimina un criterio di protezione app (MAM) Android o iOS.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity
    )
    $base = if ($Platform -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
    Invoke-M365OpsGraphRequest -Method DELETE -Path "$base/$Identity" | Out-Null
    Write-Host "Criterio protezione app rimosso ($Platform): $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Platform = $Platform; Removed = $true }
}
