function Get-M365OpsNotificationTemplates {
    <#
    .SYNOPSIS
        Elenca/legge i modelli di messaggio di notifica, con i messaggi localizzati quando si
        specifica -Identity.
    #>
    param([string]$Identity)
    if ($Identity) {
        $template = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/notificationMessageTemplates/$Identity"
        $template | Add-Member -NotePropertyName LocalizedMessages -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages").value -Force
        return $template
    }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/notificationMessageTemplates").value
}
