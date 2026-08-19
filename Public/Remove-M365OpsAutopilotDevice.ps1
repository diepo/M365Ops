function Remove-M365OpsAutopilotDevice {
    <#
    .SYNOPSIS
        Derogistra (deregister) un dispositivo da Windows Autopilot - azione AD ALTO IMPATTO:
        il dispositivo perde la registrazione Autopilot e al prossimo reset/reimaging non
        seguira' piu' l'esperienza Out-of-Box-Experience automatica configurata, finche' non
        viene ri-registrato. Non elimina il dispositivo da Intune (per quello serve un'azione
        separata sul managed device).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/windowsAutopilotDeviceIdentities/$Identity/deregister" | Out-Null
    Write-Host "Dispositivo Autopilot $Identity deregistrato." -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Deregistered = $true }
}
