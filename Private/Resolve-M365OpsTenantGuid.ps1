function Resolve-M365OpsTenantGuid {
    <#
    .SYNOPSIS
        Risolve un identificativo di tenant Microsoft 365/Entra ID (dominio, es.
        "contoso.onmicrosoft.com", O gia' un GUID) al suo Tenant ID GUID canonico, interrogando
        l'endpoint pubblico di discovery OIDC di Microsoft (login.microsoftonline.com/<id>/v2.0/
        .well-known/openid-configuration) - nessuna autenticazione richiesta, e' un endpoint
        pubblico pensato apposta per questo, il campo "issuer" della risposta contiene sempre il
        GUID canonico indipendentemente da quale forma e' stata usata per interrogarlo.
    .PARAMETER TenantIdOrDomain
        Dominio o GUID del tenant, cosi' come scritto nel campo TenantId di un profilo
        (Config\tenants.json).
    .NOTES
        Richiesta esplicitamente dall'utente il 25/08/2026: due profili tenant possono riferirsi
        allo STESSO tenant reale ma con TenantId scritto in forme diverse (uno come dominio,
        l'altro come GUID) - senza risolvere entrambi alla stessa forma canonica, Documentazione/
        Diagramma infrastruttura (che usano il Tenant ID risolto come chiave di storage, vedi
        Get-M365OpsTenantStorageKey) resterebbero duplicati invece di essere condivisi per lo
        stesso tenant fisico.

        Cache in-memory per processo ($script:M365OpsTenantGuidCache) - una sola chiamata di
        rete per ciascun valore grezzo distinto durante la vita del processo server, non una ad
        ogni domanda in chat (dove la chiave di storage viene ricalcolata ad ogni round per
        includere il riassunto del diagramma/KB nel prompt di sistema).

        Fallback SEMPRE al valore grezzo in ingresso se la risoluzione fallisce (rete assente,
        timeout, formato non valido, tenant inesistente) - mai un'eccezione che romperebbe la
        lettura di Documentazione/Diagramma: nel caso peggiore la condivisione tra profili con lo
        stesso tenant reale semplicemente non scatta finche' la rete non torna, ma nulla si
        rompe o si perde (i file restano leggibili con la chiave usata l'ultima volta).
    #>
    param([Parameter(Mandatory)] [string]$TenantIdOrDomain)

    if (-not $script:M365OpsTenantGuidCache) { $script:M365OpsTenantGuidCache = @{} }
    if ($script:M365OpsTenantGuidCache.ContainsKey($TenantIdOrDomain)) {
        return $script:M365OpsTenantGuidCache[$TenantIdOrDomain]
    }

    $resolved = $TenantIdOrDomain
    try {
        $encoded = [uri]::EscapeDataString($TenantIdOrDomain)
        $resp = Invoke-RestMethod -Method GET -Uri "https://login.microsoftonline.com/$encoded/v2.0/.well-known/openid-configuration" -TimeoutSec 8 -ErrorAction Stop
        # L'issuer e' sempre nella forma "https://login.microsoftonline.com/<GUID>/v2.0" - lo
        # stesso GUID canonico a prescindere che l'URL sopra sia stato interrogato col dominio o
        # gia' col GUID (idempotente: risolvere un GUID gia' canonico restituisce se stesso).
        if ($resp.issuer -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $resolved = $Matches[1].ToLowerInvariant()
        }
    }
    catch {
        Write-M365OpsLog "Risoluzione Tenant ID '$TenantIdOrDomain' fallita (rete o formato non valido) - uso il valore grezzo come chiave di storage: $($_.Exception.Message)" -Level Warn
    }

    $script:M365OpsTenantGuidCache[$TenantIdOrDomain] = $resolved
    $resolved
}
