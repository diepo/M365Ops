function New-M365OpsNotificationTemplate {
    <#
    .SYNOPSIS
        Crea un modello di messaggio di notifica per la non conformita' (notificationMessageTemplate)
        con il messaggio nella lingua predefinita - schema verificato dal vivo su Microsoft Learn
        il 19/08/2026. Usa Set-M365OpsNotificationTemplateMessage per aggiungere altre lingue.
    .PARAMETER DefaultLocale
        NON viene inviato nel corpo di creazione del template: verificato dal vivo il 19/08/2026
        che Graph rifiuta con 400 "An error has occurred" (nessun dettaglio sul campo, tipico di
        questo servizio Intune) qualunque valore di defaultLocale in POST, a prescindere dal
        formato ("en-us"/"en-US"/"it-IT" tutti falliti identicamente) - isolato per esclusione
        provando ogni proprieta' singolarmente (description e brandingOptions da soli funzionano).
        E' una proprieta' derivata: si imposta creando la prima localizedNotificationMessage con
        isDefault=true (locale=questo parametro), MAI passandola sul template stesso - riletto
        dopo la creazione, defaultLocale risulta popolato correttamente da solo.
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [string]$DefaultLocale = "en-us",
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$MessageBody,
        [ValidateSet('none', 'includeCompanyLogo', 'includeCompanyName', 'includeContactInformation', 'includeCompanyPortalLink', 'includeDeviceDetails')] [string[]]$BrandingOptions = @('includeCompanyLogo', 'includeCompanyName', 'includeContactInformation')
    )
    $body = @{
        displayName     = $DisplayName
        description     = $Description
        brandingOptions = ($BrandingOptions -join ',')
    }
    $template = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/notificationMessageTemplates" -Body $body

    $msgBody = @{ locale = $DefaultLocale; subject = $Subject; messageTemplate = $MessageBody; isDefault = $true }
    Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/notificationMessageTemplates/$($template.id)/localizedNotificationMessages" -Body $msgBody | Out-Null

    Write-Host "Modello di notifica creato: $($template.displayName) ($($template.id)), lingua predefinita $DefaultLocale." -ForegroundColor Green
    $template
}
