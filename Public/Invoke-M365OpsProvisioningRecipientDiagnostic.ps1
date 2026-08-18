function Invoke-M365OpsProvisioningRecipientDiagnostic {
    <#
    .SYNOPSIS
        Diagnostica problemi di provisioning per UN destinatario Exchange Online (UPN o
        indirizzo email) - copre la classe di problemi dietro NDR 550 5.1.10 verso destinatari
        "introvabili", mailbox che non si riconnette dopo un hard delete + risincronizzazione da
        AD on-prem, e provisioning bloccato dopo l'assegnazione di una licenza. L'Identity NON
        deve necessariamente esistere gia' come mailbox - e' proprio il caso "manca il
        provisioning" che questo comando serve a individuare.
    .PARAMETER Identity
        UPN o indirizzo email del destinatario da diagnosticare.
    .NOTES
        Combina quattro fonti in una sola chiamata invece di quattro query separate che l'utente
        dovrebbe interpretare a mano: mailbox attiva, mailbox inattiva/soft-deleted con lo stesso
        indirizzo (e confronto ExchangeGuid, la causa piu' comune di mailbox "che non si
        riconnette"), indirizzi proxy duplicati su altri oggetti (causa di NDR ambiguous
        recipient), stato dell'utente Entra ID (licenza assegnata, sync ibrido). Restituisce
        sempre sia i dati grezzi (Data) sia una sintesi in linguaggio naturale (Findings) di cosa
        NON torna, cosi' un admin non deve incrociare i quattro risultati a mano.
    #>
    param([Parameter(Mandatory)] [string]$Identity)

    Connect-M365OpsExchange
    $findings = [System.Collections.Generic.List[string]]::new()
    $data = [ordered]@{ Identity = $Identity }

    # -Properties ExchangeGuid esplicito: Get-EXOMailbox (a differenza del classico Get-Mailbox)
    # NON restituisce ExchangeGuid di default - senza questo, il confronto ExchangeGuid piu' sotto
    # (il cuore di questa diagnosi) confronterebbe sempre due valori vuoti, non rilevando MAI un
    # conflitto reale ma senza dare nessun errore - trovato prima di essere mai usato dal vivo.
    $mailbox = $null
    try { $mailbox = Get-EXOMailbox -Identity $Identity -Properties ExchangeGuid -ErrorAction Stop } catch { }
    $data.MailboxFound = [bool]$mailbox
    if ($mailbox) {
        $data.RecipientTypeDetails = $mailbox.RecipientTypeDetails
        $data.ExchangeGuid = $mailbox.ExchangeGuid
        $data.PrimarySmtpAddress = $mailbox.PrimarySmtpAddress
    } else {
        $findings.Add("Nessuna mailbox attiva trovata in Exchange Online con identity '$Identity'.")
    }

    $recipient = $null
    try { $recipient = Get-Recipient -Identity $Identity -ErrorAction Stop } catch { }
    $data.RecipientFound = [bool]$recipient
    if ($recipient -and -not $mailbox) {
        $data.RecipientType = $recipient.RecipientType
        $findings.Add("Esiste un oggetto destinatario di tipo '$($recipient.RecipientType)' con questo indirizzo, ma NON e' una mailbox utente - tipico di un MailUser proveniente da sync ibrido non ancora convertito in mailbox cloud, o di un contatto/gruppo che occupa lo stesso indirizzo.")
    } elseif (-not $recipient -and -not $mailbox) {
        $findings.Add("Nessun oggetto destinatario di alcun tipo trovato con questo indirizzo in Exchange Online.")
    }

    $inactive = $null
    try { $inactive = Get-EXOMailbox -Identity $Identity -SoftDeletedMailbox -Properties ExchangeGuid -ErrorAction Stop } catch { }
    if (-not $inactive) {
        try {
            $inactive = @(Get-EXOMailbox -InactiveMailboxOnly -ResultSize Unlimited -Properties ExchangeGuid -ErrorAction Stop | Where-Object {
                $_.PrimarySmtpAddress -eq $Identity -or $_.UserPrincipalName -eq $Identity -or ($_.EmailAddresses -contains "smtp:$Identity")
            } | Select-Object -First 1)
        } catch { }
    }
    $data.InactiveOrSoftDeletedMailboxFound = [bool]$inactive
    if ($inactive) {
        $data.InactiveExchangeGuid = $inactive.ExchangeGuid
        $findings.Add("Trovata una mailbox INATTIVA/eliminata (soft-delete) con lo stesso indirizzo (ExchangeGuid $($inactive.ExchangeGuid)) - se l'oggetto Entra ID risincronizzato ha un ExchangeGuid diverso, la vecchia mailbox NON si riconnette automaticamente: e' il conflitto classico dopo un hard delete seguito da resync da AD on-prem.")
        if ($mailbox -and $mailbox.ExchangeGuid -and $inactive.ExchangeGuid -and $mailbox.ExchangeGuid -ne $inactive.ExchangeGuid) {
            $findings.Add("CONFERMATO: l'ExchangeGuid della mailbox attiva ($($mailbox.ExchangeGuid)) e' DIVERSO da quello della mailbox inattiva ($($inactive.ExchangeGuid)) - i dati della vecchia mailbox NON sono collegati a questo utente, serve un New-MailboxRestoreRequest esplicito per recuperarli, non avverra' da solo.")
        }
    }

    $dupHolders = $null
    try {
        $dupHolders = @(Get-Recipient -Filter "EmailAddresses -like '*$Identity*'" -ResultSize Unlimited -ErrorAction Stop | Where-Object { $_.PrimarySmtpAddress -ne $Identity })
    } catch { }
    $data.DuplicateProxyAddressHolders = if ($dupHolders) { @($dupHolders | Select-Object -ExpandProperty PrimarySmtpAddress) } else { @() }
    if ($dupHolders -and $dupHolders.Count -gt 0) {
        $findings.Add("L'indirizzo '$Identity' compare come indirizzo proxy secondario su $($dupHolders.Count) altro/i oggetto/i ($(($dupHolders | Select-Object -ExpandProperty PrimarySmtpAddress) -join ', ')) - possibile causa di NDR 'ambiguous recipient' o di consegna verso l'oggetto sbagliato.")
    }

    $aadUser = $null
    try { $aadUser = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$Identity`?`$select=id,userPrincipalName,accountEnabled,onPremisesSyncEnabled,onPremisesLastSyncDateTime,assignedLicenses,createdDateTime" } catch { }
    $data.EntraUserFound = [bool]$aadUser
    if ($aadUser) {
        $data.OnPremisesSyncEnabled = $aadUser.onPremisesSyncEnabled
        $data.OnPremisesLastSyncDateTime = $aadUser.onPremisesLastSyncDateTime
        $data.LicenseCount = @($aadUser.assignedLicenses).Count
        $data.AccountCreated = $aadUser.createdDateTime
        if (@($aadUser.assignedLicenses).Count -gt 0 -and -not $mailbox) {
            $ageNote = if ($aadUser.createdDateTime) {
                $ageHours = [math]::Round(((Get-Date) - [datetime]$aadUser.createdDateTime).TotalHours, 1)
                " (account creato $ageHours ore fa)"
            } else { "" }
            $findings.Add("L'utente Entra ID esiste e ha $(@($aadUser.assignedLicenses).Count) licenza/e assegnata/e ma NESSUNA mailbox risulta provisionata$ageNote - se sono passate solo poche ore e' provisioning normale in corso (puo' richiedere fino a qualche ora), altrimenti va indagato (licenza senza piano Exchange incluso, provisioning bloccato lato Microsoft).")
        }
    } else {
        $findings.Add("Nessun utente Entra ID trovato con identity '$Identity' - verifica che l'indirizzo/UPN sia scritto correttamente, o che l'oggetto non sia stato eliminato di recente (recuperabile dal cestino Entra ID entro 30 giorni).")
    }

    if ($findings.Count -eq 0) {
        $findings.Add("Nessuna anomalia di provisioning rilevata: mailbox attiva, coerente, nessun conflitto trovato con altri oggetti.")
    }

    [pscustomobject]@{
        Identity = $Identity
        Findings = @($findings)
        Data     = [pscustomobject]$data
    }
}
