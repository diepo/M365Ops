function Write-M365OpsAiUsageLog {
    <#
    .SYNOPSIS
        Registra un turno di utilizzo IA completo (una risposta intera a un messaggio
        utente, non ogni singolo round di tool-calling al suo interno) in
        Logs\ai-usage-YYYYMMDD.jsonl - un file al giorno, JSON Lines (un oggetto per riga),
        cosi' la sezione "Costi IA" della GUI puo' aggregare per giorno/provider/modello
        senza dover riparsare l'intero log testuale generico (m365ops-*.log), pensato per
        la lettura umana, non per l'aggregazione automatica.

        Richiesto esplicitamente dall'utente (31/08/2026, dopo un'indagine sui costi Azure
        concentrati nella maratona di agosto): "una sezione di report... dove compaiono
        giorno per giorno i token inviati ricevuti da e verso quale modello e la
        possibilita' di stimare il costo".

        Non lancia mai eccezioni (stesso principio di Write-M365OpsLog): un problema nel
        logging non deve mai rompere la risposta reale che si stava registrando - questa
        funzione viene chiamata alla FINE di una risposta gia' pronta per l'utente, un suo
        fallimento non deve mai nascondere quella risposta.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider,
        [string]$Model,
        [Parameter(Mandatory)] [int]$InputTokens,
        [Parameter(Mandatory)] [int]$OutputTokens,
        [int]$CachedTokens = 0,
        [int]$ReasoningTokens = 0
    )
    try {
        $logDir = Join-Path $script:M365OpsModuleRoot 'Logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        $logFile = Join-Path $logDir "ai-usage-$(Get-Date -Format 'yyyyMMdd').jsonl"
        $tenant = if ($script:M365OpsContext -and $script:M365OpsContext.Name) { $script:M365OpsContext.Name } else { $null }
        $entry = [pscustomobject]@{
            timestamp       = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
            tenant          = $tenant
            provider        = $Provider
            model           = $Model
            inputTokens     = $InputTokens
            outputTokens    = $OutputTokens
            cachedTokens    = $CachedTokens
            reasoningTokens = $ReasoningTokens
        }
        Add-Content -Path $logFile -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
    }
    catch { }
}
