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
        # Conflitto noto MicrosoftTeams/ExchangeOnlineManagement, riprodotto dal vivo il
        # 22/08/2026 esattamente su QUESTA funzione (il messaggio d'errore dell'utente -
        # "Could not load file or assembly ...Microsoft.IdentityModel.Abstractions...
        # manifest definition does not match" - corrisponde esattamente) - vedi
        # Connect-M365OpsExchange.ps1 per il dettaglio completo. Controllato PRIMA di
        # importare il modulo, cosi' l'utente vede un messaggio chiaro invece del criptico
        # errore .NET nativo che aveva causato un blocco/crash apparente del server.
        if ($script:M365OpsTeamsModuleImported) {
            return [pscustomobject]@{ Status = 'Error'; Message = "Token ottenuto ma il modulo MicrosoftTeams e' gia' caricato in questo processo server, e i due moduli portano versioni incompatibili delle stesse librerie di autenticazione - conflitto noto e documentato di Microsoft (non un bug di M365Ops), senza soluzione lato modulo. Riavvia il server (pulsante Manutenzione, o 'M365Ops - Termina e riavvia' sul Desktop se non risponde) per liberare il processo e riprova il login Exchange da capo." }
        }
        try {
            # Fallback di auto-installazione (22/08/2026, bug reale segnalato dal vivo: login
            # delegato riuscito, poi fallito qui con "no valid module file was found" su un PC
            # senza il modulo) - Install-M365OpsPrerequisites lo installa gia' in anticipo al
            # primo avvio, questo resta solo come rete di sicurezza se quel passaggio e' stato
            # saltato o e' fallito, stesso principio gia' in Connect-M365OpsExchange.ps1 (che
            # pero' non passa mai da QUESTA funzione, da cui il buco originale).
            # Versione FISSATA a 3.9.0, confermata conflict-free con MicrosoftTeams (23/08/2026)
            # - vedi Connect-M365OpsExchange.ps1 per il dettaglio completo della verifica dal
            # vivo (con -AccessToken, il percorso usato proprio qui sotto, gia' testato presente
            # su 3.9.0). Assert-M365OpsExoSafeVersion (Private) disinstalla anche attivamente una
            # eventuale versione >= 3.10.0 gia' presente sul disco, non solo installa la 3.9.0 se
            # manca.
            $script:M365OpsExoSafeVersion = '3.9.0'
            Assert-M365OpsExoSafeVersion
            Import-Module ExchangeOnlineManagement -RequiredVersion $script:M365OpsExoSafeVersion -ErrorAction Stop
            $script:M365OpsExchangeModuleImported = $true
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
