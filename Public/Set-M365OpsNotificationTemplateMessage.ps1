function Set-M365OpsNotificationTemplateMessage {
    <#
    .SYNOPSIS
        Aggiunge o aggiorna il messaggio localizzato di un modello di notifica per una lingua
        specifica. Se -Locale esiste gia' per il modello, aggiorna quel messaggio (PATCH);
        altrimenti ne crea uno nuovo (POST).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$Locale,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$MessageBody,
        [bool]$IsDefault = $false
    )
    $existing = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages").value | Where-Object { $_.locale -eq $Locale }
    $body = @{ locale = $Locale; subject = $Subject; messageTemplate = $MessageBody; isDefault = $IsDefault }

    if ($existing) {
        Invoke-M365OpsGraphRequest -Method PATCH -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages/$($existing.id)" -Body $body | Out-Null
        Write-Host "Messaggio $Locale aggiornato per il modello $Identity." -ForegroundColor Green
    } else {
        Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages" -Body $body | Out-Null
        Write-Host "Messaggio $Locale aggiunto al modello $Identity." -ForegroundColor Green
    }
}
