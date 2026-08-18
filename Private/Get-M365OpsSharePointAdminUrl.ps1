function Get-M365OpsSharePointAdminUrl {
    <#
    .SYNOPSIS
        Deriva l'URL del centro di amministrazione SharePoint del tenant attivo
        (es. 'contoso.onmicrosoft.com' -> 'https://contoso-admin.sharepoint.com').
    .NOTES
        Bug reale corretto il 17/08/2026: la prima versione assumeva che
        $script:M365OpsContext.TenantId fosse SEMPRE nel formato 'xxxxx.onmicrosoft.com' (vero
        per contoso-test) e si limitava a togliere il suffisso - ma un profilo puo' avere TenantId
        salvato come GUID puro (vero per Fabrikam-Prod, es. 'a1b2c3d4-...'), producendo un hostname
        senza senso ('https://a1b2c3d4-...-admin.sharepoint.com', non risolvibile via DNS) e
        quindi ogni chiamata SharePoint falliva ancora prima del permesso/autenticazione.
        Ora: se il TenantId e' gia' nel formato dominio, usato direttamente (percorso veloce,
        nessuna chiamata di rete); altrimenti si risolve il dominio iniziale verificato
        (quello *.onmicrosoft.com originale, sempre presente) via Microsoft Graph
        /organization - funziona sia in AppOnly sia in Delegated, usa lo stesso
        Invoke-M365OpsGraphRequest gia' usato da tutto il resto del modulo. Risultato
        cache-ato per tenant (nome profilo), una sola chiamata Graph per sessione.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    if (-not $script:M365OpsSharePointDomainCache) { $script:M365OpsSharePointDomainCache = @{} }
    $cacheKey = $script:M365OpsContext.Name
    if ($script:M365OpsSharePointDomainCache[$cacheKey]) {
        return "https://$($script:M365OpsSharePointDomainCache[$cacheKey])-admin.sharepoint.com"
    }

    if ($script:M365OpsContext.TenantId -match '^[\w-]+\.onmicrosoft\.com$') {
        $prefix = ($script:M365OpsContext.TenantId -replace '\.onmicrosoft\.com$', '')
    }
    else {
        # TenantId non e' nel formato dominio (es. un GUID) - risolve il dominio iniziale
        # verificato reale invece di indovinarlo da un valore che non lo contiene.
        $org = Invoke-M365OpsGraphRequest -Method GET -Path "/organization?`$select=verifiedDomains"
        $initialDomain = $org.value[0].verifiedDomains | Where-Object { $_.isInitial } | Select-Object -First 1 -ExpandProperty name
        if (-not $initialDomain) { throw "Impossibile determinare il dominio *.onmicrosoft.com del tenant da /organization - verifica manualmente l'URL del centro di amministrazione SharePoint." }
        $prefix = ($initialDomain -replace '\.onmicrosoft\.com$', '')
    }

    $script:M365OpsSharePointDomainCache[$cacheKey] = $prefix
    "https://$prefix-admin.sharepoint.com"
}
