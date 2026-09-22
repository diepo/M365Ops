function Get-M365OpsFoundryToken {
    <#
    .SYNOPSIS
        Access token Entra ID per chiamare Microsoft Foundry Agent Service - scope
        https://ai.azure.com/.default. Verificato sulla documentazione ufficiale Microsoft il
        22/09/2026 (non a memoria): l'Agent Service NON supporta le chiavi API, SOLO Entra ID
        ("Agents service | API key: No | Microsoft Entra ID: Yes" - tabella "Feature support
        matrix", authentication-authorization-foundry). Richiesto esplicitamente dall'utente:
        "iuntegra la possibilita' di chiamare un agent da foundry... mi pare tu debba usare
        projects sdk e la api key non sia supportata, prevedi anche questo".
    .DESCRIPTION
        Due modi di ottenere il token, in quest'ordine:
          1. Client credentials con la STESSA App Registration gia' usata per Graph/Exchange
             (client secret, o l'assertion JWT col certificato se il secret non e' disponibile -
             identico a Get-M365OpsToken.ps1, stesso principio, scope diverso) - funziona su
             QUALUNQUE PC, non richiede una VM/server Azure. Serve pero' che l'App Registration
             abbia il ruolo RBAC "Foundry Agent Consumer" assegnato sul progetto Foundry (Azure
             RBAC, non un permesso API Graph - un passaggio a parte, vedi la guida). Disponibile
             solo su tenant AppOnly (un tenant Delegato non ha un client secret dell'app).
          2. Identita' gestita (Get-M365OpsManagedIdentityToken, stessa funzione gia' costruita
             per Azure Key Vault, qui con Resource 'https://ai.azure.com') - unico modo su un
             tenant Delegato, e alternativa comunque valida su AppOnly se e' quella preferita
             (es. l'app gira su una VM Azure con identita' gestita invece che con l'App
             Registration del tenant M365).
        Se nessuno dei due e' disponibile, l'errore spiega ENTRAMBI i motivi (non solo l'ultimo
        tentato), cosi' l'utente capisce quale via attivare invece di vedere un errore generico.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $ctx = $script:M365OpsContext
    $scope = 'https://ai.azure.com/.default'

    $cacheKey = "$($ctx.Name)|foundry"
    if (-not $script:M365OpsFoundryTokenCache) { $script:M365OpsFoundryTokenCache = @{} }
    $cached = $script:M365OpsFoundryTokenCache[$cacheKey]
    if ($cached -and $cached.ExpiresAt -gt (Get-Date).AddSeconds(60)) { return $cached.AccessToken }

    $clientCredError = $null
    if ($ctx.AuthMode -ne 'Delegated') {
        $tokenEndpoint = "https://login.microsoftonline.com/$($ctx.TenantId)/oauth2/v2.0/token"
        $secret = if ($ctx.SecretEnvVar) { Get-M365OpsSecret -Name $ctx.SecretEnvVar } else { $null }
        try {
            $tokenResponse = if ($secret) {
                Invoke-RestMethod -Method POST -Uri $tokenEndpoint -Body @{
                    grant_type = "client_credentials"; client_id = $ctx.ClientId; client_secret = $secret; scope = $scope
                } -ErrorAction Stop
            } elseif ($ctx.ExchangeCertThumbprint) {
                $assertion = New-M365OpsCertificateAssertion -Thumbprint $ctx.ExchangeCertThumbprint -ClientId $ctx.ClientId -TokenEndpoint $tokenEndpoint
                Invoke-RestMethod -Method POST -Uri $tokenEndpoint -Body @{
                    grant_type = "client_credentials"; client_id = $ctx.ClientId
                    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"; client_assertion = $assertion; scope = $scope
                } -ErrorAction Stop
            } else {
                throw "nessun secret ne' certificato configurato sul profilo tenant"
            }
            $script:M365OpsFoundryTokenCache[$cacheKey] = @{ AccessToken = $tokenResponse.access_token; ExpiresAt = (Get-Date).AddSeconds([int]$tokenResponse.expires_in) }
            return $tokenResponse.access_token
        } catch {
            # AADSTS7000215/70011 ecc. su un'app senza il ruolo Foundry assegnato NON falliscono
            # qui (il token si ottiene comunque, Entra non sa nulla dei ruoli Foundry) - falliscono
            # dopo, alla vera chiamata, con un 403 Foundry: quello e' gestito da Invoke-M365OpsFoundryAgent.
            $clientCredError = $_.Exception.Message
        }
    } else {
        $clientCredError = "tenant '$($ctx.Name)' in modalita' Delegated: nessun client secret dell'app disponibile per un token applicativo"
    }

    try {
        $mi = Get-M365OpsManagedIdentityToken -Resource 'https://ai.azure.com'
        $script:M365OpsFoundryTokenCache[$cacheKey] = @{ AccessToken = $mi.AccessToken; ExpiresAt = $mi.ExpiresOn.ToLocalTime() }
        return $mi.AccessToken
    } catch {
        throw "Impossibile ottenere un token per Microsoft Foundry Agent Service: client credentials non disponibili ($clientCredError); identita' gestita non disponibile ($($_.Exception.Message)). Serve UNA delle due - vedi la sezione 'Agent Foundry' della guida."
    }
}
