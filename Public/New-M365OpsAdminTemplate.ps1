function New-M365OpsAdminTemplate {
    <#
    .SYNOPSIS
        Crea un profilo Modelli amministrativi (Group Policy, groupPolicyConfiguration) -
        risorsa esistente solo in Graph beta, verificato dal vivo su Microsoft Learn il
        19/08/2026. Creato VUOTO: usa Find-M365OpsAdminTemplateSetting per cercare le
        impostazioni disponibili e Set-M365OpsAdminTemplateSetting per configurarle, poi
        Set-M365OpsAdminTemplateAssignment per assegnarlo a dei gruppi.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [string[]]$RoleScopeTagIds
    )
    $body = @{ displayName = $DisplayName; description = $Description }
    if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }
    $tmpl = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/groupPolicyConfigurations" -Body $body -Beta
    Write-Host "Profilo Modelli amministrativi creato, VUOTO: $($tmpl.displayName) ($($tmpl.id))" -ForegroundColor Green
    $tmpl
}
