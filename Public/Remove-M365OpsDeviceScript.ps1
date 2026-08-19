function Remove-M365OpsDeviceScript {
    <#
    .SYNOPSIS
        Elimina uno script di distribuzione Intune (PowerShell Windows o Shell macOS).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Windows', 'macOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity
    )
    $base = if ($Platform -eq 'Windows') { "/deviceManagement/deviceManagementScripts" } else { "/deviceManagement/deviceShellScripts" }
    Invoke-M365OpsGraphRequest -Method DELETE -Path "$base/$Identity" -Beta | Out-Null
    Write-Host "Script rimosso: $Identity [$Platform]" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
