function New-M365OpsProactiveRemediation {
    <#
    .SYNOPSIS
        Crea uno script di Proactive Remediation (deviceHealthScript: rileva+correggi) - schema
        verificato dal vivo su Microsoft Learn il 19/08/2026. NON assegnato: usa
        Set-M365OpsProactiveRemediationAssignment per attivarlo e definire la pianificazione.
    .PARAMETER DetectionScriptPath / RemediationScriptPath
        Percorsi locali dei due script PowerShell (.ps1) - rilevamento e correzione. Il
        rilevamento e' sempre obbligatorio; la correzione e' facoltativa (solo-rilevamento e'
        un caso d'uso legittimo, per il solo reporting).
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [string]$DetectionScriptPath,
        [string]$RemediationScriptPath,
        [ValidateSet('system', 'user')] [string]$RunAsAccount = 'system',
        [bool]$EnforceSignatureCheck = $false,
        [bool]$RunAs32Bit = $false,
        [string]$Publisher = "M365Ops",
        [string[]]$RoleScopeTagIds
    )

    if (-not (Test-Path $DetectionScriptPath)) { throw "Script di rilevamento non trovato: $DetectionScriptPath" }
    $detectionContent = [Convert]::ToBase64String([IO.File]::ReadAllBytes($DetectionScriptPath))
    $remediationContent = if ($RemediationScriptPath) {
        if (-not (Test-Path $RemediationScriptPath)) { throw "Script di correzione non trovato: $RemediationScriptPath" }
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($RemediationScriptPath))
    } else { "" }

    $body = @{
        "@odata.type"              = "#microsoft.graph.deviceHealthScript"
        displayName                = $DisplayName
        description                = $Description
        publisher                  = $Publisher
        detectionScriptContent     = $detectionContent
        remediationScriptContent   = $remediationContent
        runAsAccount               = $RunAsAccount
        enforceSignatureCheck      = $EnforceSignatureCheck
        runAs32Bit                 = $RunAs32Bit
    }
    if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }

    $script = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceHealthScripts" -Body $body -Beta
    Write-Host "Creato, NON assegnato: $($script.displayName) ($($script.id))" -ForegroundColor Green
    $script
}
