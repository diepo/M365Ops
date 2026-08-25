function Get-M365OpsInfraDiagramNarrative {
    <#
    .SYNOPSIS
        Trasforma il diagramma di infrastruttura di un tenant (Get-M365OpsInfraDiagram: nodi
        tipizzati + collegamenti disegnati dall'operatore in GUI) in due testi pensati per l'IA:
        un riassunto breve (sempre incluso nel prompt di sistema, stesso principio della
        Knowledge Base - vedi Invoke-M365OpsAgentTools.ps1) e il testo completo, strutturato,
        restituito solo quando il tool get_tenant_infrastructure viene davvero chiamato.
    .PARAMETER Diagram
        L'oggetto restituito da Get-M365OpsInfraDiagram { Nodes; Edges; UpdatedAt }.
    .OUTPUTS
        pscustomobject { Summary; FullText } - Summary $null se il diagramma e' vuoto (nessun
        nodo ancora disegnato), cosi' il chiamante puo' decidere di non aggiungere nulla al
        prompt di sistema in quel caso, esattamente come gia' fatto per un catalogo KB vuoto.
    #>
    param([Parameter(Mandatory)] $Diagram)

    $nodes = @($Diagram.Nodes)
    $edges = @($Diagram.Edges)
    if ($nodes.Count -eq 0) {
        return [pscustomobject]@{ Summary = $null; FullText = "Nessun nodo ancora disegnato in questo diagramma." }
    }

    $byType = $nodes | Group-Object -Property type | Sort-Object Count -Descending
    $typeCounts = ($byType | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '
    $updatedText = if ($Diagram.UpdatedAt) {
        try { "ultimo aggiornamento: $(([datetime]$Diagram.UpdatedAt).ToString('dd/MM/yyyy HH:mm'))" } catch { "" }
    } else { "" }
    $summary = "$($nodes.Count) nodi ($typeCounts), $($edges.Count) collegamenti$(if ($updatedText) { " - $updatedText" })."

    $nodeById = @{}
    $nodeLines = foreach ($n in $nodes) {
        $nodeById[$n.id] = $n
        $props = @()
        if ($n.role)   { $props += "ruolo: $($n.role)" }
        if ($n.ip)     { $props += "IP: $($n.ip)" }
        if ($n.domain) { $props += "dominio: $($n.domain)" }
        if ($n.notes)  { $props += "note: $($n.notes)" }
        $propsText = if ($props.Count -gt 0) { " (" + ($props -join ', ') + ")" } else { "" }
        "- [$($n.type)] $($n.name)$propsText"
    }
    $edgeLines = foreach ($e in $edges) {
        $fromName = if ($nodeById.ContainsKey($e.from)) { $nodeById[$e.from].name } else { $e.from }
        $toName = if ($nodeById.ContainsKey($e.to)) { $nodeById[$e.to].name } else { $e.to }
        $labelText = if ($e.label) { ": $($e.label)" } else { "" }
        "- $fromName -> $toName$labelText"
    }

    $fullText = "Nodi ($($nodes.Count)):`n" + ($nodeLines -join "`n")
    if ($edgeLines.Count -gt 0) {
        $fullText += "`n`nCollegamenti ($($edges.Count)):`n" + ($edgeLines -join "`n")
    }

    [pscustomobject]@{ Summary = $summary; FullText = $fullText }
}
