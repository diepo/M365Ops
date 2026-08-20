function Set-M365OpsTenant {
    <#
    .SYNOPSIS
        Registra o aggiorna un profilo tenant in Config\tenants.json.
        NON salva mai il secret in chiaro: solo il NOME della variabile d'ambiente che lo contiene.
        Il thumbprint del certificato Exchange e l'indirizzo email mittente NON sono segreti.
        Preserva McpServers del profilo (gestiti da Set-M365OpsMcpServer) se gia' presenti.

        AuthMode 'AppOnly' (default) richiede ClientId + (SecretEnvVar O ExchangeCertThumbprint -
        uno dei due basta, sono alternativi dal 21/08/2026, vedi Get-M365OpsToken.ps1) - App
        Registration con client credentials, nessuna interazione umana necessaria dopo il setup
        iniziale.
        AuthMode 'Delegated' non richiede alcuna App Registration: usa un login interattivo
        (utente + MFA) tramite Start-M365OpsDelegatedLogin - pensato per i tenant dove non
        hai i permessi per creare un'App Registration ma hai ruoli admin delegati (Exchange
        Admin, User Admin, ecc.) sul tuo utente. Richiede DelegatedUpn.

    .EXAMPLE
        Set-M365OpsTenant -Name "contoso-test" -TenantId "contoso.onmicrosoft.com" -ClientId "00000000-..." -SecretEnvVar "M365_CLIENT_SECRET"

    .EXAMPLE
        Set-M365OpsTenant -Name "cliente-y" -TenantId "clientey.onmicrosoft.com" -AuthMode Delegated -DelegatedUpn "diego@clientey.onmicrosoft.com"
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$TenantId,
        [string]$ClientId,
        [string]$SecretEnvVar,
        [ValidateSet('AppOnly', 'Delegated')] [string]$AuthMode = 'AppOnly',
        [string]$DelegatedUpn,
        [string]$ExchangeCertThumbprint,
        [string]$EmailSender,
        [string]$SharePointInteractiveClientId
    )

    # BUG DI REGRESSIONE trovato dal vivo il 21/08/2026, segnalato dall'utente durante un test
    # su PC pulito ("ho messo appid, thumbprint etc e non salva: servono client ID e nome
    # variabile secret"): questa validazione richiedeva ANCORA -SecretEnvVar obbligatorio anche
    # dopo che Get-M365OpsToken.ps1 (v0.9.17) aveva reso il certificato un'alternativa valida al
    # secret - bloccava a monte esattamente la configurazione "solo certificato" che quella
    # funzionalita' era pensata per abilitare. Corretto: serve SecretEnvVar O
    # ExchangeCertThumbprint, non necessariamente entrambi.
    if ($AuthMode -eq 'AppOnly' -and -not $ClientId) {
        throw "AuthMode 'AppOnly' richiede -ClientId. Per un tenant senza App Registration usa -AuthMode Delegated -DelegatedUpn."
    }
    if ($AuthMode -eq 'AppOnly' -and -not $SecretEnvVar -and -not $ExchangeCertThumbprint) {
        throw "AuthMode 'AppOnly' richiede -SecretEnvVar O -ExchangeCertThumbprint (uno dei due basta - sono alternativi, non serve compilare entrambi). Senza nessuno dei due l'app non ha modo di autenticarsi verso Microsoft Graph."
    }
    if ($AuthMode -eq 'Delegated' -and -not $DelegatedUpn) {
        throw "AuthMode 'Delegated' richiede -DelegatedUpn (il tuo UPN su quel tenant, es. mario.rossi@clientex.onmicrosoft.com)."
    }

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    $config = @{}
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            $mcpServers = @{}
            if ($prop.Value.McpServers) {
                foreach ($mcpProp in $prop.Value.McpServers.PSObject.Properties) {
                    $mcpServers[$mcpProp.Name] = @{ command = $mcpProp.Value.command; args = $mcpProp.Value.args; envMapping = $mcpProp.Value.envMapping }
                }
            }
            $config[$prop.Name] = @{
                TenantId                      = $prop.Value.TenantId
                ClientId                      = $prop.Value.ClientId
                SecretEnvVar                  = $prop.Value.SecretEnvVar
                AuthMode                      = if ($prop.Value.AuthMode) { $prop.Value.AuthMode } else { 'AppOnly' }
                DelegatedUpn                  = $prop.Value.DelegatedUpn
                ExchangeCertThumbprint        = $prop.Value.ExchangeCertThumbprint
                EmailSender                   = $prop.Value.EmailSender
                SharePointInteractiveClientId = $prop.Value.SharePointInteractiveClientId
                McpServers                    = $mcpServers
            }
        }
    }

    $existing = $config[$Name]
    $config[$Name] = @{
        TenantId                      = $TenantId
        ClientId                      = $ClientId
        SecretEnvVar                  = $SecretEnvVar
        AuthMode                      = $AuthMode
        DelegatedUpn                  = $DelegatedUpn
        ExchangeCertThumbprint        = if ($ExchangeCertThumbprint) { $ExchangeCertThumbprint } elseif ($existing) { $existing.ExchangeCertThumbprint } else { $null }
        EmailSender                   = if ($EmailSender) { $EmailSender } elseif ($existing) { $existing.EmailSender } else { $null }
        # Client ID dell'app Entra ID registrata con Register-PnPEntraIDAppForInteractiveLogin
        # per il login SharePoint sui tenant Delegati (sezione 17.10 della guida) - vedi
        # Sync-M365OpsSharePointAppRegistration per come viene scoperto/popolato in automatico.
        SharePointInteractiveClientId = if ($SharePointInteractiveClientId) { $SharePointInteractiveClientId } elseif ($existing) { $existing.SharePointInteractiveClientId } else { $null }
        McpServers                    = if ($existing -and $existing.McpServers) { $existing.McpServers } else { @{} }
    }

    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
    Write-Host "Profilo '$Name' salvato in $configPath [$AuthMode] (nessun secret scritto su disco)." -ForegroundColor Green
}
