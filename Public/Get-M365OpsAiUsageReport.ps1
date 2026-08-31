function Get-M365OpsAiUsageReport {
    <#
    .SYNOPSIS
        Legge tutti i file Logs\ai-usage-*.jsonl (scritti da Write-M365OpsAiUsageLog, uno
        per giorno) e li aggrega per giorno/provider/modello - la base per la sezione "Costi
        IA" della GUI richiesta esplicitamente dall'utente il 31/08/2026 ("una sezione di
        report... dove compaiono giorno per giorno i token inviati ricevuti da e verso quale
        modello").

        Non calcola il costo in $ qui - questo restituisce solo token aggregati, puri e
        verificabili. Il costo si aggiunge a valle (Gui/Server.ps1, combinando questo
        risultato con Get-M365OpsAiPricingConfig) cosi' questa funzione resta stabile anche
        quando i prezzi cambiano o vengono corretti, senza dover ricalcolare/ririeleggere i
        log.
    .PARAMETER Days
        Quanti giorni indietro includere (default 30) - i log piu' vecchi non vengono letti
        affatto, non solo filtrati dopo, per restare veloci anche con uno storico lungo.
    #>
    param(
        [int]$Days = 30
    )

    $logDir = Join-Path $script:M365OpsModuleRoot 'Logs'
    $daily = @{}
    $totals = @{}

    if (-not (Test-Path $logDir)) { return [pscustomobject]@{ Daily = @(); Totals = @() } }

    for ($i = 0; $i -lt $Days; $i++) {
        $day = (Get-Date).AddDays(-$i)
        $dayKey = $day.ToString('yyyy-MM-dd')
        $logFile = Join-Path $logDir "ai-usage-$($day.ToString('yyyyMMdd')).jsonl"
        if (-not (Test-Path $logFile)) { continue }

        # Un file corrotto/parzialmente scritto (es. processo terminato a meta' scrittura di
        # una riga) non deve far fallire l'intero report - riga per riga, non l'intero file,
        # cosi' un solo problema locale non nasconde giorni interi di dati altrimenti validi.
        $lines = Get-Content -Path $logFile -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if (-not $line) { continue }
            try {
                $entry = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }
            $modelKey = "$($entry.provider)|$($entry.model)"
            $dailyKey = "$dayKey|$modelKey"

            if (-not $daily.ContainsKey($dailyKey)) {
                $daily[$dailyKey] = [pscustomobject]@{
                    Date            = $dayKey
                    Provider        = $entry.provider
                    Model           = $entry.model
                    Calls           = 0
                    InputTokens     = 0
                    OutputTokens    = 0
                    CachedTokens    = 0
                    ReasoningTokens = 0
                }
            }
            $daily[$dailyKey].Calls++
            $daily[$dailyKey].InputTokens += [int]$entry.inputTokens
            $daily[$dailyKey].OutputTokens += [int]$entry.outputTokens
            $daily[$dailyKey].CachedTokens += [int]$entry.cachedTokens
            $daily[$dailyKey].ReasoningTokens += [int]$entry.reasoningTokens

            if (-not $totals.ContainsKey($modelKey)) {
                $totals[$modelKey] = [pscustomobject]@{
                    Provider        = $entry.provider
                    Model           = $entry.model
                    Calls           = 0
                    InputTokens     = 0
                    OutputTokens    = 0
                    CachedTokens    = 0
                    ReasoningTokens = 0
                }
            }
            $totals[$modelKey].Calls++
            $totals[$modelKey].InputTokens += [int]$entry.inputTokens
            $totals[$modelKey].OutputTokens += [int]$entry.outputTokens
            $totals[$modelKey].CachedTokens += [int]$entry.cachedTokens
            $totals[$modelKey].ReasoningTokens += [int]$entry.reasoningTokens
        }
    }

    [pscustomobject]@{
        Daily  = @($daily.Values | Sort-Object @{Expression = 'Date'; Descending = $true }, Provider, Model)
        Totals = @($totals.Values | Sort-Object @{Expression = { $_.InputTokens + $_.OutputTokens } ; Descending = $true })
    }
}
