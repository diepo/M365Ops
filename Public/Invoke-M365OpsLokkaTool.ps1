function Invoke-M365OpsLokkaTool {
    <#
    .SYNOPSIS
        Chiama un tool esposto da Lokka (vedi Connect-M365OpsLokka per l'elenco).
        Avvia Lokka automaticamente se non e' gia' attivo.
    #>
    param(
        [Parameter(Mandatory)] [string]$ToolName,
        [hashtable]$Arguments = @{}
    )

    if (-not $script:M365OpsLokkaProcess -or $script:M365OpsLokkaProcess.HasExited) {
        Connect-M365OpsLokka | Out-Null
    }

    Invoke-M365OpsMcpRequest -Process $script:M365OpsLokkaProcess -Method "tools/call" -Params @{
        name      = $ToolName
        arguments = $Arguments
    }
}
