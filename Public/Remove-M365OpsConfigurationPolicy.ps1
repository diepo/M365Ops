function Remove-M365OpsConfigurationPolicy {
    <#
    .SYNOPSIS
        Elimina una policy Settings Catalog/Endpoint Security/Security Baseline.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/configurationPolicies/$Identity" -Beta | Out-Null
    Write-Host "Policy rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
