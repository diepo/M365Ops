function Sync-M365OpsSharePointAppRegistration {
    <#
    .SYNOPSIS
        Scopre se l'App Registration dedicata al login SharePoint interattivo
        ("M365Ops SharePoint", creata con Register-PnPEntraIDAppForInteractiveLogin) esiste
        gia' nel tenant attivo - se si', ne legge il Client ID via Graph e lo salva da solo nel
        profilo del tenant (Set-M365OpsTenant), senza bisogno di copiare/incollare il GUID a
        mano. Se non esiste ancora, restituisce il comando esatto da eseguire una tantum per
        crearla, con il dominio del tenant attivo gia' compilato.
    .NOTES
        Storia reale (17/08/2026): serviva un'App Registration DEDICATA per il login SharePoint
        sui tenant Delegati perche' Microsoft ha ritirato il client pubblico condiviso "PnP
        Management Shell" dal 9 settembre 2024 (Register-PnPManagementShellAccess stesso lo
        conferma con un errore esplicito) - ogni tenant deve registrare la propria app. Prima
        di questa funzione, il Client ID andava copiato a mano nel profilo tenant - richiesto
        esplicitamente un discovery automatico invece del passaggio manuale.

        Richiede una connessione Graph (AppOnly: sempre disponibile via certificato; Delegato:
        di norma serve prima "Accedi con il mio utente" nel tab Tenant, MA vedi eccezione sotto).

        ECCEZIONE - CLI Microsoft 365 come sostituto (23/08/2026, bug reale segnalato dal vivo
        dall'utente: su un tenant Delegato con SOLO CLI Microsoft 365 connesso, SharePoint
        rifiutava di connettersi con "Nessuna sessione delegata attiva", anche se l'unico vero
        bisogno di Graph qui e' cercare l'app "M365Ops SharePoint" per NOME una tantum - un
        bisogno che CLI Microsoft 365 puo' soddisfare altrettanto bene, in modo completamente
        indipendente dalla sessione Graph generica, se e' gia' connesso (stesso principio gia'
        applicato alle letture/scritture generiche in Invoke-M365OpsAgentTools.ps1 - "trattalo
        come equivalente a Graph laddove ha possibilita'"). Su un tenant Delegato senza sessione
        Graph generica attiva, prova PRIMA 'm365 entra app get --name' (verificato dal vivo con
        'm365 entra app get --help' il 23/08/2026, non indovinato) se CLI Microsoft 365 e'
        configurato - solo se anche questo fallisce, arriva l'errore originale che chiede il
        login Graph generico. Una volta trovato, il Client ID si salva nel profilo come sempre:
        questa intera ricerca serve solo la PRIMA volta per tenant, mai piu' dopo.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    $appName = 'M365Ops SharePoint'
    $tenantDomain = if ($script:M365OpsContext.TenantId -match '^[\w-]+\.onmicrosoft\.com$') {
        $script:M365OpsContext.TenantId
    } else {
        try {
            $org = Invoke-M365OpsGraphRequest -Method GET -Path "/organization?`$select=verifiedDomains"
            $org.value[0].verifiedDomains | Where-Object { $_.isInitial } | Select-Object -First 1 -ExpandProperty name
        } catch { $null }
    }
    $registerCmd = "Register-PnPEntraIDAppForInteractiveLogin -ApplicationName `"$appName`" -Tenant $tenantDomain"

    # Sessione Graph generica attiva? Solo rilevante per capire se conviene provare CLI365
    # PRIMA di Graph su un tenant Delegato (vedi .NOTES) - su AppOnly Graph e' sempre
    # disponibile via certificato, questo controllo resta $true e non cambia nulla.
    $graphDelegatedSessionActive = $true
    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        $cachedDelegated = $script:M365OpsTokenCache[$script:M365OpsContext.Name]
        $graphDelegatedSessionActive = [bool]($cachedDelegated -and $cachedDelegated.Delegated -and ($cachedDelegated.Delegated.AccessToken -or $cachedDelegated.Delegated.RefreshToken))
    }

    $app = $null
    $cliM365Attempted = $false
    if (-not $graphDelegatedSessionActive) {
        $cliM365Configured = $false
        try { $cliM365Configured = [bool](Get-M365OpsMcpServers | Where-Object { $_.Name -eq 'CLI-Microsoft365' }) } catch { }
        if ($cliM365Configured) {
            $cliM365Attempted = $true
            try {
                $cliResult = Invoke-M365OpsMcpServerTool -ServerName 'CLI-Microsoft365' -ToolName 'm365_run_command' -Arguments @{ command = "m365 entra app get --name `"$appName`"" }
                $cliText = ($cliResult.content | ForEach-Object { $_.text }) -join "`n"
                $cliApp = $cliText | ConvertFrom-Json -ErrorAction Stop
                if ($cliApp.appId) { $app = [pscustomobject]@{ appId = $cliApp.appId; displayName = $cliApp.displayName } }
            } catch {
                # Nessuna app trovata con questo nome, o CLI365 stesso non disponibile/non
                # connesso - non e' un errore fatale qui, si prova comunque il percorso Graph
                # sotto (che dara' il messaggio originale, chiaro, se fallisce anche lui).
            }
        }
    }

    if (-not $app) {
        try {
            $result = Invoke-M365OpsGraphRequest -Method GET -Path "/applications?`$filter=displayName eq '$appName'&`$select=appId,displayName"
            $app = $result.value | Select-Object -First 1
        }
        catch {
            if ($cliM365Attempted) {
                return [pscustomobject]@{
                    Found  = $false
                    Status = 'Error'
                    Message = "Impossibile verificare se l'app '$appName' esiste: ne' la sessione Graph generica ne' CLI Microsoft 365 (gia' provato) sono riusciti a cercarla. Su Delegato fai prima 'Accedi con il mio utente' nel tab Tenant, oppure verifica che CLI Microsoft 365 sia davvero connesso per questo tenant: $($_.Exception.Message)"
                }
            }
            return [pscustomobject]@{
                Found  = $false
                Status = 'Error'
                Message = "Impossibile verificare se l'app '$appName' esiste (serve una connessione Graph attiva - su Delegato fai prima 'Accedi con il mio utente', oppure connetti CLI Microsoft 365 per questo tenant come alternativa): $($_.Exception.Message)"
            }
        }
    }
    if (-not $app) {
        return [pscustomobject]@{
            Found   = $false
            Status  = 'NotFound'
            Message = "App '$appName' non trovata in questo tenant. Registrala una tantum da un terminale PowerShell 7 normale (non dal pulsante della GUI):`n$registerCmd`nPoi riprova - verra' rilevata e salvata in automatico."
        }
    }

    # Trovata: salva il Client ID nel profilo persistito, riusando gli altri campi gia'
    # esistenti (Set-M365OpsTenant richiede sempre i campi obbligatori del proprio AuthMode,
    # non solo quello nuovo che stiamo aggiornando qui).
    $setParams = @{
        Name                          = $script:M365OpsContext.Name
        TenantId                      = $script:M365OpsContext.TenantId
        AuthMode                      = $script:M365OpsContext.AuthMode
        SharePointInteractiveClientId = $app.appId
    }
    if ($script:M365OpsContext.AuthMode -eq 'AppOnly') {
        $setParams.ClientId = $script:M365OpsContext.ClientId
        $setParams.SecretEnvVar = $script:M365OpsContext.SecretEnvVar
    } else {
        $setParams.DelegatedUpn = $script:M365OpsContext.DelegatedUpn
    }
    if ($script:M365OpsContext.ExchangeCertThumbprint) { $setParams.ExchangeCertThumbprint = $script:M365OpsContext.ExchangeCertThumbprint }
    if ($script:M365OpsContext.EmailSender) { $setParams.EmailSender = $script:M365OpsContext.EmailSender }

    Set-M365OpsTenant @setParams | Out-Null
    # Aggiorna anche il contesto in memoria, cosi' Connect-M365OpsSharePoint lo vede SUBITO
    # senza richiedere una riattivazione del profilo (Connect-M365Ops) per prendere effetto.
    $script:M365OpsContext.SharePointInteractiveClientId = $app.appId

    [pscustomobject]@{
        Found    = $true
        Status   = 'Saved'
        ClientId = $app.appId
        Message  = "App '$appName' trovata (Client ID $($app.appId)) e salvata nel profilo '$($script:M365OpsContext.Name)'."
    }
}
