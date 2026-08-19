function New-M365OpsAutopilotDeploymentProfile {
    <#
    .SYNOPSIS
        Crea un profilo di distribuzione Windows Autopilot (schema
        windowsAutopilotDeploymentProfile verificato dal vivo su Microsoft Learn il 19/08/2026).
        NON assegnato: usa Set-M365OpsAutopilotDeploymentProfileAssignment per attivarlo.
    .PARAMETER DeviceNameTemplate
        Es. "PC-%SERIAL%" - max 15 caratteri generati, puo' contenere %SERIAL% o %RAND:n%.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [string]$Locale = "os-default",
        [ValidateSet('windowsPc', 'holoLens', 'virtualMachine')] [string]$DeviceType = 'windowsPc',
        [string]$DeviceNameTemplate,
        [bool]$HidePrivacySettings = $false,
        [bool]$HideEula = $false,
        [ValidateSet('standard', 'administrator')] [string]$UserType = 'standard',
        [bool]$SkipKeyboardSelectionPage = $false,
        [bool]$HideEscapeLink = $true,
        [bool]$HideInstallationProgress = $false,
        [bool]$AllowDeviceUseBeforeProfileAndAppInstallComplete = $false,
        [bool]$BlockDeviceSetupRetryByUser = $false,
        [bool]$AllowLogCollectionOnInstallFailure = $true,
        [int]$InstallProgressTimeoutInMinutes = 60,
        [bool]$AllowDeviceUseOnInstallFailure = $false,
        [string]$CustomErrorMessage = "",
        [bool]$PreprovisioningAllowed = $false,
        [string[]]$RoleScopeTagIds
    )

    $body = @{
        "@odata.type"     = "#microsoft.graph.windowsAutopilotDeploymentProfile"
        displayName       = $DisplayName
        description       = $Description
        locale            = $Locale
        deviceType        = $DeviceType
        hardwareHashExtractionEnabled = $true
        preprovisioningAllowed = $PreprovisioningAllowed
        outOfBoxExperienceSetting = @{
            "@odata.type"                 = "microsoft.graph.outOfBoxExperienceSetting"
            privacySettingsHidden         = $HidePrivacySettings
            eulaHidden                    = $HideEula
            userType                      = $UserType
            deviceUsageType               = "singleUser"
            keyboardSelectionPageSkipped  = $SkipKeyboardSelectionPage
            escapeLinkHidden              = $HideEscapeLink
        }
        enrollmentStatusScreenSettings = @{
            "@odata.type"                                       = "microsoft.graph.windowsEnrollmentStatusScreenSettings"
            hideInstallationProgress                            = $HideInstallationProgress
            allowDeviceUseBeforeProfileAndAppInstallComplete    = $AllowDeviceUseBeforeProfileAndAppInstallComplete
            blockDeviceSetupRetryByUser                         = $BlockDeviceSetupRetryByUser
            allowLogCollectionOnInstallFailure                  = $AllowLogCollectionOnInstallFailure
            customErrorMessage                                  = $CustomErrorMessage
            installProgressTimeoutInMinutes                     = $InstallProgressTimeoutInMinutes
            allowDeviceUseOnInstallFailure                       = $AllowDeviceUseOnInstallFailure
        }
    }
    if ($DeviceNameTemplate) { $body.deviceNameTemplate = $DeviceNameTemplate }
    if ($RoleScopeTagIds) { $body.roleScopeTagIds = $RoleScopeTagIds }

    $profile = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/windowsAutopilotDeploymentProfiles" -Body $body -Beta
    Write-Host "Creato, NON assegnato: $($profile.displayName) ($($profile.id))" -ForegroundColor Green
    $profile
}
