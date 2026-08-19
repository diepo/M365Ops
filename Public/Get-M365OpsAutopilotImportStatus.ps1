function Get-M365OpsAutopilotImportStatus {
    <#
    .SYNOPSIS
        Verifica l'esito di un'importazione Autopilot avviata con Import-M365OpsAutopilotDevice
        (asincrona - subito dopo l'import di solito risulta ancora 'pending'/'partner').
    #>
    param([string]$ImportId)

    if ($ImportId) { return Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/importedWindowsAutopilotDeviceIdentities/$ImportId" }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/importedWindowsAutopilotDeviceIdentities").value
}
