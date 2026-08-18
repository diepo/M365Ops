function Send-M365OpsReportEmail {
    <#
    .SYNOPSIS
        Invia un file come allegato via Microsoft Graph. Su tenant AppOnly usa
        /users/{FromAddress o EmailSender configurato}/sendMail (il permesso applicativo
        Mail.Send consente di inviare come qualunque mailbox del tenant). Su tenant
        Delegated invia SEMPRE come l'utente con cui hai fatto login (/me/sendMail) a meno
        di passare -FromAddress esplicitamente - un token delegato puo' inviare da un
        indirizzo diverso dal proprio solo se quell'utente ha permesso Send As su quella
        mailbox, altrimenti Graph rifiuta con un errore chiaro.
    #>
    param(
        [Parameter(Mandatory)] [string]$To,
        [Parameter(Mandatory)] [string]$AttachmentPath,
        [string]$Subject = "Report M365Ops",
        [string]$Body = "In allegato il report generato da M365Ops.",
        [string]$FromAddress
    )

    $isDelegated = $script:M365OpsContext.AuthMode -eq 'Delegated'
    if (-not $FromAddress -and -not $isDelegated) {
        $FromAddress = $script:M365OpsContext.EmailSender
        if (-not $FromAddress) { throw "Nessun indirizzo mittente configurato. Impostalo con Set-M365OpsTenant -EmailSender oppure passa -FromAddress." }
    }
    if (-not (Test-Path $AttachmentPath)) { throw "File non trovato: $AttachmentPath" }

    $fileBytes = [IO.File]::ReadAllBytes($AttachmentPath)
    $fileName = Split-Path -Leaf $AttachmentPath
    $base64 = [Convert]::ToBase64String($fileBytes)

    $mailBody = @{
        message          = @{
            subject      = $Subject
            body         = @{ contentType = "Text"; content = $Body }
            toRecipients = @(@{ emailAddress = @{ address = $To } })
            attachments  = @(
                @{
                    "@odata.type" = "#microsoft.graph.fileAttachment"
                    name          = $fileName
                    contentBytes  = $base64
                }
            )
        }
        saveToSentItems = $true
    }

    $sendPath = if ($isDelegated -and -not $FromAddress) { "/me/sendMail" } else { "/users/$FromAddress/sendMail" }
    Invoke-M365OpsGraphRequest -Method POST -Path $sendPath -Body $mailBody | Out-Null
    $fromLabel = if ($isDelegated -and -not $FromAddress) { "$($script:M365OpsContext.DelegatedUpn) (utente delegato)" } else { $FromAddress }
    "Email inviata a $To con allegato $fileName (da $fromLabel)."
}
