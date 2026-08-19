function New-M365OpsEnrollmentPlatformRestriction {
    <#
    .SYNOPSIS
        Crea una configurazione di restrizione piattaforma per l'iscrizione dispositivi
        (deviceEnrollmentPlatformRestrictionsConfiguration) - schema verificato dal vivo su
        Microsoft Learn il 19/08/2026. Ogni piattaforma non specificata resta non bloccata
        (comportamento predefinito Intune, nessuna restrizione).
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [bool]$IosBlocked, [bool]$IosPersonalDeviceEnrollmentBlocked, [string]$IosOsMinimumVersion, [string]$IosOsMaximumVersion,
        [bool]$WindowsBlocked, [bool]$WindowsPersonalDeviceEnrollmentBlocked, [string]$WindowsOsMinimumVersion, [string]$WindowsOsMaximumVersion,
        [bool]$AndroidBlocked, [bool]$AndroidPersonalDeviceEnrollmentBlocked, [string]$AndroidOsMinimumVersion, [string]$AndroidOsMaximumVersion,
        [bool]$MacOSBlocked, [bool]$MacOSPersonalDeviceEnrollmentBlocked, [string]$MacOSOsMinimumVersion, [string]$MacOSOsMaximumVersion
    )

    function New-Restriction([bool]$blocked, [bool]$personalBlocked, [string]$minVer, [string]$maxVer) {
        $r = @{ "@odata.type" = "microsoft.graph.deviceEnrollmentPlatformRestriction"; platformBlocked = $blocked; personalDeviceEnrollmentBlocked = $personalBlocked }
        if ($minVer) { $r.osMinimumVersion = $minVer }
        if ($maxVer) { $r.osMaximumVersion = $maxVer }
        $r
    }

    $body = @{
        "@odata.type"       = "#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration"
        displayName         = $DisplayName
        description         = $Description
        iosRestriction      = New-Restriction $IosBlocked $IosPersonalDeviceEnrollmentBlocked $IosOsMinimumVersion $IosOsMaximumVersion
        windowsRestriction  = New-Restriction $WindowsBlocked $WindowsPersonalDeviceEnrollmentBlocked $WindowsOsMinimumVersion $WindowsOsMaximumVersion
        androidRestriction  = New-Restriction $AndroidBlocked $AndroidPersonalDeviceEnrollmentBlocked $AndroidOsMinimumVersion $AndroidOsMaximumVersion
        macOSRestriction    = New-Restriction $MacOSBlocked $MacOSPersonalDeviceEnrollmentBlocked $MacOSOsMinimumVersion $MacOSOsMaximumVersion
    }

    $cfg = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceEnrollmentConfigurations" -Body $body
    Write-Host "Restrizione piattaforma creata: $($cfg.displayName) ($($cfg.id))." -ForegroundColor Green
    $cfg
}
