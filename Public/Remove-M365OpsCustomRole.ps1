function Remove-M365OpsCustomRole {
    <#
    .SYNOPSIS
        Elimina un ruolo RBAC personalizzato Intune. I ruoli incorporati (isBuiltIn=true) non
        possono essere eliminati - Graph restituira' un errore chiaro in tal caso.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/roleDefinitions/$Identity" | Out-Null
    Write-Host "Ruolo personalizzato rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
