function Get-M365OpsToken {
    <#
    .SYNOPSIS
        Restituisce un access token Graph per il tenant attivo. In modalita' AppOnly (default)
        e' client credentials, senza interazione umana. In modalita' Delegated usa il token
        dell'utente ottenuto con Start-M365OpsDelegatedLogin (richiede login interattivo
        completato in precedenza - vedi Get-M365OpsDelegatedToken).
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

    $secret = Get-M365OpsSecret -Name $ctx.SecretEnvVar
    if (-not $secret) {
        throw "Secret non trovato nella variabile d'ambiente '$($ctx.SecretEnvVar)'. Impostala con setx e apri un nuovo terminale, oppure verifica il nome nel profilo tenant."
    }

    $tokenResponse = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($ctx.TenantId)/oauth2/v2.0/token" -Body @{
        grant_type    = "client_credentials"
        client_id     = $ctx.ClientId
        client_secret = $secret
        scope         = "https://graph.microsoft.com/.default"
    }

    $script:M365OpsTokenCache[$cacheKey] = @{
        AccessToken = $tokenResponse.access_token
        ExpiresAt   = (Get-Date).AddSeconds([int]$tokenResponse.expires_in)
    }

    return $tokenResponse.access_token
}
