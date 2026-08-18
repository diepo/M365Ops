function Sync-M365OpsSharePointAppRegistration {
    <#
    .SYNOPSIS
        Scopre se l'App Registration dedicata al login SharePoint interattivo
        ("M365Ops SharePoint", creata con Register-PnPEntraIDAppForInteractiveLogin) esiste
        gia' nel tenant attivo - se si', ne legge il Client ID via Graph e lo salva da solo nel
        profilo del tenant (Set-M365OpsTenant), senza bisogno di copiare/incollare il GUID a
        mano. Se non esiste ancora, restituisce il comando esatto da eseguire una tantum per
        crearla, con il dominio del tenant attivo gia' compilato.
    .NOTES
        Storia reale (17/08/2026): serviva un'App Registration DEDICATA per il login SharePoint
        sui tenant Delegati perche' Microsoft ha ritirato il client pubblico condiviso "PnP
        Management Shell" dal 9 settembre 2024 (Register-PnPManagementShellAccess stesso lo
        conferma con un errore esplicito) - ogni tenant deve registrare la propria app. Prima
        di questa funzione, il Client ID andava copiato a mano nel profilo tenant - richiesto
        esplicitamente un discovery automatico invece del passaggio manuale.

        Richiede una connessione Graph gia' attiva sul tenant corrente (AppOnly: sempre
        disponibile via certificato; Delegato: serve prima "Accedi con il mio utente" nel tab
        Tenant) - usa Application.Read.All, gia' incluso negli scope del login delegato
        generico di questo modulo.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    $appName = 'M365Ops SharePoint'
    $tenantDomain = if ($script:M365OpsContext.TenantId -match '^[\w-]+\.onmicrosoft\.com$') {
        $script:M365OpsContext.TenantId
    } else {
        try {
            $org = Invoke-M365OpsGraphRequest -Method GET -Path "/organization?`$select=verifiedDomains"
            $org.value[0].verifiedDomains | Where-Object { $_.isInitial } | Select-Object -First 1 -ExpandProperty name
        } catch { $null }
    }
    $registerCmd = "Register-PnPEntraIDAppForInteractiveLogin -ApplicationName `"$appName`" -Tenant $tenantDomain"

    try {
        $result = Invoke-M365OpsGraphRequest -Method GET -Path "/applications?`$filter=displayName eq '$appName'&`$select=appId,displayName"
    }
    catch {
        return [pscustomobject]@{
            Found  = $false
            Status = 'Error'
            Message = "Impossibile verificare se l'app '$appName' esiste (serve una connessione Graph attiva - su Delegato fai prima 'Accedi con il mio utente'): $($_.Exception.Message)"
        }
    }

    $app = $result.value | Select-Object -First 1
    if (-not $app) {
        return [pscustomobject]@{
            Found   = $false
            Status  = 'NotFound'
            Message = "App '$appName' non trovata in questo tenant. Registrala una tantum da un terminale PowerShell 7 normale (non dal pulsante della GUI):`n$registerCmd`nPoi riprova - verra' rilevata e salvata in automatico."
        }
    }

    # Trovata: salva il Client ID nel profilo persistito, riusando gli altri campi gia'
    # esistenti (Set-M365OpsTenant richiede sempre i campi obbligatori del proprio AuthMode,
    # non solo quello nuovo che stiamo aggiornando qui).
    $setParams = @{
        Name                          = $script:M365OpsContext.Name
        TenantId                      = $script:M365OpsContext.TenantId
        AuthMode                      = $script:M365OpsContext.AuthMode
        SharePointInteractiveClientId = $app.appId
    }
    if ($script:M365OpsContext.AuthMode -eq 'AppOnly') {
        $setParams.ClientId = $script:M365OpsContext.ClientId
        $setParams.SecretEnvVar = $script:M365OpsContext.SecretEnvVar
    } else {
        $setParams.DelegatedUpn = $script:M365OpsContext.DelegatedUpn
    }
    if ($script:M365OpsContext.ExchangeCertThumbprint) { $setParams.ExchangeCertThumbprint = $script:M365OpsContext.ExchangeCertThumbprint }
    if ($script:M365OpsContext.EmailSender) { $setParams.EmailSender = $script:M365OpsContext.EmailSender }

    Set-M365OpsTenant @setParams | Out-Null
    # Aggiorna anche il contesto in memoria, cosi' Connect-M365OpsSharePoint lo vede SUBITO
    # senza richiedere una riattivazione del profilo (Connect-M365Ops) per prendere effetto.
    $script:M365OpsContext.SharePointInteractiveClientId = $app.appId

    [pscustomobject]@{
        Found    = $true
        Status   = 'Saved'
        ClientId = $app.appId
        Message  = "App '$appName' trovata (Client ID $($app.appId)) e salvata nel profilo '$($script:M365OpsContext.Name)'."
    }
}
