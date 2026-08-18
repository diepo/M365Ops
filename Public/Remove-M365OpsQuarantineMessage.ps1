function Remove-M365OpsQuarantineMessage {
    <#
    .SYNOPSIS
        Elimina definitivamente un messaggio in quarantena (Identity ottenuta da
        Get-M365OpsQuarantineMessages) senza rilasciarlo a nessuno - da usare quando e' spam/
        phishing/malware confermato, non un falso positivo.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Delete-QuarantineMessage -Identity $Identity
    Write-Host "Messaggio eliminato dalla quarantena: $Identity" -ForegroundColor Green
}
