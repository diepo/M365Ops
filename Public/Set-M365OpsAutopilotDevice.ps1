function Set-M365OpsAutopilotDevice {
    <#
    .SYNOPSIS
        Aggiorna groupTag/utente assegnato/nome di un dispositivo Autopilot gia' registrato
        (azione updateDeviceProperties, verificata dal vivo su Microsoft Learn il 19/08/2026 -
        NON e' una PATCH diretta sulla risorsa, Autopilot usa un'azione dedicata).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string]$GroupTag,
        [string]$UserPrincipalName,
        [string]$AddressableUserName,
        [string]$DisplayName
    )

    $body = @{}
    if ($null -ne $GroupTag) { $body.groupTag = $GroupTag }
    if ($UserPrincipalName) { $body.userPrincipalName = $UserPrincipalName }
    if ($AddressableUserName) { $body.addressableUserName = $AddressableUserName }
    if ($DisplayName) { $body.displayName = $DisplayName }
    if ($body.Count -eq 0) { throw "Nessun campo da modificare specificato." }

    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/windowsAutopilotDeviceIdentities/$Identity/updateDeviceProperties" -Body $body | Out-Null
    Write-Host "Dispositivo Autopilot $Identity aggiornato." -ForegroundColor Green
    Get-M365OpsAutopilotDevices -Identity $Identity
}
