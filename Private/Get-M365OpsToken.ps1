function Get-M365OpsToken {
    <#
    .SYNOPSIS
        Restituisce un access token Graph per il tenant attivo. In modalita' AppOnly (default)
        e' client credentials, senza interazione umana - con client secret se disponibile,
        altrimenti con lo stesso certificato usato per Exchange (vedi sotto). In modalita'
        Delegated usa il token dell'utente ottenuto con Start-M365OpsDelegatedLogin (richiede
        login interattivo completato in precedenza - vedi Get-M365OpsDelegatedToken).
    .NOTES
        Autenticazione via certificato invece del secret (21/08/2026, richiesto esplicitamente
        dall'utente): Microsoft Entra ID supporta client credentials con un JWT "client
        assertion" firmato dal certificato dell'app al posto del client secret (RFC 7523,
        stesso meccanismo usato da Connect-ExchangeOnline -CertificateThumbprint per Exchange
        Online) - un solo materiale segreto (il certificato) per entrambe le aree invece di
        due (secret per Graph, certificato per Exchange). Se il profilo tenant ha un secret
        configurato E RISOLVIBILE (variabile d'ambiente/registro), quello resta la scelta
        di default per compatibilita' con ogni installazione esistente - il certificato viene
        usato solo quando il secret non e' disponibile ma un ExchangeCertThumbprint si',
        MAI come sostituzione silenziosa di un secret gia' funzionante.
    #>
    if (-not $script:M365OpsContext) {
        throw "Nessun tenant attivo. Usa Connect-M365Ops -TenantProfile <nome> prima."
    }

    $ctx = $script:M365OpsContext

    if ($ctx.AuthMode -eq 'Delegated') {
        return Get-M365OpsDelegatedToken -Context $ctx
    }

    $cacheKey = $ctx.Name
    $cached = $script:M365OpsTokenCache[$cacheKey]
    if ($cached -and $cached.ExpiresAt -gt (Get-Date).AddSeconds(60)) {
        return $cached.AccessToken
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$($ctx.TenantId)/oauth2/v2.0/token"
    $secret = if ($ctx.SecretEnvVar) { Get-M365OpsSecret -Name $ctx.SecretEnvVar } else { $null }

    if ($secret) {
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenEndpoint -Body @{
            grant_type    = "client_credentials"
            client_id     = $ctx.ClientId
            client_secret = $secret
            scope         = "https://graph.microsoft.com/.default"
        }
    }
    elseif ($ctx.ExchangeCertThumbprint) {
        $assertion = New-M365OpsCertificateAssertion -Thumbprint $ctx.ExchangeCertThumbprint -ClientId $ctx.ClientId -TokenEndpoint $tokenEndpoint
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenEndpoint -Body @{
            grant_type            = "client_credentials"
            client_id             = $ctx.ClientId
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion      = $assertion
            scope                 = "https://graph.microsoft.com/.default"
        }
    }
    else {
        throw "Nessuna credenziale disponibile per '$($ctx.Name)': secret non trovato nella variabile d'ambiente '$($ctx.SecretEnvVar)' e nessun thumbprint certificato configurato nel profilo tenant. Imposta uno dei due (Impostazioni tenant)."
    }

    $script:M365OpsTokenCache[$cacheKey] = @{
        AccessToken = $tokenResponse.access_token
        ExpiresAt   = (Get-Date).AddSeconds([int]$tokenResponse.expires_in)
    }

    return $tokenResponse.access_token
}
