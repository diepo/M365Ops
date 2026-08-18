function Set-M365OpsTenantAllowBlockListItem {
    <#
    .SYNOPSIS
        Modifica una voce esistente della Tenant Allow/Block List (tipicamente per estenderne
        la scadenza o aggiungere note) - non per crearne una nuova, per quello vedi
        New-M365OpsTenantAllowBlockListEntry. Gli Id vanno presi da Get-M365OpsTenantAllowBlockList,
        mai indovinati. Sintassi verificata contro la documentazione ufficiale Microsoft
        (non a memoria) il 18/08/2026.
    #>
    param(
        [Parameter(Mandatory)] [string[]]$Ids,
        [Parameter(Mandatory)] [ValidateSet('Sender', 'Url', 'FileHash', 'IP')] [string]$ListType,
        [datetime]$ExpirationDate,
        [switch]$NoExpiration,
        [string]$Notes
    )
    Connect-M365OpsExchange
    $params = @{ Ids = $Ids; ListType = $ListType }
    if ($NoExpiration) { $params.NoExpiration = $true }
    elseif ($ExpirationDate) { $params.ExpirationDate = $ExpirationDate }
    if ($Notes) { $params.Notes = $Notes }

    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    Set-TenantAllowBlockListItems @params -ErrorAction Stop
    Write-Host "Voce/i Tenant Allow/Block List aggiornata/e: $($Ids.Count)" -ForegroundColor Green
}
