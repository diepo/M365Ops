function Remove-M365OpsKnowledgeDocument {
    <#
    .SYNOPSIS
        Rimuove un documento (file + testo estratto + voce di catalogo) dalla Knowledge Base
        del tenant indicato. SOLO uso GUI (tab Documentazione) - non esposta all'AI: la
        cancellazione di un documento caricato dall'operatore non deve mai dipendere da
        un'interpretazione del modello.
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [string]$FileName
    )

    $requestedName = Split-Path -Leaf $FileName
    $paths = Get-M365OpsKnowledgeBasePaths -TenantName $TenantName
    $kbDir = $paths.KbDir
    $catalogPath = $paths.CatalogPath

    $catalog = @()
    if (Test-Path $catalogPath) {
        try { $catalog = @(Get-Content $catalogPath -Raw | ConvertFrom-Json) } catch { $catalog = @() }
    }
    $found = $catalog | Where-Object { $_.FileName -eq $requestedName } | Select-Object -First 1
    if (-not $found) { throw "Nessun documento '$requestedName' nella Knowledge Base di '$TenantName'." }

    $catalog = @($catalog | Where-Object { $_.FileName -ne $requestedName })
    # -InputObject, MAI in pipeline - bug reale trovato dal vivo il 18/08/2026: con un array
    # VUOTO (ultimo documento rimosso) "$catalog | ConvertTo-Json" non emette nulla, quindi
    # Set-Content a valle non viene MAI eseguito - il file restava quello vecchio, la funzione
    # riportava comunque successo. Vedi anche Add-M365OpsKnowledgeDocument.ps1.
    ConvertTo-Json -InputObject $catalog -Depth 6 | Set-Content -Path $catalogPath -Encoding UTF8

    Remove-Item -Path (Join-Path $kbDir $requestedName) -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $kbDir "$requestedName.extracted.txt") -Force -ErrorAction SilentlyContinue

    Write-Host "Documento '$requestedName' rimosso dalla Knowledge Base di '$TenantName'." -ForegroundColor Green
    [pscustomobject]@{ TenantName = $TenantName; FileName = $requestedName; Removed = $true }
}
