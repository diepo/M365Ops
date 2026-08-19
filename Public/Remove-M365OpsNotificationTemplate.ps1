function Remove-M365OpsNotificationTemplate {
    <#
    .SYNOPSIS
        Elimina un modello di messaggio di notifica.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/notificationMessageTemplates/$Identity" | Out-Null
    Write-Host "Modello di notifica rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
