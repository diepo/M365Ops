function Remove-M365OpsAcceptedDomain {
    <#
    .SYNOPSIS
        Rimuove un dominio accettato dal tenant - AZIONE AD ALTO IMPATTO: tutte le mailbox
        con un indirizzo su questo dominio come primario perdono la capacita' di
        inviare/ricevere posta su quell'indirizzo. Non funziona se il dominio e' ancora
        quello predefinito o se e' l'unico dominio custom rimasto (limite nativo del
        servizio, non di questa funzione).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Remove-AcceptedDomain -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Dominio accettato rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
