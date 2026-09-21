function Test-M365OpsAzureOpenAIKeyVault {
    <#
    .SYNOPSIS
        Verifica DAL VIVO l'intera catena Key Vault -> chiave Azure OpenAI: identita' gestita ->
        token -> lettura del secret. Restituisce esito e diagnostica leggibile, MAI la chiave
        (solo la sua lunghezza) ne' il token. Costa una lettura reale di Key Vault - da chiamare
        solo su azione esplicita dell'utente (pulsante "Verifica Key Vault" in GUI, o a mano da
        una shell), mai in polling automatico.
    .OUTPUTS
        pscustomobject { Ok; Configured; Message; Vault; SecretName; Hosting; PrincipalId; KeyLength }.
        PrincipalId (claim 'oid' del token, decodificato SOLO per mostrarlo - nessuna validazione
        della firma, non e' una decisione di sicurezza) e' l'identita' a cui assegnare il ruolo
        'Key Vault Secrets User' se la lettura fallisce con 403.
    #>
    $vaultUri = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEYVAULT_URI'
    if (-not $vaultUri) {
        return [pscustomobject]@{
            Ok = $false; Configured = $false; Vault = $null; SecretName = $null; Hosting = $null; PrincipalId = $null; KeyLength = $null
            Message = "Key Vault non configurato (AZURE_OPENAI_KEYVAULT_URI vuota): la chiave viene letta dalla variabile d'ambiente AZURE_OPENAI_KEY."
        }
    }
    $secretName = Get-M365OpsSecret -Name 'AZURE_OPENAI_KEYVAULT_SECRET'
    if (-not $secretName) { $secretName = 'azure-openai-key' }
    $vaultLabel = try { ([uri]$vaultUri).Authority } catch { $vaultUri }

    try {
        $key = Get-M365OpsAzureOpenAIKey -ForceRefresh
    }
    catch {
        return [pscustomobject]@{
            Ok = $false; Configured = $true; Vault = $vaultLabel; SecretName = $secretName; Hosting = $null; PrincipalId = $null; KeyLength = $null
            Message = $_.Exception.Message
        }
    }

    # Il token e' gia' in cache dopo la lettura riuscita - da li' si ricavano hosting e identita'.
    $hosting = $null; $principal = $null
    $tokenEntry = $script:M365OpsManagedIdentityTokenCache.Values | Select-Object -First 1
    if ($tokenEntry) {
        $hosting = $tokenEntry.Hosting
        try {
            $payload = $tokenEntry.AccessToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
            $payload = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
            $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)) | ConvertFrom-Json
            $principal = $claims.oid
        } catch { }
    }

    [pscustomobject]@{
        Ok = $true; Configured = $true; Vault = $vaultLabel; SecretName = $secretName; Hosting = $hosting; PrincipalId = $principal; KeyLength = $key.Length
        Message = "Chiave letta da Key Vault '$vaultLabel' (secret '$secretName', $($key.Length) caratteri) tramite identita' gestita [$hosting]$(if ($principal) { ", identita' $principal" })."
    }
}
