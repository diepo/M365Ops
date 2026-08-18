<#
    Flusso OAuth2 device code per l'autenticazione DELEGATA (utente + MFA), usato dai tenant
    con AuthMode = 'Delegated' - dove non e' disponibile un'App Registration propria.
    Usa il client pubblico multi-tenant di Microsoft "Microsoft Graph Command Line Tools"
    (id ben noto, presente di default in ogni tenant, nessuna registrazione da fare noi).
    Nessun segreto coinvolto: e' un client pubblico per design, l'unico fattore di sicurezza
    e' il login interattivo dell'utente stesso (con MFA) sul dispositivo Microsoft.
#>

$script:M365OpsDeviceCodeClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
# Elenco scope rivisto il 15/08/2026 dopo aver trovato piu' volte lo stesso problema: uno
# scope non richiesto qui produce un 403 che sembra "manca il consenso admin per un'app
# estranea" ma in realta' e' solo che il token non l'ha mai chiesto (Organization.Read.All
# per il report licenze e' stato il primo caso reale). graph_api_call/propose_graph_write
# (Invoke-M365OpsAgentTools) sono generici verso QUALUNQUE endpoint Graph - la loro stessa
# descrizione promette dispositivi/utenti/gruppi/mailbox/licenze/Teams/log di sign-in, quindi
# lo scope deve coprire davvero tutto questo, non solo cio' che i cmdlet dedicati usano oggi.
# Scritture ad alto raggio d'azione (RoleManagement.ReadWrite.Directory - assegna/revoca ruoli
# admin; Policy.ReadWrite.ConditionalAccess - un CA sbagliato blocca fuori l'intero tenant;
# Application.ReadWrite.All - puo' creare credenziali su un'app) sono ESCLUSE di proposito:
# vanno aggiunte solo su richiesta esplicita per una funzionalita' reale, non "perche' possibile".
# UserAuthenticationMethod.ReadWrite.All aggiunto il 15/08/2026: bug reale, era gia'
# documentato come richiesto nei commenti di Get-M365OpsUserMfaStatus.ps1/Reset-M365OpsUserMfa.ps1
# ma non era mai stato messo QUI - causava un 403 "Request Authorization failed" su
# /authentication/methods anche con il ruolo Entra corretto, perche' il token non lo
# conteneva affatto (stesso identico problema gia' visto con Organization.Read.All).
$script:M365OpsDeviceCodeScopes = 'https://graph.microsoft.com/DeviceManagementManagedDevices.Read.All https://graph.microsoft.com/DeviceManagementConfiguration.ReadWrite.All https://graph.microsoft.com/DeviceManagementApps.ReadWrite.All https://graph.microsoft.com/Group.ReadWrite.All https://graph.microsoft.com/User.ReadWrite.All https://graph.microsoft.com/UserAuthenticationMethod.ReadWrite.All https://graph.microsoft.com/Directory.Read.All https://graph.microsoft.com/Organization.Read.All https://graph.microsoft.com/AuditLog.Read.All https://graph.microsoft.com/RoleManagement.Read.Directory https://graph.microsoft.com/Reports.Read.All https://graph.microsoft.com/Sites.Read.All https://graph.microsoft.com/Application.Read.All https://graph.microsoft.com/SecurityEvents.Read.All https://graph.microsoft.com/Policy.Read.All https://graph.microsoft.com/Team.ReadBasic.All https://graph.microsoft.com/Channel.ReadBasic.All https://graph.microsoft.com/Mail.Send offline_access'

# Client pubblico usato internamente dal modulo ExchangeOnlineManagement per il proprio
# flusso -Device (id estratto ed verificato empiricamente dal .dll del modulo, non a memoria -
# il client "legacy" a volte citato online, a0c73c16-..., risulta disabilitato sui tenant
# moderni). Usato SOLO per ottenere un token per Exchange Online via device code in modo non
# bloccante (vedi Start-M365OpsExchangeDelegatedLogin) - la connessione PowerShell vera e
# propria avviene poi con Connect-ExchangeOnline -AccessToken, che e' invece rapida.
$script:M365OpsExoDeviceCodeClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'
$script:M365OpsExoDeviceCodeScopes = 'https://outlook.office365.com/.default offline_access'

function Start-M365OpsDeviceCodeFlow {
    <#
    .SYNOPSIS
        Avvia il flusso device code per il tenant indicato: restituisce il codice e l'URL
        che l'utente deve aprire per autenticarsi. Non blocca in attesa del login - il
        completamento va verificato con Receive-M365OpsDeviceCodeToken (polling).
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [string]$ClientId = $script:M365OpsDeviceCodeClientId,
        [string]$Scope = $script:M365OpsDeviceCodeScopes
    )

    try {
        $response = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" -Body @{
            client_id = $ClientId
            scope     = $Scope
        } -ErrorAction Stop
    }
    catch {
        # Bug reale (17/08/2026): senza questo, un 400 da Azure AD arriva al chiamante come
        # "Response status code does not indicate success: 400 (Bad Request)" - il messaggio
        # generico di .NET, che NON include il vero codice errore AADSTS (es. client
        # sconosciuto, scope non valido per quel client, consenso admin richiesto). PowerShell
        # popola il corpo reale della risposta in $_.ErrorDetails.Message sugli errori HTTP -
        # va estratto esplicitamente, altrimenti si perde silenziosamente.
        $detail = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "Richiesta device code fallita (client_id=$ClientId, scope=$Scope): $detail"
    }

    [pscustomobject]@{
        DeviceCode      = $response.device_code
        UserCode        = $response.user_code
        VerificationUri = $response.verification_uri
        ExpiresAt       = (Get-Date).AddSeconds([int]$response.expires_in)
        Interval        = [int]$response.interval
    }
}

function Receive-M365OpsDeviceCodeToken {
    <#
    .SYNOPSIS
        UN singolo tentativo di scambio device_code -> token (polling esterno, non blocca
        qui). Restituisce Status: Pending (l'utente non ha ancora completato il login),
        Completed (token ottenuto) o Error.
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$DeviceCode,
        [string]$ClientId = $script:M365OpsDeviceCodeClientId
    )

    try {
        $response = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body @{
            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
            client_id   = $ClientId
            device_code = $DeviceCode
        } -ErrorAction Stop

        return [pscustomobject]@{
            Status       = 'Completed'
            AccessToken  = $response.access_token
            RefreshToken = $response.refresh_token
            ExpiresAt    = (Get-Date).AddSeconds([int]$response.expires_in)
        }
    }
    catch {
        $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($errorBody -and $errorBody.error -eq 'authorization_pending') {
            return [pscustomobject]@{ Status = 'Pending' }
        }
        if ($errorBody -and $errorBody.error -eq 'authorization_declined') {
            return [pscustomobject]@{ Status = 'Error'; Message = 'Accesso rifiutato dall''utente.' }
        }
        if ($errorBody -and $errorBody.error -eq 'expired_token') {
            return [pscustomobject]@{ Status = 'Error'; Message = 'Codice scaduto - riavvia il login.' }
        }
        return [pscustomobject]@{ Status = 'Error'; Message = if ($errorBody.error_description) { $errorBody.error_description } else { $_.Exception.Message } }
    }
}

function Get-M365OpsDelegatedToken {
    <#
    .SYNOPSIS
        Restituisce un access token DELEGATO valido per il tenant attivo, usando il refresh
        token in cache se il precedente e' scaduto. Non fa mai login interattivo qui - se
        non c'e' nessuna sessione delegata attiva, l'errore chiede esplicitamente di avviarla
        con Start-M365OpsDelegatedLogin.
    #>
    param([Parameter(Mandatory)] [hashtable]$Context)

    $cacheKey = $Context.Name
    $cached = $script:M365OpsTokenCache[$cacheKey]

    if ($cached -and $cached.Delegated -and $cached.Delegated.ExpiresAt -gt (Get-Date).AddSeconds(60)) {
        return $cached.Delegated.AccessToken
    }

    if ($cached -and $cached.Delegated -and $cached.Delegated.RefreshToken) {
        try {
            $response = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($Context.TenantId)/oauth2/v2.0/token" -Body @{
                grant_type    = "refresh_token"
                client_id     = $script:M365OpsDeviceCodeClientId
                refresh_token = $cached.Delegated.RefreshToken
                scope         = $script:M365OpsDeviceCodeScopes
            } -ErrorAction Stop

            if (-not $script:M365OpsTokenCache[$cacheKey]) { $script:M365OpsTokenCache[$cacheKey] = @{} }
            $script:M365OpsTokenCache[$cacheKey].Delegated = @{
                AccessToken  = $response.access_token
                RefreshToken = $response.refresh_token
                ExpiresAt    = (Get-Date).AddSeconds([int]$response.expires_in)
            }
            return $response.access_token
        }
        catch {
            # Il refresh token puo' essere scaduto/revocato - richiede un nuovo login interattivo.
        }
    }

    throw "Nessuna sessione delegata attiva per '$($Context.Name)'. Avvia il login dal tab Tenant ('Accedi con il mio utente') prima di usare questo tenant."
}
