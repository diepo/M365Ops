function New-M365OpsEnrollmentLimitConfiguration {
    <#
    .SYNOPSIS
        Crea una configurazione che limita il numero di dispositivi iscrivibili per utente
        (deviceEnrollmentLimitConfiguration) - schema verificato dal vivo su Microsoft Learn il
        19/08/2026. Priorita' assegnata automaticamente da Intune alla creazione (ultima):
        usa Set-M365OpsEnrollmentConfigurationPriority per riordinare.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [ValidateRange(1, 15)] [int]$Limit
    )
    $body = @{
        "@odata.type" = "#microsoft.graph.deviceEnrollmentLimitConfiguration"
        displayName   = $DisplayName
        description   = $Description
        limit         = $Limit
    }
    $cfg = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceEnrollmentConfigurations" -Body $body
    Write-Host "Limite iscrizione creato: $($cfg.displayName) ($($cfg.id)), limite=$Limit dispositivi/utente." -ForegroundColor Green
    $cfg
}
