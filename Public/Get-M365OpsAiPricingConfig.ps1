function Get-M365OpsAiPricingConfig {
    <#
    .SYNOPSIS
        Legge Config\ai-pricing.json - il prezzo per milione di token (input/cache/output)
        associato a ciascun provider+modello, usato per stimare il costo reale della sezione
        "Costi IA" (richiesta esplicita dell'utente il 31/08/2026). Chiave "Provider|Model",
        stessa combinazione gia' usata da Write-M365OpsAiUsageLog/Get-M365OpsAiUsageReport.

        Claude Sonnet 4.5 e' PRE-CARICATO con il prezzo reale pubblico (verificato su
        platform.claude.com/docs/en/about-claude/pricing il 31/08/2026, non a memoria: $3/MTok
        input, $0.30/MTok cache hit, $15/MTok output) - e' l'unico modello Claude che questo
        modulo usa (hardcoded in Invoke-M365OpsAgent(Tools).ps1), quindi il prezzo e' noto e
        stabile per definizione, non serve dedurlo. I deployment Azure OpenAI restano invece
        SEMPRE da rilevare/configurare esplicitamente (vedi Find-M365OpsAzureModelPricing) -
        il nome del deployment e' scelto liberamente dall'utente e non identifica da solo
        quale modello reale ci sia dietro.
    #>
    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\ai-pricing.json'
    $defaults = @{
        'Claude|claude-sonnet-4-5' = [pscustomobject]@{
            inputPer1M       = 3.0
            cachedInputPer1M = 0.30
            outputPer1M      = 15.0
            source           = 'known'
            lastUpdated      = '2026-08-31'
        }
    }
    if (-not (Test-Path $configPath)) { return $defaults }
    try {
        # PSCustomObject, non -AsHashtable (PS 5.1 non lo supporta - richiede PS6+, questo
        # modulo dichiara PowerShellVersion 5.1 nel manifest) - stesso pattern gia' in uso
        # ovunque nel modulo per leggere un dizionario da JSON (es. Get-M365OpsMcpServers.ps1),
        # iterando .PSObject.Properties invece di indicizzare come un vero hashtable.
        $saved = Get-Content -Path $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $defaults
    }
    # Unione: le voci salvate hanno sempre priorita' (l'utente potrebbe aver corretto anche
    # il prezzo Claude di default), ma una voce di default mai vista prima (es. dopo un
    # aggiornamento del modulo) resta comunque disponibile finche' non viene sovrascritta.
    $merged = @{}
    foreach ($key in $defaults.Keys) { $merged[$key] = $defaults[$key] }
    if ($saved) {
        foreach ($prop in $saved.PSObject.Properties) { $merged[$prop.Name] = $prop.Value }
    }
    $merged
}
