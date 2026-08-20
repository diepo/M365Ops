function Complete-M365OpsExchangeDelegatedLogin {
    <#
    .SYNOPSIS
        UN singolo tentativo di verifica che l'utente abbia completato il login Exchange
        avviato con Start-M365OpsExchangeDelegatedLogin - pensata per essere chiamata
        ripetutamente (polling) dalla GUI. Finche' il login non e' completato, ogni chiamata
        e' rapida (una sola richiesta HTTP di verifica, Status=Pending). Solo quando il
        token e' pronto viene chiamato Connect-ExchangeOnline -AccessToken (rapido, nessuna
        interazione umana necessaria a quel punto) per stabilire la sessione PowerShell vera
        e propria - questo e' l'unico momento in cui questa funzione puo' impiegare qualche
        secondo in piu' del solito, mai piu' di questo.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $pending = $script:M365OpsPendingExoDeviceCode[$tenantName]
    if (-not $pending) {
        return [pscustomobject]@{ Status = 'Error'; Message = "Nessun login Exchange in corso per '$tenantName' - avvialo prima con Start-M365OpsExchangeDelegatedLogin." }
    }
    if ((Get-Date) -gt $pending.ExpiresAt) {
        $script:M365OpsPendingExoDeviceCode.Remove($tenantName)
        return [pscustomobject]@{ Status = 'Error'; Message = "Codice scaduto - riavvia il login." }
    }

    $result = Receive-M365OpsDeviceCodeToken -TenantId $script:M365OpsContext.TenantId -DeviceCode $pending.DeviceCode -ClientId $script:M365OpsExoDeviceCodeClientId

    if ($result.Status -eq 'Completed') {
        $script:M365OpsPendingExoDeviceCode.Remove($tenantName)
        try {
            # Fallback di auto-installazione (22/08/2026, bug reale segnalato dal vivo: login
            # delegato riuscito, poi fallito qui con "no valid module file was found" su un PC
            # senza il modulo) - Install-M365OpsPrerequisites lo installa gia' in anticipo al
            # primo avvio, questo resta solo come rete di sicurezza se quel passaggio e' stato
            # saltato o e' fallito, stesso principio gia' in Connect-M365OpsExchange.ps1 (che
            # pero' non passa mai da QUESTA funzione, da cui il buco originale).
            if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
                Write-Host "Modulo ExchangeOnlineManagement non trovato, lo installo..." -ForegroundColor Yellow
                Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            }
            Import-Module ExchangeOnlineManagement -ErrorAction Stop
            Connect-ExchangeOnline -AccessToken $result.AccessToken -UserPrincipalName $script:M365OpsContext.DelegatedUpn -ShowBanner:$false -ErrorAction Stop
            $script:M365OpsExchangeConnected = $true
            Write-Host "Exchange Online (delegato) connesso per '$tenantName'." -ForegroundColor Green
        }
        catch {
            return [pscustomobject]@{ Status = 'Error'; Message = "Token ottenuto ma la connessione a Exchange e' fallita: $($_.Exception.Message)" }
        }
    }
    elseif ($result.Status -eq 'Error') {
        $script:M365OpsPendingExoDeviceCode.Remove($tenantName)
    }

    $result
}
