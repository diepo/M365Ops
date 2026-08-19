function New-M365OpsAppProtectionPolicy {
    <#
    .SYNOPSIS
        Crea un criterio di protezione app (MAM) Android o iOS - schema verificato dal vivo su
        Microsoft Learn il 19/08/2026 (androidManagedAppProtection / iosManagedAppProtection).
        NON assegnato e senza app di destinazione: usa Set-M365OpsAppProtectionTargetApps per
        indicare a quali app si applica e Set-M365OpsAppProtectionAssignment per i gruppi.
    .PARAMETER Platform
        'Android' o 'iOS' - determina il tipo di risorsa Graph creato e quali parametri
        specifici della piattaforma sono validi (es. FaceIdBlocked e' solo iOS).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Android', 'iOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [bool]$PinRequired = $true,
        [int]$MinimumPinLength = 4,
        [bool]$OrganizationalCredentialsRequired = $false,
        [bool]$DataBackupBlocked = $false,
        [bool]$DeviceComplianceRequired = $true,
        [bool]$SaveAsBlocked = $true,
        [bool]$ContactSyncBlocked = $false,
        [bool]$PrintBlocked = $false,
        [ValidateSet('allApps', 'managedApps', 'none')] [string]$AllowedInboundDataTransferSources = 'managedApps',
        [ValidateSet('allApps', 'managedApps', 'none')] [string]$AllowedOutboundDataTransferDestinations = 'managedApps',
        [ValidateSet('allApps', 'managedAppsWithPasteIn', 'managedApps', 'blocked')] [string]$AllowedOutboundClipboardSharingLevel = 'managedAppsWithPasteIn',
        [string]$PeriodOfflineBeforeWipeIsEnforced = "P90D",
        [string]$PeriodOfflineBeforeAccessCheck = "PT12H",
        [string]$MinimumRequiredOsVersion,
        [string]$MinimumRequiredAppVersion,
        [bool]$FingerprintBlocked = $false,
        [bool]$FaceIdBlocked = $false
    )

    $body = @{
        displayName                              = $DisplayName
        description                               = $Description
        pinRequired                               = $PinRequired
        minimumPinLength                          = $MinimumPinLength
        organizationalCredentialsRequired         = $OrganizationalCredentialsRequired
        dataBackupBlocked                         = $DataBackupBlocked
        deviceComplianceRequired                  = $DeviceComplianceRequired
        saveAsBlocked                             = $SaveAsBlocked
        contactSyncBlocked                        = $ContactSyncBlocked
        printBlocked                              = $PrintBlocked
        allowedInboundDataTransferSources         = $AllowedInboundDataTransferSources
        allowedOutboundDataTransferDestinations   = $AllowedOutboundDataTransferDestinations
        allowedOutboundClipboardSharingLevel      = $AllowedOutboundClipboardSharingLevel
        periodOfflineBeforeWipeIsEnforced         = $PeriodOfflineBeforeWipeIsEnforced
        periodOfflineBeforeAccessCheck            = $PeriodOfflineBeforeAccessCheck
    }
    if ($MinimumRequiredOsVersion) { $body.minimumRequiredOsVersion = $MinimumRequiredOsVersion }
    if ($MinimumRequiredAppVersion) { $body.minimumRequiredAppVersion = $MinimumRequiredAppVersion }

    if ($Platform -eq 'Android') {
        $body."@odata.type" = "#microsoft.graph.androidManagedAppProtection"
        $body.fingerprintBlocked = $FingerprintBlocked
        $path = "/deviceAppManagement/androidManagedAppProtections"
    } else {
        $body."@odata.type" = "#microsoft.graph.iosManagedAppProtection"
        $body.faceIdBlocked = $FaceIdBlocked
        $path = "/deviceAppManagement/iosManagedAppProtections"
    }

    $policy = Invoke-M365OpsGraphRequest -Method POST -Path $path -Body $body
    Write-Host "Criterio protezione app creato ($Platform), NON ancora associato a gruppi/app: $($policy.displayName) ($($policy.id))" -ForegroundColor Green
    $policy
}
