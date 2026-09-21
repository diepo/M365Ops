function Test-M365OpsAzureOpenAIKeyConfigured {
    <#
    .SYNOPSIS
        Dice SE una sorgente per la chiave Azure OpenAI e' configurata e QUALE, senza mai leggere
        la chiave: nessuna chiamata di rete a Key Vault. Serve ai controlli di stato (setup,
        pallini in GUI, pannello utilizzo AI) che girano spesso e spesso in polling - una
        richiesta a Key Vault ad ogni controllo sarebbe lenta e inutile, la lettura vera avviene
        solo quando si fa davvero una chiamata AI (vedi Get-M365OpsAzureOpenAIKey).
    .OUTPUTS
        pscustomobject { Configured; Source = 'KeyVault' | 'EnvironmentVariable' | 'None' }.
        Con Key Vault configurato la sorgente e' SEMPRE 'KeyVault', anche se esiste ancora una
        AZURE_OPENAI_KEY locale - stessa regola di Get-M365OpsAzureOpenAIKey.
    #>
    if (Get-M365OpsSecret -Name 'AZURE_OPENAI_KEYVAULT_URI') {
        return [pscustomobject]@{ Configured = $true; Source = 'KeyVault' }
    }
    if (Get-M365OpsSecret -Name 'AZURE_OPENAI_KEY') {
        return [pscustomobject]@{ Configured = $true; Source = 'EnvironmentVariable' }
    }
    [pscustomobject]@{ Configured = $false; Source = 'None' }
}
