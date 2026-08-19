function Remove-M365OpsScopeTag {
    <#
    .SYNOPSIS
        Elimina uno Scope Tag Intune (roleScopeTag). Non e' possibile eliminare lo scope tag
        "Default" incorporato (isBuiltIn=true) - Graph restituira' un errore chiaro in tal caso.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/roleScopeTags/$Identity" -Beta | Out-Null
    Write-Host "Scope Tag rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
