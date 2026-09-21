function Get-M365OpsKeyVaultSecret {
    <#
    .SYNOPSIS
        Legge il valore di un secret da Azure Key Vault (REST diretto, nessun modulo Az/
        SecretManagement da installare) autenticandosi con l'identita' gestita di questa
        macchina/servizio - vedi Get-M365OpsManagedIdentityToken per le varianti supportate.
    .PARAMETER VaultUri
        URI del vault, es. "https://miovault.vault.azure.net". Accettati solo host Key Vault
        (public cloud, Cina, US Gov) e SOLO https - un token portato in chiaro su http o verso
        un host qualunque sarebbe una fuga di credenziali; l'unica eccezione e' il loopback
        (localhost/127.0.0.1), che non esce mai dalla macchina - serve ai test di questa funzione.
    .PARAMETER SecretName
        Nome del secret (solo lettere, cifre, trattino - regola di Key Vault).
    .PARAMETER ClientId
        Client ID di un'identita' gestita user-assigned (opzionale).
    .OUTPUTS
        string - il valore del secret. MAI scritto nei log ne' in un messaggio d'errore.
    .NOTES
        Gli errori portano nella proprieta' Data['Transient'] = $true quando sono transitori
        (rete, 429, 5xx) - il chiamante puo' cosi' distinguere "Key Vault momentaneamente
        irraggiungibile" (ha senso continuare con l'ultimo valore noto) da "permesso negato/
        secret inesistente" (non ha senso: va corretta la configurazione).
    #>
    param(
        [Parameter(Mandatory)] [string]$VaultUri,
        [Parameter(Mandatory)] [string]$SecretName,
        [string]$ClientId
    )

    if ($SecretName -notmatch '^[0-9a-zA-Z-]{1,127}$') {
        throw "Nome secret Key Vault non valido: '$SecretName' (ammessi solo lettere, cifre e trattino, max 127 caratteri)."
    }

    $uriObj = $null
    if (-not [System.Uri]::TryCreate($VaultUri.Trim(), [System.UriKind]::Absolute, [ref]$uriObj)) {
        throw "URI Key Vault non valido: '$VaultUri' (atteso es. https://miovault.vault.azure.net)."
    }
    $hostName = $uriObj.Host.ToLowerInvariant()
    $isLoopback = $hostName -in @('localhost', '127.0.0.1', '[::1]', '::1')
    $resource = $null
    if ($hostName -like '*.vault.azure.net')         { $resource = 'https://vault.azure.net' }
    elseif ($hostName -like '*.vault.azure.cn')      { $resource = 'https://vault.azure.cn' }
    elseif ($hostName -like '*.vault.usgovcloudapi.net') { $resource = 'https://vault.usgovcloudapi.net' }
    elseif ($isLoopback)                             { $resource = 'https://vault.azure.net' }
    else {
        throw "Host Key Vault non riconosciuto: '$hostName' (attesi *.vault.azure.net, *.vault.azure.cn o *.vault.usgovcloudapi.net - un Managed HSM non contiene secret)."
    }
    if ($uriObj.Scheme -ne 'https' -and -not $isLoopback) {
        throw "URI Key Vault non sicuro: '$VaultUri' - il token verrebbe inviato in chiaro. Usa https://."
    }

    $base = "$($uriObj.Scheme)://$($uriObj.Authority)"
    $secretUri = "$base/secrets/${SecretName}?api-version=7.4"
    $vaultLabel = $uriObj.Authority

    $fail = {
        param([string]$Message, [bool]$Transient)
        $ex = [System.InvalidOperationException]::new($Message)
        $ex.Data['Transient'] = $Transient
        throw $ex
    }

    $forceTokenRefresh = $false
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $token = Get-M365OpsManagedIdentityToken -Resource $resource -ClientId $ClientId -ForceRefresh:$forceTokenRefresh

        try {
            $response = Invoke-WebRequest -Uri $secretUri -Headers @{ Authorization = "Bearer $($token.AccessToken)" } -TimeoutSec 15 -SkipHttpErrorCheck -ErrorAction Stop
        }
        catch {
            & $fail "Key Vault '$vaultLabel' non raggiungibile: $($_.Exception.Message)" $true
        }

        $status = [int]$response.StatusCode
        $body = $null
        try { $body = $response.Content | ConvertFrom-Json -ErrorAction Stop } catch { }

        if ($status -eq 200) {
            if ($null -eq $body -or $null -eq $body.value -or [string]::IsNullOrWhiteSpace([string]$body.value)) {
                & $fail "Il secret '$SecretName' su Key Vault '$vaultLabel' esiste ma e' vuoto." $false
            }
            return [string]$body.value
        }

        $kvCode = $body.error.code
        $kvMessage = $body.error.message

        # 401: token rifiutato (scaduto lato servizio, o cache di token non piu' valida) - un solo
        # nuovo tentativo con un token FRESCO prima di dichiarare il fallimento.
        if ($status -eq 401 -and $attempt -eq 1) { $forceTokenRefresh = $true; continue }

        switch ($status) {
            401 { & $fail "Key Vault '$vaultLabel' ha rifiutato il token dell'identita' gestita (401 $kvCode): $kvMessage" $false }
            403 { & $fail "Accesso negato al secret '$SecretName' su Key Vault '$vaultLabel' (403 $kvCode). L'identita' gestita ($($token.Hosting)) non ha il permesso di LETTURA sui secret: assegnale il ruolo RBAC 'Key Vault Secrets User' sul vault (o sul singolo secret), oppure una access policy con permesso 'Get' sui secret. Se il vault ha il firewall attivo, la rete di questa macchina deve essere ammessa. Dettaglio Azure: $kvMessage" $false }
            404 { & $fail "Secret '$SecretName' non trovato su Key Vault '$vaultLabel' (404 $kvCode) - controlla nome del secret e URI del vault. $kvMessage" $false }
            { $_ -eq 429 -or $_ -ge 500 } { & $fail "Key Vault '$vaultLabel' momentaneamente non disponibile (HTTP $status $kvCode): $kvMessage" $true }
            default { & $fail "Key Vault '$vaultLabel': risposta inattesa HTTP $status $kvCode $kvMessage" $false }
        }
    }
}
