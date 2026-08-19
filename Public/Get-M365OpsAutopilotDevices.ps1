function Get-M365OpsAutopilotDevices {
    <#
    .SYNOPSIS
        Elenca i dispositivi registrati in Windows Autopilot (identita', non i dispositivi
        gestiti - per quelli usa Get-M365OpsManagedDevices). Schema
        (windowsAutopilotDeviceIdentity) verificato dal vivo su Microsoft Learn il 19/08/2026.
    #>
    param(
        [string]$Identity,
        [string]$SerialNumber
    )

    if ($Identity) { return Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/windowsAutopilotDeviceIdentities/$Identity" }

    $devices = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/windowsAutopilotDeviceIdentities").value
    if ($SerialNumber) { $devices = @($devices | Where-Object { $_.serialNumber -eq $SerialNumber }) }
    $devices
}
