function Get-M365OpsQuarantineMessageHeader {
    <#
    .SYNOPSIS
        Mostra l'header SMTP grezzo (RFC 5322) di un messaggio in quarantena, senza
        rilasciarlo - utile per analisi/forensics (SPF/DKIM/DMARC, hop di instradamento
        reali) prima di decidere se e' un falso positivo o una minaccia reale.
    .PARAMETER Identity
        Va presa da Get-M365OpsQuarantineMessages, mai indovinata.
    .NOTES
        Mode: ReadOnly
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Get-QuarantineMessageHeader -Identity $Identity
}
