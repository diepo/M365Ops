function Test-M365OpsAiConnection {
    <#
    .SYNOPSIS
        Verifica DAL VIVO (una piccola chiamata reale, non solo "la chiave e' presente") che
        il provider AI indicato risponda correttamente. Costa una chiamata reale (pochi token)
        - va richiamata solo su azione esplicita dell'utente, mai in polling automatico.
    #>
    param(
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )
    try {
        $reply = Invoke-M365OpsAgent -Prompt "Rispondi solo con la parola: OK" -Provider $Provider -MaxTokens 10
        [pscustomobject]@{ Provider = $Provider; Ok = $true; Message = "Connesso. Risposta: $($reply.Trim())" }
    }
    catch {
        [pscustomobject]@{ Provider = $Provider; Ok = $false; Message = $_.Exception.Message }
    }
}
