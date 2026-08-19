function Set-M365OpsEnrollmentConfigurationPriority {
    <#
    .SYNOPSIS
        Cambia la priorita' di una configurazione di iscrizione (azione setPriority) - valore
        piu' basso = priorita' piu' alta, si applica per primo agli utenti in piu' gruppi.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [int]$Priority
    )
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/deviceEnrollmentConfigurations/$Identity/setPriority" -Body @{ priority = $Priority } | Out-Null
    Write-Host "Configurazione ${Identity}: priorita' impostata a $Priority." -ForegroundColor Green
}
