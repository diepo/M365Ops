function Set-M365OpsInfraDiagram {
    <#
    .SYNOPSIS
        Salva il diagramma di infrastruttura (nodi/collegamenti) per il tenant indicato in
        Config\InfraDiagram-<TenantName>.json - stesso schema di isolamento per-tenant di
        Add-M365OpsChatHistoryTurn.
    .PARAMETER Nodes
        Array di oggetti { id, type, name, role, ip, domain, notes, x, y } - cosi' come arrivano
        gia' pronti dall'editor GUI (Gui/index.html), nessuna conversione di case necessaria
        (salvati esattamente con questi nomi di proprieta', riletti identici da
        Get-M365OpsInfraDiagram e dal renderer testuale per l'IA).
    .PARAMETER Edges
        Array di oggetti { id, from, to, label }.
    .NOTES
        Validazione leggera, non stretta: questo e' un editor grafico pensato per un singolo
        operatore che disegna la PROPRIA infrastruttura, non un input utente non fidato da un
        modulo esterno - a differenza dei dati letti da Graph/EXO, qui non serve difendersi da
        contenuti malevoli, solo da un payload malformato che romperebbe il rendering GUI o
        gonfierebbe senza controllo il testo passato poi all'IA (get_tenant_infrastructure,
        Invoke-M365OpsAgentTools.ps1) - da qui i due tetti (500 nodi, 1000 collegamenti) e lo
        scarto silenzioso di voci senza un Id valido invece di un errore bloccante.
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Nodes,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Edges
    )

    $safeName = $TenantName -replace '[^\w\-]', '_'
    $configDir = Join-Path $script:M365OpsModuleRoot 'Config'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $path = Join-Path $configDir "InfraDiagram-$safeName.json"

    # Tetto dimensionale (vedi .NOTES) - un editor GUI a mano non produrra' mai realisticamente
    # migliaia di nodi, ma senza un limite un payload anomalo finirebbe comunque, per intero, nel
    # prompt di sistema/nella risposta del tool get_tenant_infrastructure ad ogni domanda.
    $safeNodes = @($Nodes | Where-Object { $_.id } | Select-Object -First 500 | ForEach-Object {
        [pscustomobject]@{
            id     = [string]$_.id
            type   = if ($_.type) { [string]$_.type } else { 'Other' }
            name   = if ($_.name) { [string]$_.name } else { '(senza nome)' }
            role   = [string]$_.role
            ip     = [string]$_.ip
            domain = [string]$_.domain
            notes  = [string]$_.notes
            x      = if ($null -ne $_.x) { [double]$_.x } else { 0 }
            y      = if ($null -ne $_.y) { [double]$_.y } else { 0 }
        }
    })
    $validNodeIds = @($safeNodes | ForEach-Object { $_.id })
    # Uno scarto silenzioso qui (collegamento verso un nodo gia' rimosso) e' corretto e atteso:
    # capita normalmente quando l'operatore elimina un nodo che aveva ancora un collegamento
    # attivo - l'editor GUI rimuove gia' i collegamenti orfani lato client prima di salvare, ma
    # questo e' un secondo livello di difesa lato server, non deve mai bloccare il salvataggio.
    $safeEdges = @($Edges | Where-Object { $_.id -and $_.from -in $validNodeIds -and $_.to -in $validNodeIds } | Select-Object -First 1000 | ForEach-Object {
        [pscustomobject]@{
            id    = [string]$_.id
            from  = [string]$_.from
            to    = [string]$_.to
            label = [string]$_.label
        }
    })

    $diagram = [pscustomobject]@{
        nodes     = $safeNodes
        edges     = $safeEdges
        updatedAt = (Get-Date -Format 'o')
    }
    # -InputObject, MAI in pipeline: stesso bug reale gia' trovato piu' volte in questo progetto
    # (GET /api/tenants, GET /api/chat/history, Add-M365OpsKnowledgeDocument) - "$diagram |
    # ConvertTo-Json" con un array a un solo elemento dentro appiattirebbe quell'array in un
    # oggetto nudo invece di [oggetto], rompendo il parsing lato GUI al primo nodo salvato.
    ConvertTo-Json -InputObject $diagram -Depth 8 | Set-Content -Path $path -Encoding UTF8

    [pscustomobject]@{ Nodes = $safeNodes; Edges = $safeEdges; UpdatedAt = $diagram.updatedAt }
}
