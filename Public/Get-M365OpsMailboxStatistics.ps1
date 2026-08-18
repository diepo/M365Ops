function Get-M365OpsMailboxStatistics {
    <#
    .SYNOPSIS
        Statistiche di una mailbox (dimensione, numero elementi, ultimo logon) oppure
        di tutte se -Identity non e' specificato.
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    $targets = if ($Identity) { , $Identity } else { (Get-EXOMailbox -ResultSize Unlimited).PrimarySmtpAddress }
    $targets | ForEach-Object {
        $stats = Get-EXOMailboxStatistics -Identity $_ -Properties TotalItemSize, ItemCount, LastLogonTime
        [pscustomobject]@{
            Identity      = $_
            SizeGB        = if ($stats.TotalItemSize) { [math]::Round(($stats.TotalItemSize.Value.ToBytes() / 1GB), 2) } else { $null }
            ItemCount     = $stats.ItemCount
            LastLogonTime = $stats.LastLogonTime
        }
    }
}
