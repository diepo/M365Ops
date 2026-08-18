function Get-M365OpsQuarantinePolicy {
    <#
    .SYNOPSIS
        Elenca le policy di quarantena (cosa puo' fare un utente su un messaggio in
        quarantena - rilasciarlo, richiederne il rilascio, vederne l'header, ecc. - a
        seconda del motivo per cui e' stato messo in quarantena). Diverso da
        Get-M365OpsQuarantineMessages, che elenca i MESSAGGI, non le policy.
    .NOTES
        Mode: ReadOnly
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    if ($Identity) {
        Get-QuarantinePolicy -Identity $Identity
    } else {
        Get-QuarantinePolicy | Select-Object Name, QuarantinePolicyType
    }
}
