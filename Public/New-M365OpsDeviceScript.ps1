function New-M365OpsDeviceScript {
    <#
    .SYNOPSIS
        Crea uno script di distribuzione Intune - PowerShell per Windows
        (deviceManagementScripts) o Shell per macOS (deviceShellScripts), schema verificato dal
        vivo su Microsoft Learn il 19/08/2026. DIVERSO dal packaging Win32 (New-M365OpsWin32App):
        qui lo script VIENE ESEGUITO direttamente sul dispositivo (via agente Intune), non
        pacchettizzato come app installabile. NON assegnato: usa
        Set-M365OpsDeviceScriptAssignment per attivarlo.
    .PARAMETER ScriptPath
        Percorso locale del file .ps1 (Windows) o .sh (macOS) - il contenuto viene letto e
        codificato automaticamente.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Windows', 'macOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [string]$ScriptPath,
        [ValidateSet('system', 'user')] [string]$RunAsAccount = 'system',
        [string[]]$RoleScopeTagIds,
        # Solo Windows
        [bool]$EnforceSignatureCheck = $false,
        [bool]$RunAs32Bit = $false,
        # Solo macOS
        [string]$ExecutionFrequency,
        [int]$RetryCount = 3,
        [bool]$BlockExecutionNotifications = $false
    )

    if (-not (Test-Path $ScriptPath)) { throw "File script non trovato: $ScriptPath" }
    $scriptBytes = [IO.File]::ReadAllBytes($ScriptPath)
    $scriptContentBase64 = [Convert]::ToBase64String($scriptBytes)
    $fileName = Split-Path -Leaf $ScriptPath

    if ($Platform -eq 'Windows') {
        $body = @{
            "@odata.type"          = "#microsoft.graph.deviceManagementScript"
            displayName            = $DisplayName
            description            = $Description
            scriptContent          = $scriptContentBase64
            fileName               = $fileName
            runAsAccount           = $RunAsAccount
            enforceSignatureCheck  = $EnforceSignatureCheck
            runAs32Bit             = $RunAs32Bit
        }
        if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }
        $path = "/deviceManagement/deviceManagementScripts"
    } else {
        $body = @{
            "@odata.type"                 = "#microsoft.graph.deviceShellScript"
            displayName                   = $DisplayName
            description                   = $Description
            scriptContent                 = $scriptContentBase64
            fileName                      = $fileName
            runAsAccount                  = $RunAsAccount
            retryCount                    = $RetryCount
            blockExecutionNotifications   = $BlockExecutionNotifications
        }
        if ($ExecutionFrequency) { $body.executionFrequency = $ExecutionFrequency }
        if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }
        $path = "/deviceManagement/deviceShellScripts"
    }

    $script = Invoke-M365OpsGraphRequest -Method POST -Path $path -Body $body -Beta
    Write-Host "Creato, NON assegnato: $($script.displayName) ($($script.id)) [$Platform]" -ForegroundColor Green
    $script
}
