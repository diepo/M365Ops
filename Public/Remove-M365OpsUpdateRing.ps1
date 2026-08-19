function Remove-M365OpsUpdateRing {
    <#
    .SYNOPSIS
        Elimina un anello di aggiornamento Windows Update for Business.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/deviceConfigurations/$Identity" | Out-Null
    Write-Host "Anello di aggiornamento rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
