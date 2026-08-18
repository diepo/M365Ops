function Remove-M365OpsQuarantinePolicy {
    <#
    .SYNOPSIS
        Elimina una policy di quarantena personalizzata. Non funziona sulle due policy
        predefinite del sistema (AdminOnlyAccessPolicy, DefaultFullAccessPolicy) - non
        possono essere eliminate, e' un limite nativo del servizio, non di questa funzione.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    # BUG reale trovato dal vivo lo stesso giorno (diagnosi automatica dell'app): a differenza
    # di quasi ogni altro Remove-* di Exchange, Remove-QuarantinePolicy NON supporta -Confirm
    # (assente dalla sua sintassi ufficiale) - passarlo produceva un errore di binding
    # parametro invece di eseguire la rimozione.
    Remove-QuarantinePolicy -Identity $Identity -ErrorAction Stop
    Write-Host "Policy di quarantena rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
