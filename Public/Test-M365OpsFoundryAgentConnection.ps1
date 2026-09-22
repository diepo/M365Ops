function Test-M365OpsFoundryAgentConnection {
    <#
    .SYNOPSIS
        Verifica DAL VIVO (una chiamata reale, minima) che l'agent Microsoft Foundry configurato
        risponda - stesso principio di Test-M365OpsAiConnection, canale separato (vedi
        Invoke-M365OpsFoundryAgent.ps1). Costa una chiamata reale - solo su azione esplicita.
    #>
    try {
        $result = Invoke-M365OpsFoundryAgent -Prompt "Rispondi solo con la parola: OK" -MaxOutputTokens 200
        [pscustomobject]@{ Ok = $true; Message = "Connesso. Risposta: $($result.Text.Trim())" }
    }
    catch {
        [pscustomobject]@{ Ok = $false; Message = $_.Exception.Message }
    }
}
