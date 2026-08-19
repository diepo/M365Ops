function Remove-M365OpsAdminTemplate {
    <#
    .SYNOPSIS
        Elimina un profilo Modelli amministrativi (Group Policy).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/groupPolicyConfigurations/$Identity" -Beta | Out-Null
    Write-Host "Profilo Modelli amministrativi rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
