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

    # Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore, riprodotto live, non solo
    # per lettura): storico chat e Knowledge Base sono salvati su disco con un nome file
    # derivato da $Name tramite $Name -replace '[^\w\-]', '_' (stessa regex ripetuta identica
    # in Get-M365OpsChatHistory/Add-M365OpsChatHistoryTurn/Clear-M365OpsChatHistory/
    # Add-M365OpsKnowledgeDocument/Remove-M365OpsKnowledgeDocument/Get-M365OpsKnowledgeCatalog/
    # Get-M365OpsKnowledgeDocumentText) - questa regex NON e' iniettiva: "North West" e
    # "North_West", o "Contoso.Test" e "Contoso Test", si riducono allo STESSO nome file
    # ("North_West"/"Contoso_Test"), riprodotto dal vivo. Due profili tenant DIVERSI con nomi
    # che collidono solo dopo la sanitizzazione finirebbero quindi a condividere lo stesso file
    # di storico chat/Knowledge Base - lo storico conversazionale (e i documenti caricati) di
    # un tenant diventerebbero visibili/mescolati nell'altro, esattamente la classe di fuga di
    # dati tra tenant gia' corretta per $script:LastReportPath in Connect-M365Ops.ps1. Bloccato
    # qui, all'origine (la creazione del profilo), invece di in ognuna delle sette funzioni che
    # leggono/scrivono quei file - un profilo che AGGIORNA se stesso (nome gia' esistente
    # identico) resta sempre permesso, solo un nome NUOVO che collide con un profilo DIVERSO
    # gia' salvato viene rifiutato.
    if (-not $existing) {
        $safeName = $Name -replace '[^\w\-]', '_'
        $collidingProfile = $config.Keys | Where-Object { $_ -ne $Name -and ($_ -replace '[^\w\-]', '_') -eq $safeName } | Select-Object -First 1
        if ($collidingProfile) {
            throw "Il nome profilo '$Name' si riduce allo stesso nome file interno di un profilo GIA' ESISTENTE, '$collidingProfile' (entrambi diventano '$safeName' una volta tolti spazi/punteggiatura) - storico chat e Knowledge Base finirebbero mescolati tra i due tenant. Scegli un nome diverso (es. con un trattino o senza spazi/punti)."
        }
    }

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
