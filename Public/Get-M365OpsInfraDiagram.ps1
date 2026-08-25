function Get-M365OpsInfraDiagram {
    <#
    .SYNOPSIS
        Legge il diagramma di infrastruttura (nodi/collegamenti disegnati dall'operatore in GUI:
        Domain Controller, Entra Connect, sedi, firewall, ecc.) salvato in locale per il tenant
        indicato (Config\InfraDiagram-<chiave tenant>.json, vedi Get-M365OpsInfraDiagramPath).
        Isolamento per TENANT REALE, non per profilo (25/08/2026, richiesto esplicitamente
        dall'utente): due profili diversi sullo stesso tenant (es. AppOnly + Delegato) condividono
        lo stesso diagramma - nessun modo di leggere quello di un tenant DIVERSO passando un
        TenantName di un profilo che punta altrove.
    .PARAMETER TenantName
        Nome del PROFILO (non del tenant) - usato per risolvere la chiave di storage reale
        tramite Get-M365OpsInfraDiagramPath.
    .OUTPUTS
        Un pscustomobject { Nodes; Edges; UpdatedAt } - array vuoti e UpdatedAt $null se il
        tenant non ha ancora mai salvato un diagramma, o se il file e' corrotto (stesso principio
        difensivo di Get-M365OpsChatHistory: un file di comodita' rotto non deve mai bloccare la
        GUI, solo apparire come "nessun diagramma ancora").
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $path = Get-M365OpsInfraDiagramPath -TenantName $TenantName
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
