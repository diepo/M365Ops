function Get-M365OpsAppInstallStatus {
    <#
    .SYNOPSIS
        Raccoglie dati diagnostici per un'app + dispositivo: stato dispositivo, assegnazioni,
        e stato installazione se l'endpoint lo espone (non tutti i tipi di app lo supportano
        ancora, es. i winGetApp — verificato empiricamente oggi).
    #>
    param(
        [Parameter(Mandatory)] [string]$AppId,
        [string]$DeviceId
    )

    $result = [ordered]@{}

    if ($DeviceId) {
        $result.Device = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/managedDevices/$DeviceId"
    }

    $result.Assignments = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceAppManagement/mobileApps/$AppId/assignments" -Beta).value

    try {
        $result.DeviceStatuses = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceAppManagement/mobileApps/$AppId/deviceStatuses" -Beta).value
    }
    catch {
        # Verificato il 14/08/2026: questo endpoint ha fallito sia per un'app winGetApp
        # sia per un'app win32LobApp su questo tenant - non e' un limite di un singolo
        # tipo di app, causa esatta non confermata (forse tenant di test troppo piccolo,
        # forse scope mancante, forse deprecato). Non fidarti del "non disponibile":
        # e' un errore osservato, non una certezza documentata da Microsoft.
        $result.DeviceStatuses = "Endpoint deviceStatuses ha restituito errore: $($_.Exception.Message)"
    }

    [pscustomobject]$result
}
