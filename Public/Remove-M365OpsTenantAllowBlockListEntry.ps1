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
    Remove-TenantAllowBlockListItems -ListType $ListType -Entries $Entries
    Write-Host "Voce rimossa dalla Tenant Allow/Block List ($ListType): $($Entries -join ', ')" -ForegroundColor Green
}
