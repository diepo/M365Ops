function Disconnect-M365OpsExchange {
    <#
    .SYNOPSIS
        Chiude la connessione Exchange Online PowerShell, se attiva.
    #>
    if ($script:M365OpsExchangeConnected) {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        $script:M365OpsExchangeConnected = $false
    }
}
