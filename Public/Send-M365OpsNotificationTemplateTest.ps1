function Send-M365OpsNotificationTemplateTest {
    <#
    .SYNOPSIS
        Invia un messaggio di prova per un modello di notifica (azione sendTestMessage) alla
        lingua predefinita del modello, all'utente attualmente autenticato.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/notificationMessageTemplates/$Identity/sendTestMessage" | Out-Null
    Write-Host "Messaggio di prova inviato per il modello $Identity." -ForegroundColor Green
}
