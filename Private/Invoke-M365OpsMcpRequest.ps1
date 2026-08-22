function Invoke-M365OpsMcpRequest {
    <#
    .SYNOPSIS
        Client MCP minimale (JSON-RPC 2.0 su stdio) - manda una richiesta a un processo
        figlio che parla il Model Context Protocol e ne legge la risposta corrispondente.
    #>
    param(
        [Parameter(Mandatory)] $Process,
        [Parameter(Mandatory)] [string]$Method,
        $Params = @{},
        [switch]$Notification,
        # Default 30s invariato per Lokka/CLI Microsoft 365 (comportamento originale) - un
        # chiamante puo' alzarlo per un'operazione nota per essere piu' lenta (es. il "connect"
        # del worker isolato Exchange/Teams, che puo' includere Connect-ExchangeOnline +
        # Connect-IPPSSession + un'attesa di stabilizzazione dell'elenco comandi, vedi
        # M365OpsIsolatedWorker.ps1 - trovato dal vivo il 26/08/2026 che 30s non bastavano
        # sempre per quel caso specifico).
        [int]$TimeoutSeconds = 30
    )

    $script:M365OpsMcpRequestId = if ($script:M365OpsMcpRequestId) { $script:M365OpsMcpRequestId + 1 } else { 1 }
    $id = $script:M365OpsMcpRequestId

    $payload = [ordered]@{ jsonrpc = "2.0"; method = $Method; params = $Params }
    if (-not $Notification) { $payload.id = $id }

    $json = $payload | ConvertTo-Json -Depth 12 -Compress
    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()

    if ($Notification) { return $null }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) {
            $err = $Process.StandardError.ReadToEnd()
            throw "Il processo MCP si e' chiuso inaspettatamente. Stderr: $err"
        }
        if ($Process.StandardOutput.EndOfStream) { Start-Sleep -Milliseconds 100; continue }

        $line = $Process.StandardOutput.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try { $parsed = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($parsed.PSObject.Properties.Name -contains 'id' -and $parsed.id -eq $id) {
            if ($parsed.error) { throw "Errore MCP: $($parsed.error.message)" }
            return $parsed.result
        }
        # Messaggio intermedio (notifica, log, risposta a un'altra richiesta): ignora e continua.
    }

    throw "Timeout in attesa di risposta MCP per il metodo '$Method'."
}
