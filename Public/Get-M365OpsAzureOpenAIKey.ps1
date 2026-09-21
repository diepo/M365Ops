function Get-M365OpsAzureOpenAIKey {
    <#
    .SYNOPSIS
        Restituisce la API key di Azure OpenAI/Foundry - l'UNICO punto del modulo che decide da
        dove arriva (16-21/09/2026, richiesto esplicitamente dall'utente: "key vault integration
        per foundry, con azure key vault, managed identity che puo' leggere la key vault e
        prende la chiave a runtime").
    .DESCRIPTION
        Due sorgenti, in quest'ordine:
          1. AZURE KEY VAULT (se AZURE_OPENAI_KEYVAULT_URI e' configurata): la chiave viene letta
             a runtime dal secret indicato (AZURE_OPENAI_KEYVAULT_SECRET, default
             'azure-openai-key') autenticandosi con l'identita' gestita della macchina - la
             chiave non e' MAI scritta su questo PC (ne' su file ne' in una variabile d'ambiente),
             vive solo in memoria del processo. Quando Key Vault e' configurato e' l'UNICA
             sorgente: un'eventuale AZURE_OPENAI_KEY locale rimasta viene ignorata, cosi' una
             chiave ruotata o revocata in Key Vault non puo' restare "in vita" da una copia
             dimenticata sul disco.
          2. VARIABILE D'AMBIENTE AZURE_OPENAI_KEY (comportamento storico, invariato): usata solo
             se Key Vault NON e' configurato.
        Il valore letto da Key Vault e' tenuto in cache in memoria per 15 minuti (un round di
        chat ne fa molte chiamate, una richiesta di rete a Key Vault per ciascuna sarebbe uno
        spreco e un rischio di throttling) - e si rinnova da solo alla scadenza, quindi una
        rotazione del secret viene raccolta senza riavviare l'app. Se il rinnovo fallisce per un
        motivo TRANSITORIO (rete, 429, 5xx) e c'e' ancora un valore precedente, si continua con
        quello (loggando un avviso) invece di bloccare la chat per un'interruzione passeggera;
        un errore NON transitorio (permesso revocato, secret cancellato) non viene mai mascherato
        da un valore vecchio.
    .PARAMETER ForceRefresh
        Ignora la cache e rilegge da Key Vault - usato da chi riceve un 401 da Azure OpenAI (la
        chiave in cache potrebbe essere stata ruotata nel frattempo).
    .OUTPUTS
        string - la chiave, oppure $null se nessuna sorgente e' configurata. Lancia un errore
        chiaro (mai la chiave, mai il token) se Key Vault e' configurato ma la lettura fallisce.
    #>
    param([switch]$ForceRefresh)

    $vaultUri = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEYVAULT_URI'
    if (-not $vaultUri) {
        return (Get-M365OpsSecret -Name 'AZURE_OPENAI_KEY')
    }

    $secretName = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEYVAULT_SECRET'
    if (-not $secretName) { $secretName = 'azure-openai-key' }
    $clientId = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEYVAULT_CLIENT_ID'

    $ttlMinutes = 15
    $configKey = "$vaultUri|$secretName|$clientId"
    $cache = $script:M365OpsAzureOpenAIKeyCache
    # Una cache di una CONFIGURAZIONE diversa (l'utente ha cambiato vault/secret/identita') non
    # va mai riusata - nemmeno come "valore precedente" in caso di errore transitorio.
    if ($cache -and $cache.ConfigKey -ne $configKey) { $cache = $null; $script:M365OpsAzureOpenAIKeyCache = $null }

    if (-not $ForceRefresh -and $cache -and $cache.FetchedAt -gt (Get-Date).AddMinutes(-$ttlMinutes)) {
        return $cache.Value
    }

    try {
        $value = Get-M365OpsKeyVaultSecret -VaultUri $vaultUri -SecretName $secretName -ClientId $clientId
    }
    catch {
        $isTransient = $_.Exception.Data['Transient'] -eq $true
        if ($cache -and $isTransient) {
            Write-M365OpsLog "Azure Key Vault: rinnovo della chiave Azure OpenAI non riuscito ($($_.Exception.Message)) - continuo con l'ultimo valore letto (di $([int]((Get-Date) - $cache.FetchedAt).TotalMinutes) minuti fa)." -Level Warn
            return $cache.Value
        }
        throw "Impossibile leggere la chiave Azure OpenAI da Azure Key Vault: $($_.Exception.Message)"
    }

    $script:M365OpsAzureOpenAIKeyCache = [pscustomobject]@{ ConfigKey = $configKey; Value = $value; FetchedAt = Get-Date }
    Write-M365OpsLog "Azure Key Vault: chiave Azure OpenAI letta dal secret '$secretName' del vault '$(([uri]$vaultUri).Authority)' (identita' gestita) - in cache $ttlMinutes minuti."
    $value
}
