function Get-M365OpsManagedIdentityToken {
    <#
    .SYNOPSIS
        Ottiene un access token Entra ID per una risorsa Azure (es. Key Vault) usando l'IDENTITA'
        GESTITA della macchina/servizio su cui gira questo processo - nessun secret, nessuna
        password, nessun login: e' Azure stesso a rilasciare il token a chi gira su una risorsa
        con un'identita' gestita assegnata (16-21/09/2026, richiesto esplicitamente dall'utente
        per l'integrazione Key Vault: "managed identity che puo' leggere la key vault e prende la
        chiave a runtime").
    .DESCRIPTION
        L'endpoint da chiamare dipende da DOVE gira il processo - le tre varianti supportate
        (stesse dell'SDK Azure.Identity ufficiale, stesso ordine di rilevamento):
          1. App Service / Functions / Container Apps: variabili IDENTITY_ENDPOINT +
             IDENTITY_HEADER (header X-IDENTITY-HEADER).
          2. Azure Arc (server fisico/on-prem registrato in Arc): IDENTITY_ENDPOINT + IMDS_ENDPOINT
             senza IDENTITY_HEADER - protocollo a sfida: la prima richiesta riceve 401 con il
             percorso di un file-chiave locale nell'header WWW-Authenticate, il cui contenuto va
             rimandato come Authorization: Basic (il file e' leggibile solo da admin locali o dal
             gruppo "Hybrid Agent Extension Applications").
          3. Macchina virtuale Azure: IMDS a 169.254.169.254 (override con la variabile standard
             AZURE_POD_IDENTITY_AUTHORITY_HOST, la stessa riconosciuta dagli SDK Azure - serve ad
             ambienti con proxy IMDS e ai test locali di questa funzione).
        Su un PC che non e' nessuna delle tre (es. un portatile fisico non registrato in Arc)
        l'identita' gestita NON esiste: la funzione lo dice chiaramente invece di un generico
        timeout di rete.
    .PARAMETER Resource
        Audience del token, es. "https://vault.azure.net".
    .PARAMETER ClientId
        Solo per un'identita' gestita USER-ASSIGNED: il suo Client ID. Vuoto = identita'
        system-assigned (o l'unica user-assigned presente). Arc supporta solo system-assigned.
    .PARAMETER ForceRefresh
        Ignora la cache e chiede un token nuovo (usato dopo un 401 dal servizio a valle).
    .OUTPUTS
        pscustomobject { AccessToken; ExpiresOn (UTC); Hosting = 'AppService'|'Arc'|'AzureVM' }.
        Il token NON viene mai scritto nei log ne' in nessun messaggio d'errore.
    .NOTES
        Richiede PowerShell 7 (-SkipHttpErrorCheck, -NoProxy) - il runtime reale di questo
        progetto (vedi Launch-M365Ops.ps1), non Windows PowerShell 5.1.
    #>
    param(
        [Parameter(Mandatory)] [string]$Resource,
        [string]$ClientId,
        [switch]$ForceRefresh
    )

    if (-not $script:M365OpsManagedIdentityTokenCache) { $script:M365OpsManagedIdentityTokenCache = @{} }
    $cacheKey = "$Resource|$ClientId"
    $cached = $script:M365OpsManagedIdentityTokenCache[$cacheKey]
    # Margine di 5 minuti: mai consegnare un token che scade mentre lo si sta usando.
    if (-not $ForceRefresh -and $cached -and $cached.ExpiresOn -gt (Get-Date).ToUniversalTime().AddMinutes(5)) {
        return $cached
    }

    $identityEndpoint = [System.Environment]::GetEnvironmentVariable('IDENTITY_ENDPOINT', 'Process')
    $identityHeader   = [System.Environment]::GetEnvironmentVariable('IDENTITY_HEADER', 'Process')
    $imdsEndpoint     = [System.Environment]::GetEnvironmentVariable('IMDS_ENDPOINT', 'Process')
    $encResource = [System.Uri]::EscapeDataString($Resource)
    $encClientId = if ($ClientId) { [System.Uri]::EscapeDataString($ClientId) } else { $null }

    $hosting = $null
    $requests = $null   # scriptblock che esegue la richiesta reale e restituisce la risposta

    if ($identityEndpoint -and $identityHeader) {
        $hosting = 'AppService'
        $uri = "${identityEndpoint}?api-version=2019-08-01&resource=$encResource" + $(if ($encClientId) { "&client_id=$encClientId" } else { '' })
        $requests = { Invoke-WebRequest -Uri $uri -Headers @{ 'X-IDENTITY-HEADER' = $identityHeader } -NoProxy -TimeoutSec 10 -SkipHttpErrorCheck -ErrorAction Stop }
    }
    elseif ($identityEndpoint -and $imdsEndpoint) {
        $hosting = 'Arc'
        if ($ClientId) { throw "Azure Arc supporta solo l'identita' gestita system-assigned - il Client ID '$ClientId' (user-assigned) non e' utilizzabile su questa macchina. Lascia vuoto il campo Client ID." }
        $uri = "${identityEndpoint}?api-version=2020-06-01&resource=$encResource"
        $requests = {
            $first = Invoke-WebRequest -Uri $uri -Headers @{ Metadata = 'true' } -NoProxy -TimeoutSec 10 -SkipHttpErrorCheck -ErrorAction Stop
            if ($first.StatusCode -ne 401) { return $first }
            # Sfida Arc: il percorso del file-chiave e' nell'header WWW-Authenticate ("Basic realm=<percorso>").
            $challenge = [string]($first.Headers['WWW-Authenticate'] | Select-Object -First 1)
            if ($challenge -notmatch 'realm=(?<path>.+)$') {
                throw "Azure Arc ha risposto 401 senza la sfida attesa (header WWW-Authenticate mancante o inatteso)."
            }
            $keyFile = $Matches['path'].Trim('"', ' ')
            try { $arcKey = (Get-Content -Path $keyFile -Raw -ErrorAction Stop).Trim() }
            catch { throw "Azure Arc: impossibile leggere il file-chiave dell'identita' gestita ($keyFile) - l'utente che esegue M365Ops deve essere amministratore locale o membro del gruppo 'Hybrid Agent Extension Applications'. Dettaglio: $($_.Exception.Message)" }
            Invoke-WebRequest -Uri $uri -Headers @{ Metadata = 'true'; Authorization = "Basic $arcKey" } -NoProxy -TimeoutSec 10 -SkipHttpErrorCheck -ErrorAction Stop
        }
    }
    else {
        $hosting = 'AzureVM'
        $imdsBase = [System.Environment]::GetEnvironmentVariable('AZURE_POD_IDENTITY_AUTHORITY_HOST', 'Process')
        if (-not $imdsBase) { $imdsBase = 'http://169.254.169.254' }
        $uri = "$($imdsBase.TrimEnd('/'))/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encResource" + $(if ($encClientId) { "&client_id=$encClientId" } else { '' })
        # IMDS e' raggiungibile SOLO dall'interno della VM, e deve bypassare qualunque proxy
        # (indicazione esplicita della documentazione Azure) - timeout breve: su un PC non-Azure
        # l'indirizzo non risponde affatto, e non deve far aspettare l'utente piu' del necessario.
        $requests = { Invoke-WebRequest -Uri $uri -Headers @{ Metadata = 'true' } -NoProxy -TimeoutSec 5 -SkipHttpErrorCheck -ErrorAction Stop }
    }

    $response = $null
    $lastFailure = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $response = & $requests
        }
        catch {
            if ($_.Exception.Message -like 'Azure Arc*') { throw }
            $lastFailure = $_.Exception.Message
            if ($hosting -eq 'AzureVM') {
                throw "Identita' gestita non disponibile: nessun endpoint IMDS raggiungibile ($lastFailure). L'identita' gestita esiste SOLO su una VM Azure, un server registrato in Azure Arc o un servizio Azure (App Service/Functions/Container Apps) con un'identita' gestita assegnata - su un PC normale non c'e'."
            }
            throw "Identita' gestita ($hosting): endpoint non raggiungibile ($lastFailure)."
        }
        # 410/429/5xx sono transitori per IMDS (indicazione della documentazione Azure: ritentare
        # con attesa crescente) - qualunque altro esito non cambia ritentando.
        if (($response.StatusCode -in @(410, 429)) -or ($response.StatusCode -ge 500)) {
            if ($attempt -lt 3) { Start-Sleep -Seconds $attempt; continue }
        }
        break
    }

    $body = $null
    try { $body = $response.Content | ConvertFrom-Json -ErrorAction Stop } catch { }

    if ($response.StatusCode -ne 200 -or -not $body -or -not $body.access_token) {
        $detail = if ($body.error_description) { $body.error_description } elseif ($body.error) { $body.error } elseif ($body.message) { $body.message } else { "risposta HTTP $($response.StatusCode) senza dettaglio" }
        $hint = if ($response.StatusCode -eq 400 -and $hosting -eq 'AzureVM') { " Nessuna identita' gestita assegnata a questa VM (o il Client ID indicato non e' assegnato ad essa): assegnane una dal portale Azure, VM > Identity." } else { '' }
        throw "Identita' gestita ($hosting): richiesta del token fallita (HTTP $($response.StatusCode)): $detail.$hint"
    }

    $expires = $null
    if ($body.expires_on -match '^\d+$') {
        $expires = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$body.expires_on).UtcDateTime
    } elseif ($body.expires_on) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse([string]$body.expires_on, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { $expires = $parsed }
    }
    if (-not $expires) {
        $seconds = if ($body.expires_in -match '^\d+$') { [int]$body.expires_in } else { 3000 }
        $expires = (Get-Date).ToUniversalTime().AddSeconds($seconds)
    }

    $result = [pscustomobject]@{ AccessToken = [string]$body.access_token; ExpiresOn = $expires; Hosting = $hosting }
    $script:M365OpsManagedIdentityTokenCache[$cacheKey] = $result
    $result
}
