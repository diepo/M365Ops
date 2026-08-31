function Set-M365OpsAiPricingConfig {
    <#
    .SYNOPSIS
        Salva/aggiorna una voce di prezzo (per milione di token) in Config\ai-pricing.json
        per un provider+modello, usata dalla sezione "Costi IA" per stimare il costo reale
        dell'utilizzo registrato da Write-M365OpsAiUsageLog. Riscrive l'INTERO file ogni
        volta con l'unione di quanto gia' salvato + questa voce - stesso principio gia' in
        uso per gli altri file di configurazione a dizionario di questo modulo (mai una
        singola voce isolata, sempre il set completo, per non perdere altre voci gia'
        salvate in scritture concorrenti separate).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider,
        [Parameter(Mandatory)] [string]$Model,
        [Parameter(Mandatory)] [double]$InputPer1M,
        [double]$CachedInputPer1M = 0,
        [Parameter(Mandatory)] [double]$OutputPer1M,
        [ValidateSet('known', 'auto', 'manual')] [string]$Source = 'manual'
    )
    $configPath = Join-Path $script:M365OpsModuleRoot 'Config\ai-pricing.json'
    $configDir = Split-Path -Parent $configPath
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Force -Path $configDir | Out-Null }

    $current = @{}
    if (Test-Path $configPath) {
        try {
            $existing = Get-Content -Path $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($existing) {
                foreach ($prop in $existing.PSObject.Properties) { $current[$prop.Name] = $prop.Value }
            }
        } catch {}
    }

    $key = "$Provider|$Model"
    $current[$key] = [pscustomobject]@{
        inputPer1M       = $InputPer1M
        cachedInputPer1M = $CachedInputPer1M
        outputPer1M      = $OutputPer1M
        source           = $Source
        lastUpdated      = (Get-Date -Format 'yyyy-MM-dd')
    }

    $current | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    $current[$key]
}
