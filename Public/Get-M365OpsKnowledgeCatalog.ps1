function Get-M365OpsKnowledgeCatalog {
    <#
    .SYNOPSIS
        Elenco (solo metadati: titolo, argomenti, riassunto - MAI il testo completo) dei
        documenti caricati nella Knowledge Base del tenant indicato. Pensato per essere incluso
        per intero nel prompt di sistema ad ogni messaggio (costo trascurabile, nessuna chiamata
        AI aggiuntiva) - per il testo completo di UN documento specifico vedi
        Get-M365OpsKnowledgeDocumentText.
    .PARAMETER TenantName
        Nome del PROFILO - la chiave di storage reale e' pero' il Tenant ID risolto (vedi
        Get-M365OpsKnowledgeBasePaths, 25/08/2026: due profili sullo stesso tenant reale
        condividono la stessa Knowledge Base), nessuna possibilita' comunque di leggere quella
        di un tenant DIVERSO.
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $catalogPath = (Get-M365OpsKnowledgeBasePaths -TenantName $TenantName).CatalogPath
    if (-not (Test-Path $catalogPath)) { return @() }

    try {
        $raw = Get-Content -Path $catalogPath -Raw -ErrorAction Stop
        if (-not $raw) { return @() }
        return @(ConvertFrom-Json -InputObject $raw -ErrorAction Stop | Where-Object { $_.FileName })
    }
    catch {
        # Stesso principio difensivo di Get-M365OpsChatHistory: un catalogo corrotto non deve
        # mai bloccare la chat, solo apparire vuoto finche' non viene ricaricato un documento.
        return @()
    }
}
