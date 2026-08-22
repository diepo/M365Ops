function New-M365OpsMigrationBatch {
    <#
    .SYNOPSIS
        Crea un batch di migrazione mailbox usando un endpoint GIA' configurato (vedi
        Get-M365OpsMigrationEndpoints - -SourceEndpoint deve corrispondere a uno di
        quelli restituiti, l'identity viene validata prima di procedere). Creato SEMPRE
        NON avviato (nessun -AutoStart) - l'avvio e' un passo separato ed esplicito, vedi
        Start-M365OpsMigrationBatch. Specifica -Users per un batch con un elenco preciso
        di mailbox (staged/onboarding), oppure -Cutover per un batch sull'intera
        organizzazione (tipico per Exchange on-premises -> Exchange Online).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$SourceEndpoint,
        [string[]]$Users,
        [switch]$Cutover,
        [string]$TargetDeliveryDomain,
        # Se presente, ogni mailbox passa a "completata" automaticamente non appena la sincronizzazione
        # iniziale finisce. Se assente (default), resta in sospeso finche' non chiami Complete-MigrationBatch
        # a mano (o non imposti -CompleteAfter) - piu' prudente per non finalizzare migrazioni senza controllo.
        [switch]$AutoComplete,
        # Rimanda la finalizzazione (taglio DNS/consegna) a una data/ora precisa nel futuro, invece che
        # subito dopo la sincronizzazione - utile per programmare il cutover fuori orario lavorativo.
        [datetime]$CompleteAfter,
        # Qualunque altro parametro nativo di New-MigrationBatch non gia' previsto sopra
        # (es. NotificationEmails, BadItemLimit, LargeItemLimit) - se non sei sicuro del
        # nome esatto o del formato atteso, consulta prima lookup_ms_docs "New-MigrationBatch".
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange

    $endpoints = @(Get-MigrationEndpoint)
    $match = $endpoints | Where-Object { $_.Identity -eq $SourceEndpoint } | Select-Object -First 1
    if (-not $match) {
        $available = if ($endpoints) { ($endpoints.Identity -join ', ') } else { '(nessuno configurato)' }
        throw "Endpoint di migrazione '$SourceEndpoint' non trovato tra quelli configurati. Disponibili: $available. Usa Get-M365OpsMigrationEndpoints per l'elenco aggiornato."
    }

    if (-not $Cutover -and (-not $Users -or $Users.Count -eq 0)) {
        throw "Specifica -Users (elenco indirizzi email da migrare) oppure -Cutover per un batch sull'intera organizzazione."
    }

    $params = @{ Name = $Name; SourceEndpoint = $match.Identity }
    if ($TargetDeliveryDomain) { $params.TargetDeliveryDomain = $TargetDeliveryDomain }
    if ($AutoComplete) { $params.AutoComplete = $true }
    if ($CompleteAfter) { $params.CompleteAfter = $CompleteAfter }

    if ($Cutover) {
        $params.Cutover = $true
    }
    else {
        $csvContent = (@("EmailAddress") + $Users) -join "`r`n"
        $params.CSVData = [System.Text.Encoding]::UTF8.GetBytes($csvContent)
    }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    # Nessun -AutoStart: il batch resta creato ma non avviato finche' non si chiama
    # esplicitamente Start-M365OpsMigrationBatch - stesso principio delle regole di
    # trasporto (create sempre disabilitate) e di ogni altro oggetto creato da questo modulo.
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026).
    $params.ErrorAction = 'Stop'
    $batch = New-MigrationBatch @params
    Write-Host "Batch di migrazione creato (NON avviato): $($batch.Identity)" -ForegroundColor Green
    $batch | Select-Object Identity, Status, SourceEndpoint, TotalCount
}
