function Get-M365OpsKnowledgeBasePaths {
    <#
    .SYNOPSIS
        Restituisce i percorsi CANONICI della Knowledge Base per un profilo tenant - il catalogo
        (Config\KnowledgeBase-<chiave>.json) e la cartella dei file caricati
        (Uploads\kb\<chiave>\), dove <chiave> e' il Tenant ID risolto (vedi
        Get-M365OpsTenantStorageKey), NON il nome profilo. Migra pigramente eventuali dati
        "legacy" salvati sotto il vecchio schema per nome profilo, se presenti - stesso
        meccanismo e stessa motivazione di Get-M365OpsInfraDiagramPath (vedi li' per i dettagli):
        due profili sullo stesso tenant reale (es. AppOnly + Delegato) condividono ora la stessa
        documentazione invece di vederne due copie separate.
    .PARAMETER TenantName
        Nome del PROFILO - oppure il bucket globale riservato $script:M365OpsGlobalKbName
        ("_global"), che passa invariato (non e' un profilo reale in Config\tenants.json, quindi
        Get-M365OpsTenantStorageKey non trova nulla da risolvere e lo restituisce cosi' com'e' -
        nessuna logica speciale necessaria qui per quel caso).
    .OUTPUTS
        pscustomobject { CatalogPath; KbDir }
    #>
    param([Parameter(Mandatory)] [string]$TenantName)

    $configDir = Join-Path $script:M365OpsModuleRoot 'Config'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $newKey = Get-M365OpsTenantStorageKey -TenantName $TenantName
    $newCatalogPath = Join-Path $configDir "KnowledgeBase-$newKey.json"
    $newKbDir = Join-Path $script:M365OpsModuleRoot "Uploads\kb\$newKey"

    $legacyKey = $TenantName -replace '[^\w\-]', '_'
    if ($legacyKey -ne $newKey) {
        $legacyCatalogPath = Join-Path $configDir "KnowledgeBase-$legacyKey.json"
        if (Test-Path $legacyCatalogPath) {
            try {
                $legacyCatalog = @(Get-Content -Path $legacyCatalogPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Where-Object { $_.FileName })
                if ($legacyCatalog.Count -gt 0) {
                    $existingCatalog = @()
                    if (Test-Path $newCatalogPath) {
                        try { $existingCatalog = @(Get-Content -Path $newCatalogPath -Raw | ConvertFrom-Json | Where-Object { $_.FileName }) } catch { $existingCatalog = @() }
                    }
                    # In caso di collisione sul nome file, vince la voce gia' presente nel
                    # catalogo canonico (probabilmente arrivata li' per prima, o gia' migrata in
                    # un giro precedente) - il file legacy corrispondente resta comunque
                    # recuperabile nella cartella rinominata sotto, non viene mai perso.
                    $existingNames = @($existingCatalog | ForEach-Object { $_.FileName })
                    $toAdd = @($legacyCatalog | Where-Object { $_.FileName -notin $existingNames })
                    $mergedCatalog = @($existingCatalog + $toAdd)
                    ConvertTo-Json -InputObject $mergedCatalog -Depth 6 | Set-Content -Path $newCatalogPath -Encoding UTF8

                    $legacyKbDir = Join-Path $script:M365OpsModuleRoot "Uploads\kb\$legacyKey"
                    if (Test-Path $legacyKbDir) {
                        New-Item -ItemType Directory -Force -Path $newKbDir | Out-Null
                        Get-ChildItem -Path $legacyKbDir -File | ForEach-Object {
                            $dest = Join-Path $newKbDir $_.Name
                            if (-not (Test-Path $dest)) { Copy-Item -Path $_.FullName -Destination $dest -Force }
                        }
                    }
                    Write-M365OpsLog "Migrazione Knowledge Base: unito il catalogo legacy del profilo '$TenantName' nella chiave per tenant '$newKey' ($($toAdd.Count) documenti aggiunti, $($legacyCatalog.Count - $toAdd.Count) gia' presenti)."
                }
            }
            catch {
                Write-M365OpsLog "Migrazione Knowledge Base fallita per il profilo '$TenantName': $($_.Exception.Message)" -Level Warn
            }
            # Stesso principio di Get-M365OpsInfraDiagramPath: rinominato, mai eliminato.
            $backupName = "KnowledgeBase-$legacyKey.json.migrated-$(Get-Date -Format 'yyyyMMdd')"
            if (-not (Test-Path (Join-Path $configDir $backupName))) {
                Rename-Item -Path $legacyCatalogPath -NewName $backupName -ErrorAction SilentlyContinue
            }
        }
    }

    [pscustomobject]@{ CatalogPath = $newCatalogPath; KbDir = $newKbDir }
}
