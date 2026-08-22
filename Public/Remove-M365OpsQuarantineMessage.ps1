function Remove-M365OpsQuarantineMessage {
    <#
    .SYNOPSIS
        Elimina definitivamente un messaggio in quarantena (Identity ottenuta da
        Get-M365OpsQuarantineMessages) senza rilasciarlo a nessuno - da usare quando e' spam/
        phishing/malware confermato, non un falso positivo.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026) - vedi Release-M365OpsQuarantineMessage.ps1
    # per il perche' una prima scansione sistematica del progetto lo aveva mancato.
    Delete-QuarantineMessage -Identity $Identity -ErrorAction Stop
    Write-Host "Messaggio eliminato dalla quarantena: $Identity" -ForegroundColor Green
}
