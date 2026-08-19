function Remove-M365OpsEnrollmentConfiguration {
    <#
    .SYNOPSIS
        Elimina una configurazione di iscrizione dispositivi. Non e' possibile eliminare la
        configurazione predefinita di sistema (una per tipo) - Graph restituira' un errore chiaro.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/deviceEnrollmentConfigurations/$Identity" | Out-Null
    Write-Host "Configurazione iscrizione rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
