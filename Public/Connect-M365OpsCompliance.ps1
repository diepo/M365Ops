function Connect-M365OpsCompliance {
    <#
    .SYNOPSIS
        Connette a Security & Compliance PowerShell (Purview) usando il tenant attivo - stesso
        modulo ExchangeOnlineManagement gia' usato per Exchange Online, ma un endpoint diverso
        (Connect-IPPSSession invece di Connect-ExchangeOnline). Stesso identico principio di
        governance di Connect-M365OpsExchange: silenziosa su AppOnly (stesso certificato), su
        Delegato richiede -AllowInteractive esplicito perche' il server e' a thread singolo e
        un login bloccante qui congelerebbe l'intera app per chiunque, non solo per chi ha
        fatto la richiesta.
    #>
    param([switch]$Force, [switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsComplianceConnected -and -not $Force) { return }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated' -and -not $AllowInteractive) {
        throw "Sessione Security & Compliance (Purview) non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab Tenant (sezione 'Stato connessioni'), Purview/Compliance, e clicca 'Connetti / Test connessione Purview' per farlo esplicitamente, poi riprova."
    }

    # Nessuna guardia preventiva (vedi Connect-M365OpsExchange.ps1 per la storia completa e il
    # perche': un blocco a priori boccerebbe anche tentativi che su questo PC funzionerebbero -
    # si prova sempre, l'eventuale conflitto viene rivestito con un messaggio chiaro solo se
    # scatta davvero).
    try {
        # Versione FISSATA a 3.4.0 - vedi Assert-M365OpsExoSafeVersion.ps1/Connect-M365OpsExchange.ps1
        # per il dettaglio completo. Assert-M365OpsExoSafeVersion (Private) disinstalla anche
        # attivamente una eventuale versione >= 3.10.0 gia' presente sul disco, installa la
        # 3.4.0 se manca, la IMPORTA (i chiamanti non lo fanno piu' separatamente) e ripara da
        # sola un'installazione locale corrotta se ne trova una.
        Assert-M365OpsExoSafeVersion

        # -ShowBanner su Connect-IPPSSession: assente su 3.1.0 (verificato dal vivo il 25/08/2026:
        # passarlo incondizionatamente dava "A parameter cannot be found that matches parameter
        # name 'ShowBanner'"), presente da 3.2.0 in poi (quindi anche su 3.4.0, il pin attuale) -
        # controllato comunque dinamicamente, come gia' fatto per -DisableWAM in
        # Connect-M365OpsTeams.ps1, invece di assumere che tutte le versioni/cmdlet del modulo
        # abbiano lo stesso set di parametri (il pin potrebbe cambiare di nuovo in futuro).
        $ippsSupportsShowBanner = (Get-Command Connect-IPPSSession).Parameters.Keys -contains 'ShowBanner'

        if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
            if (-not $script:M365OpsContext.DelegatedUpn) {
                throw "Il profilo '$($script:M365OpsContext.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
            }
            # -Device su Connect-IPPSSession NON esiste in 3.4.0 (verificato dal vivo il
            # 25/08/2026: passarlo dava "A parameter cannot be found that matches parameter name
            # 'Device'" - a differenza di Connect-ExchangeOnline, che sulla stessa versione
            # supporta gia' -AccessToken per il device-code, Connect-IPPSSession a 3.4.0 non ha
            # NESSUN flusso device-code/token, ne' per il device-code ne' per un token gia'
            # ottenuto. Ha pero' un flusso interattivo modern-auth via -UserPrincipalName da solo
            # (senza -Credential) - confermato dalla guida integrata del modulo stesso
            # ("Get-Help Connect-IPPSSession -Parameter UserPrincipalName": "allows you to skip
            # entering a username in the modern authentication credentials prompt") - un popup
            # bloccante, non un device-code in background, stesso principio gia' usato per
            # Teams/SharePoint delegati (guardia -AllowInteractive sopra, che impedisce gia' un
            # login automatico non richiesto). Sicuro dal punto di vista del conflitto Teams
            # perche' passa dalla STESSA libreria di autenticazione condivisa gia' verificata
            # pulita per Purview App-only nella stessa coppia di versioni (sezione 6.6) - non e'
            # un percorso di codice diverso, solo un modo diverso di popolare le credenziali.
            $ippsSupportsDevice = (Get-Command Connect-IPPSSession).Parameters.Keys -contains 'Device'
            $ippsParams = @{ UserPrincipalName = $script:M365OpsContext.DelegatedUpn }
            if ($ippsSupportsDevice) { $ippsParams.Device = $true }
            if ($ippsSupportsShowBanner) { $ippsParams.ShowBanner = $false }
            # Invoke-M365OpsWithExoRepairRetry (Private, 25/08/2026) - vedi
            # Connect-M365OpsExchange.ps1 per il dettaglio completo.
            Invoke-M365OpsWithExoRepairRetry { Connect-IPPSSession @ippsParams }
            $script:M365OpsComplianceConnected = $true
            return
        }

        if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
            throw "Il profilo '$($script:M365OpsContext.Name)' non ha un ExchangeCertThumbprint configurato. Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarlo."
        }

        $ippsParams = @{
            AppId               = $script:M365OpsContext.ClientId
            CertificateThumbprint = $script:M365OpsContext.ExchangeCertThumbprint
            Organization        = $script:M365OpsContext.TenantId
        }
        if ($ippsSupportsShowBanner) { $ippsParams.ShowBanner = $false }
        Invoke-M365OpsWithExoRepairRetry { Connect-IPPSSession @ippsParams }

        $script:M365OpsComplianceConnected = $true
    }
    catch {
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Purview' -OtherService 'Microsoft Teams'
        if ($hint) {
            # Isolamento reattivo (26/08/2026) - stesso worker isolato 'Exchange' usato da
            # Connect-M365OpsExchange.ps1 (il worker connette SEMPRE anche Connect-IPPSSession
            # in App-only, stesso certificato - vedi M365OpsIsolatedWorker.ps1), non un
            # secondo processo dedicato solo a Purview.
            try {
                Connect-M365OpsIsolatedModule -ModuleType 'Exchange' -ConnectParams (Get-M365OpsIsolatedConnectParams -ModuleType 'Exchange')
                $script:M365OpsComplianceConnected = $true
                Write-M365OpsLog "Purview: conflitto .NET reale rilevato, connessione riuscita tramite isolamento reattivo (processo separato) - nessun riavvio necessario."
                return
            }
            catch {
                throw $hint
            }
        }
        throw
    }
}
