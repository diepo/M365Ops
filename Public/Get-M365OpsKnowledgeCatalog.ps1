function Get-M365OpsKnowledgeCatalog {
    <#
    .SYNOPSIS
        Elenco (solo metadati: titolo, argomenti, riassunto - MAI il testo completo) dei
        documenti caricati nella Knowledge Base del tenant indicato. Pensato per essere incluso
        per intero nel prompt di sistema ad ogni messaggio (costo trascurabile, nessuna chiamata
        AI aggiuntiva) - per il testo completo di UN documento specifico vedi
        Get-M365OpsKnowledgeDocumentText.
    .PARAMETER TenantName
        Determina ESCLUSIVAMENTE quale catalogo leggere (Config\KnowledgeBase-<TenantName>.json)
        - stesso schema di isolamento di Get-M365OpsChatHistory, nessuna possibilita' di leggere
        il catalogo di un altro tenant passando un nome diverso.
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $safeName = $TenantName -replace '[^\w\-]', '_'
    $catalogPath = Join-Path $script:M365OpsModuleRoot "Config\KnowledgeBase-$safeName.json"
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
