function Complete-M365OpsDelegatedLogin {
    <#
    .SYNOPSIS
        UN singolo tentativo di verifica che l'utente abbia completato il login avviato
        con Start-M365OpsDelegatedLogin per il tenant ATTIVO - pensata per essere chiamata
        ripetutamente (polling) dalla GUI, non blocca in attesa. Su successo, la sessione
        delegata viene messa in cache SOLO per questo tenant (isolata dagli altri profili).
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $pending = $script:M365OpsPendingDeviceCode[$tenantName]
    if (-not $pending) {
        return [pscustomobject]@{ Status = 'Error'; Message = "Nessun login in corso per '$tenantName' - avvialo prima con Start-M365OpsDelegatedLogin." }
    }
    if ((Get-Date) -gt $pending.ExpiresAt) {
        $script:M365OpsPendingDeviceCode.Remove($tenantName)
        return [pscustomobject]@{ Status = 'Error'; Message = "Codice scaduto - riavvia il login." }
    }

    $result = Receive-M365OpsDeviceCodeToken -TenantId $script:M365OpsContext.TenantId -DeviceCode $pending.DeviceCode

    if ($result.Status -eq 'Completed') {
        $script:M365OpsPendingDeviceCode.Remove($tenantName)
        if (-not $script:M365OpsTokenCache[$tenantName]) { $script:M365OpsTokenCache[$tenantName] = @{} }
        $script:M365OpsTokenCache[$tenantName].Delegated = @{
            AccessToken  = $result.AccessToken
            RefreshToken = $result.RefreshToken
            ExpiresAt    = $result.ExpiresAt
        }
        Write-Host "Login delegato completato per '$tenantName'." -ForegroundColor Green
    }
    elseif ($result.Status -eq 'Error') {
        $script:M365OpsPendingDeviceCode.Remove($tenantName)
        # Riconoscimento del consenso admin mancante (26/08/2026, richiesto esplicitamente
        # dall'utente): AADSTS65001 e' il codice specifico che Azure AD restituisce quando il
        # client pubblico "Microsoft Graph Command Line Tools" non ha (ancora) il consenso
        # amministratore su QUESTO tenant per gli scope richiesti - un errore di
        # AUTORIZZAZIONE MANCANTE, non di rete/credenziali sbagliate. CLI Microsoft 365 usa un
        # client di prima parte DIVERSO per il proprio login (vedi Connect-M365OpsCliMicrosoft365.ps1)
        # - un consenso admin e' per definizione specifico di UN client, quindi e' realistico
        # che un tenant l'abbia concesso all'uno e non all'altro: se il login Graph fallisce
        # proprio per questo motivo, provare CLI365 (gia' cablato per accedere allo stesso
        # dominio Entra ID/Outlook/Planner/OneDrive/Purview via Invoke-M365OpsAgentTools.ps1,
        # vedi $cliM365ProactivePreference) e' un fallback concreto, non un'ipotesi - se riesce,
        # l'IA lo preferisce gia' automaticamente al posto di Graph in quel dominio finche' non
        # esiste una sessione Graph delegata vera (stesso identico controllo
        # $graphDelegatedSessionActive gia' in uso, nessuna nuova logica di priorita' necessaria
        # qui: la sessione Graph resta assente sia che il login non sia mai stato tentato sia
        # che sia fallito per consenso, la preferenza scatta allo stesso modo in entrambi i
        # casi). Qui ci limitiamo a riconoscere il caso e segnalarlo alla GUI, che offre il
        # pulsante "Connetti CLI Microsoft 365" gia' esistente invece del solo messaggio di
        # errore generico.
        $needsAdminConsent = $result.Message -match 'AADSTS65001'
        $result | Add-Member -NotePropertyName NeedsAdminConsent -NotePropertyValue $needsAdminConsent -Force
    }

    $result
}
