function Remove-M365OpsRemoteDomain {
    <#
    .SYNOPSIS
        Elimina una voce di dominio remoto personalizzata (non funziona su "Default", che
        e' l'impostazione base del tenant e non puo' essere rimossa - e' un limite nativo
        del servizio).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Remove-RemoteDomain -Identity $Identity -Confirm:$false -ErrorAction Stop
    Write-Host "Dominio remoto rimosso: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
