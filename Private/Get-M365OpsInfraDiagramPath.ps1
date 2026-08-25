function Get-M365OpsInfraDiagramPath {
    <#
    .SYNOPSIS
        Restituisce il percorso CANONICO del diagramma infrastruttura per un profilo tenant
        (Config\InfraDiagram-<TenantId risolto>.json, vedi Get-M365OpsTenantStorageKey), e
        migra pigramente eventuali dati "legacy" salvati sotto il vecchio schema per NOME
        PROFILO (Config\InfraDiagram-<nome profilo>.json), se presenti.
    .NOTES
        Migrazione (25/08/2026, richiesto esplicitamente dall'utente): prima di questa versione
        la chiave di storage era il nome profilo, non il Tenant ID risolto - un utente con due
        profili sullo stesso tenant reale (es. "vnsys-test" AppOnly e "vnsys delegata" Delegato,
        entrambi TenantId "vnsysit.onmicrosoft.com") aveva due file separati e vuoti invece di
        uno condiviso. Idempotente e sicura: il file legacy viene UNITO (non sovrascritto) nel
        nuovo file, poi rinominato con un suffisso ".migrated-<data>" (mai eliminato) - al
        prossimo accesso non c'e' piu' nulla da migrare, quindi questo blocco diventa un
        no-op economico (un solo Test-Path). Se DUE profili diversi hanno entrambi dati legacy
        sullo stesso Tenant ID risolto, vengono uniti entrambi nello stesso file canonico, in
        qualunque ordine vengano acceduti per primi (ogni chiamata unisce il proprio legacy nel
        canonico gia' esistente, invece di sovrascriverlo).
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $configDir = Join-Path $script:M365OpsModuleRoot 'Config'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $newKey = Get-M365OpsTenantStorageKey -TenantName $TenantName
    $newPath = Join-Path $configDir "InfraDiagram-$newKey.json"

    $legacyKey = $TenantName -replace '[^\w\-]', '_'
    if ($legacyKey -ne $newKey) {
        $legacyPath = Join-Path $configDir "InfraDiagram-$legacyKey.json"
        if (Test-Path $legacyPath) {
            try {
                $legacyRaw = Get-Content -Path $legacyPath -Raw -ErrorAction Stop
                $legacyParsed = if ($legacyRaw) { ConvertFrom-Json -InputObject $legacyRaw -ErrorAction Stop } else { $null }
                $legacyNodes = @($legacyParsed.nodes)
                $legacyEdges = @($legacyParsed.edges)
                if ($legacyNodes.Count -gt 0 -or $legacyEdges.Count -gt 0) {
                    $existing = $null
                    if (Test-Path $newPath) {
                        try { $existing = ConvertFrom-Json -InputObject (Get-Content -Path $newPath -Raw) -ErrorAction Stop } catch { $existing = $null }
                    }
                    $mergedNodes = @(@($existing.nodes) + $legacyNodes | Sort-Object -Property id -Unique)
                    $mergedEdges = @(@($existing.edges) + $legacyEdges | Sort-Object -Property id -Unique)
                    $merged = [pscustomobject]@{ nodes = $mergedNodes; edges = $mergedEdges; updatedAt = (Get-Date -Format 'o') }
                    ConvertTo-Json -InputObject $merged -Depth 8 | Set-Content -Path $newPath -Encoding UTF8
                    Write-M365OpsLog "Migrazione diagramma infrastruttura: unito il file legacy del profilo '$TenantName' nella chiave per tenant '$newKey' ($($legacyNodes.Count) nodi, $($legacyEdges.Count) collegamenti)."
                }
            }
            catch {
                Write-M365OpsLog "Migrazione diagramma infrastruttura fallita per il profilo '$TenantName': $($_.Exception.Message)" -Level Warn
            }
            # Rinominato, MAI eliminato (recuperabile se la unione sopra avesse un problema non
            # ancora scoperto) - il suffisso con la data evita di sovrascrivere un backup gia'
            # esistente se questa funzione venisse per assurdo chiamata due volte lo stesso giorno
            # prima che il Test-Path sul file legacy sopra lo escluda (non dovrebbe mai succedere,
            # ma Rename-Item su un file di destinazione gia' esistente lancerebbe un errore non
            # gestito altrimenti).
            $backupName = "InfraDiagram-$legacyKey.json.migrated-$(Get-Date -Format 'yyyyMMdd')"
            if (-not (Test-Path (Join-Path $configDir $backupName))) {
                Rename-Item -Path $legacyPath -NewName $backupName -ErrorAction SilentlyContinue
            }
        }
    }

    $newPath
}
