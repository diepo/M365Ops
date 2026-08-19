function New-M365OpsUpdateRing {
    <#
    .SYNOPSIS
        Crea un anello di aggiornamento Windows Update for Business (windowsUpdateForBusinessConfiguration)
        - schema verificato dal vivo su Microsoft Learn il 19/08/2026. NON assegnato: usa
        Set-M365OpsUpdateRingAssignment per associarlo a dei gruppi.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [ValidateSet('userDefined', 'notifyDownload', 'autoInstallAtMaintenanceTime', 'autoInstallAndRebootAtMaintenanceTime', 'autoInstallAndRebootAtScheduledTime', 'autoInstallAndRebootWithoutEndUserControl')] [string]$AutomaticUpdateMode = 'autoInstallAndRebootAtMaintenanceTime',
        [int]$QualityUpdatesDeferralPeriodInDays = 0,
        [int]$FeatureUpdatesDeferralPeriodInDays = 0,
        [int]$DeadlineForQualityUpdatesInDays = 5,
        [int]$DeadlineForFeatureUpdatesInDays = 5,
        [int]$DeadlineGracePeriodInDays = 2,
        [bool]$MicrosoftUpdateServiceAllowed = $true,
        [bool]$DriversExcluded = $false,
        [ValidateSet('userDefined', 'enabled', 'disabled')] [string]$UserPauseAccess = 'enabled',
        [bool]$PostponeRebootUntilAfterDeadline = $true,
        [bool]$AllowWindows11Upgrade = $false
    )

    $body = @{
        "@odata.type"                        = "#microsoft.graph.windowsUpdateForBusinessConfiguration"
        displayName                          = $DisplayName
        description                          = $Description
        automaticUpdateMode                  = $AutomaticUpdateMode
        qualityUpdatesDeferralPeriodInDays    = $QualityUpdatesDeferralPeriodInDays
        featureUpdatesDeferralPeriodInDays    = $FeatureUpdatesDeferralPeriodInDays
        deadlineForQualityUpdatesInDays       = $DeadlineForQualityUpdatesInDays
        deadlineForFeatureUpdatesInDays       = $DeadlineForFeatureUpdatesInDays
        deadlineGracePeriodInDays             = $DeadlineGracePeriodInDays
        microsoftUpdateServiceAllowed         = $MicrosoftUpdateServiceAllowed
        driversExcluded                       = $DriversExcluded
        userPauseAccess                       = $UserPauseAccess
        postponeRebootUntilAfterDeadline      = $PostponeRebootUntilAfterDeadline
        allowWindows11Upgrade                 = $AllowWindows11Upgrade
    }

    $ring = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceConfigurations" -Body $body
    Write-Host "Anello di aggiornamento creato, NON ancora assegnato: $($ring.displayName) ($($ring.id))" -ForegroundColor Green
    $ring
}
