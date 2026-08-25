function Get-M365OpsTenantStorageKey {
    <#
    .SYNOPSIS
        Dato il NOME di un profilo tenant (Config\tenants.json), restituisce la chiave da usare
        per lo storage per-tenant di Documentazione (Knowledge Base) e Diagramma infrastruttura -
        il Tenant ID reale risolto in forma canonica (Resolve-M365OpsTenantGuid), non il nome del
        profilo. Sostituisce il vecchio schema "un file per ogni NOME PROFILO" (richiesto
        esplicitamente dall'utente il 25/08/2026): due profili con modalita' di accesso diverse
        (es. uno AppOnly, uno Delegato - caso reale gia' presente in questo progetto: "vnsys-test"
        e "vnsys delegata" hanno lo stesso TenantId "vnsysit.onmicrosoft.com") sullo STESSO
        tenant reale condividono ora automaticamente la stessa documentazione/diagramma, invece
        di vederne due copie separate e vuote.
    .PARAMETER TenantName
        Nome del profilo (es. "vnsys-test") - oppure un valore che NON corrisponde a nessun
        profilo reale (es. "_global", il bucket KB globale riservato di Add-M365OpsKnowledgeDocument):
        in quel caso restituito invariato (sanificato), nessuna risoluzione tentata - non c'e'
        nulla da risolvere per un bucket che non e' un tenant vero.
    .NOTES
        Lo storico chat (Get-M365OpsChatHistory) NON usa questa funzione - resta deliberatamente
        per-PROFILO: una conversazione e' legata alla sessione/modalita' di lavoro attiva in quel
        momento (AppOnly vs Delegato possono avere permessi/contesto diversi), non al tenant in
        astratto, a differenza della documentazione che descrive il tenant a prescindere da come
        ci si e' collegati in quel momento.
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\tenants.json'
    $rawTenantId = $null
    if (Test-Path $configPath) {
        try {
            $profiles = Get-Content $configPath -Raw | ConvertFrom-Json
            $match = $profiles.PSObject.Properties | Where-Object { $_.Name -eq $TenantName } | Select-Object -First 1
            if ($match -and $match.Value.TenantId) { $rawTenantId = $match.Value.TenantId }
        }
        catch { }
    }

    $key = if ($rawTenantId) { Resolve-M365OpsTenantGuid -TenantIdOrDomain $rawTenantId } else { $TenantName }
    $key -replace '[^\w\-]', '_'
}
