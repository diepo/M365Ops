function Get-M365OpsAiUsageStatus {
    <#
    .SYNOPSIS
        Stato del motore AI: provider attivo, chiavi configurate (presenza, non validità -
        per quella usa Test-M365OpsAiConnection), conteggio chiamate fatte in questa sessione
        del server. Dal 15/08/2026 sia la chat libera con tool-calling (Invoke-M365OpsAgentTools)
        sia le chiamate singole senza strumenti (analisi pattern, diagnosi errori) rispettano
        il provider selezionato in "Motore AI" - prima del 15/08/2026 solo le seconde lo
        facevano davvero (limite ora rimosso, vedi Invoke-M365OpsAgentTools).
    .PARAMETER ActiveProvider
        Il provider attivo secondo il chiamante (Server.ps1) - $script:ActiveAIProvider vive
        nello scope di Server.ps1, non in quello del modulo, quindi va passato esplicitamente
        invece di provare a leggerlo direttamente da qui.
    #>
    param([string]$ActiveProvider = 'Claude')

    $claudeKey = [bool](Get-M365OpsSecret -Name 'ANTHROPIC_API_KEY')
    $azureKey = [bool](Get-M365OpsSecret -Name 'AZURE_OPENAI_KEY')
    $azureEndpoint = [bool](Get-M365OpsSecret -Name 'AZURE_OPENAI_ENDPOINT')
    $azureDeployment = [bool](Get-M365OpsSecret -Name 'AZURE_OPENAI_DEPLOYMENT')

    [pscustomobject]@{
        ActiveProvider        = $ActiveProvider
        ClaudeKeyConfigured   = $claudeKey
        AzureKeyConfigured    = ($azureKey -and $azureEndpoint -and $azureDeployment)
        ClaudeCallCount       = $script:M365OpsAiCallCount.Claude
        AzureCallCount        = $script:M365OpsAiCallCount.AzureOpenAI
    }
}
