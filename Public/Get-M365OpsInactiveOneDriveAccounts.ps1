function Get-M365OpsInactiveOneDriveAccounts {
    <#
    .SYNOPSIS
        Incrocia i OneDrive personali (Get-M365OpsOneDriveUsageReport) con lo stato reale
        dell'account Entra ID del proprietario: segnala solo quelli il cui proprietario e'
        disabilitato o non esiste piu' (utente eliminato) - dati ancora presenti su OneDrive
        per un account che non dovrebbe piu' averne accesso, il classico rischio di
        compliance/storage orfano.
    .NOTES
        Il campo Owner di Get-PnPTenantSite non e' ancora stato verificato dal vivo (permesso
        SharePoint mancante) - se il formato restituito non fosse un UPN diretto, la ricerca
        Entra qui sotto fallirebbe per OGNI riga con "non trovato" invece di distinguere
        correttamente disabilitato/eliminato: DA RICONTROLLARE con un test reale appena il
        permesso e' disponibile, prima di considerare questo report affidabile.
    #>
    $sites = @(Get-M365OpsOneDriveUsageReport)
    if ($sites.Count -eq 0) { return @() }

    foreach ($site in $sites) {
        if (-not $site.Owner) {
            [pscustomobject]@{ Url = $site.Url; Owner = $null; StorageUsageCurrent = $site.StorageUsageCurrent; Stato = 'Proprietario sconosciuto (campo Owner vuoto)' }
            continue
        }
        try {
            $user = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$($site.Owner)?`$select=accountEnabled,displayName"
            if ($user.accountEnabled -eq $false) {
                [pscustomobject]@{ Url = $site.Url; Owner = $site.Owner; DisplayName = $user.displayName; StorageUsageCurrent = $site.StorageUsageCurrent; LastContentModifiedDate = $site.LastContentModifiedDate; Stato = 'Account disabilitato' }
            }
        }
        catch {
            # 404 = utente non trovato in Entra ID (eliminato) - qualunque altro errore di rete
            # viene comunque segnalato invece di essere scambiato per un utente eliminato.
            $isNotFound = $_.Exception.Message -match '404|Request_ResourceNotFound'
            $stato = if ($isNotFound) { 'Utente eliminato da Entra ID' } else { "Verifica fallita: $($_.Exception.Message)" }
            [pscustomobject]@{ Url = $site.Url; Owner = $site.Owner; DisplayName = $null; StorageUsageCurrent = $site.StorageUsageCurrent; LastContentModifiedDate = $site.LastContentModifiedDate; Stato = $stato }
        }
    }
}
