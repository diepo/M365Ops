function Remove-M365OpsTenantAllowBlockListSpoofItem {
    <#
    .SYNOPSIS
        Rimuove una o piu' coppie spoof dalla Tenant Allow/Block List. Gli Id (GUID) vanno
        presi da Get-M365OpsTenantAllowBlockListSpoofItems, mai indovinati - non e' l'indirizzo
        email del mittente falsificato, e' l'identificativo generato dal servizio per quella
        specifica coppia.
    #>
    param(
        [Parameter(Mandatory)] [string[]]$Ids
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Remove-TenantAllowBlockListSpoofItems -Identity 'Default' -Ids $Ids -Confirm:$false -ErrorAction Stop
    Write-Host "Voci spoof rimosse: $($Ids.Count)" -ForegroundColor Green
    [pscustomobject]@{ Ids = $Ids; Removed = $true }
}
