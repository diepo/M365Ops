function Remove-M365OpsTenantAllowBlockListEntry {
    <#
    .SYNOPSIS
        Rimuove una o piu' voci dalla Tenant Allow/Block List (stesso ListType e stesso Value
        usati in New-M365OpsTenantAllowBlockListEntry, o trovati con Get-M365OpsTenantAllowBlockList).
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Sender', 'Url', 'FileHash', 'IP')] [string]$ListType,
        [Parameter(Mandatory)] [string[]]$Entries
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026).
    Remove-TenantAllowBlockListItems -ListType $ListType -Entries $Entries -ErrorAction Stop
    Write-Host "Voce rimossa dalla Tenant Allow/Block List ($ListType): $($Entries -join ', ')" -ForegroundColor Green
}
