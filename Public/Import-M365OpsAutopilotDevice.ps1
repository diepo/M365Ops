function Import-M365OpsAutopilotDevice {
    <#
    .SYNOPSIS
        Registra un nuovo dispositivo in Windows Autopilot (schema
        importedWindowsAutopilotDeviceIdentity verificato dal vivo su Microsoft Learn il
        19/08/2026). Richiede l'hardware hash REALE del dispositivo (ottenuto sul dispositivo
        stesso, tipicamente con lo script community Get-WindowsAutopilotInfo, oppure dal
        rivenditore/OEM) - non puo' essere generato o indovinato da qui: e' un identificativo
        hardware univoco. La registrazione e' asincrona: usa Get-M365OpsAutopilotImportStatus
        per verificare l'esito (puo' richiedere qualche minuto).
    .PARAMETER HardwareIdentifier
        L'hardware hash in Base64 (la colonna "Hardware Hash" del CSV generato da
        Get-WindowsAutopilotInfo, o il campo equivalente fornito dall'OEM/rivenditore).
    #>
    param(
        [Parameter(Mandatory)] [string]$SerialNumber,
        [Parameter(Mandatory)] [string]$HardwareIdentifier,
        [string]$GroupTag = "",
        [string]$ProductKey = "",
        [string]$AssignedUserPrincipalName
    )

    $body = @{
        "@odata.type"      = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
        groupTag           = $GroupTag
        serialNumber       = $SerialNumber
        productKey         = $ProductKey
        hardwareIdentifier = $HardwareIdentifier
    }
    if ($AssignedUserPrincipalName) { $body.assignedUserPrincipalName = $AssignedUserPrincipalName }

    $result = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/importedWindowsAutopilotDeviceIdentities" -Body $body
    Write-Host "Importazione avviata per il seriale $SerialNumber (id import $($result.id)) - verifica l'esito con Get-M365OpsAutopilotImportStatus, puo' richiedere qualche minuto." -ForegroundColor Green
    $result
}
