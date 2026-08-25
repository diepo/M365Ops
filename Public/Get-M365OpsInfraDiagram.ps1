function Get-M365OpsInfraDiagram {
    <#
    .SYNOPSIS
        Legge il diagramma di infrastruttura (nodi/collegamenti disegnati dall'operatore in GUI:
        Domain Controller, Entra Connect, sedi, firewall, ecc.) salvato in locale per il tenant
        indicato (Config\InfraDiagram-<TenantName>.json). Stesso schema di isolamento per-tenant
        gia' in uso per lo storico chat (Get-M365OpsChatHistory) e la Knowledge Base
        (Get-M365OpsKnowledgeCatalog) - nessun modo di leggere il diagramma di un altro tenant
        passando un TenantName diverso.
    .PARAMETER TenantName
        Determina ESCLUSIVAMENTE quale file leggere.
    .OUTPUTS
        Un pscustomobject { Nodes; Edges; UpdatedAt } - array vuoti e UpdatedAt $null se il
        tenant non ha ancora mai salvato un diagramma, o se il file e' corrotto (stesso principio
        difensivo di Get-M365OpsChatHistory: un file di comodita' rotto non deve mai bloccare la
        GUI, solo apparire come "nessun diagramma ancora").
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $safeName = $TenantName -replace '[^\w\-]', '_'
    $path = Join-Path $script:M365OpsModuleRoot "Config\InfraDiagram-$safeName.json"
    $empty = [pscustomobject]@{ Nodes = @(); Edges = @(); UpdatedAt = $null }
    if (-not (Test-Path $path)) { return $empty }

    try {
        $raw = Get-Content -Path $path -Raw -ErrorAction Stop
        if (-not $raw) { return $empty }
        $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        [pscustomobject]@{
            Nodes     = @($parsed.nodes)
            Edges     = @($parsed.edges)
            UpdatedAt = $parsed.updatedAt
        }
    }
    catch {
        $empty
    }
}
