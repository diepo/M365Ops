function Set-M365OpsNotificationTemplateMessage {
    <#
    .SYNOPSIS
        Aggiunge o aggiorna il messaggio localizzato di un modello di notifica per una lingua
        specifica. Se -Locale esiste gia' per il modello, aggiorna quel messaggio (PATCH);
        altrimenti ne crea uno nuovo (POST).
    .NOTES
        Bug reale trovato dal vivo il 23/08/2026 durante un bug-hunt mirato sulle scritture
        Exchange/Teams/SharePoint: il ramo PATCH includeva 'locale' nel body (ereditato dal
        body condiviso con il ramo POST, dove serve) - Graph rifiuta SEMPRE con 400 "Cannot
        Patch Locale Property", anche quando il valore e' identico a quello gia' presente,
        perche' il locale fa gia' parte dell'ID della risorsa
        (.../localizedNotificationMessages/{templateId}_{locale}) ed e' immutabile via PATCH.
        Risultato pre-fix: aggiornare un messaggio localizzato GIA' esistente (es. per
        correggere un refuso) falliva sempre, mentre crearne uno nuovo funzionava - riprodotto
        dal vivo creando en-us, poi tentando un secondo Set- sullo stesso locale. Fix: il body
        del PATCH omette 'locale' (non necessario: la risorsa e' gia' identificata dall'ID).
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$Locale,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$MessageBody,
        [bool]$IsDefault = $false
    )
    $existing = (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages").value | Where-Object { $_.locale -eq $Locale }

    if ($existing) {
        $patchBody = @{ subject = $Subject; messageTemplate = $MessageBody; isDefault = $IsDefault }
        Invoke-M365OpsGraphRequest -Method PATCH -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages/$($existing.id)" -Body $patchBody | Out-Null
        Write-Host "Messaggio $Locale aggiornato per il modello $Identity." -ForegroundColor Green
    } else {
        $body = @{ locale = $Locale; subject = $Subject; messageTemplate = $MessageBody; isDefault = $IsDefault }
        Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/notificationMessageTemplates/$Identity/localizedNotificationMessages" -Body $body | Out-Null
        Write-Host "Messaggio $Locale aggiunto al modello $Identity." -ForegroundColor Green
    }
}
