function Get-M365OpsDeviceScripts {
    <#
    .SYNOPSIS
        Elenca/legge gli script di distribuzione Intune (PowerShell Windows o Shell macOS).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Windows', 'macOS')] [string]$Platform,
        [string]$Identity
    )
    $base = if ($Platform -eq 'Windows') { "/deviceManagement/deviceManagementScripts" } else { "/deviceManagement/deviceShellScripts" }
    if ($Identity) { return Invoke-M365OpsGraphRequest -Method GET -Path "$base/$Identity" -Beta }
    (Invoke-M365OpsGraphRequest -Method GET -Path $base -Beta).value
}
