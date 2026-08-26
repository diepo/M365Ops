function Get-M365OpsMailboxStatistics {
    <#
    .SYNOPSIS
        Statistiche di una mailbox (dimensione, numero elementi, ultimo logon) oppure
        di tutte se -Identity non e' specificato.
    #>
    param([string]$Identity)
    Connect-M365OpsExchange
    $targets = if ($Identity) { , $Identity } else { (Get-EXOMailbox -ResultSize Unlimited).PrimarySmtpAddress }
    # Bug reale (stesso schema di v0.10.1/v0.10.2/v0.10.6, trovato durante l'audit del
    # 26/08/2026): a differenza delle funzioni sorelle che fanno la STESSA chiamata per mailbox
    # (Get-M365OpsInactiveMailboxes, Get-M365OpsMailboxUsageReport - entrambe gia' con
    # -ErrorAction SilentlyContinue), qui mancava del tutto - quando chiamata SENZA -Identity
    # (tutte le mailbox del tenant), una singola mailbox su cui Get-EXOMailboxStatistics lancia
    # un errore terminante (es. throttling momentaneo) uccideva l'intero ciclo, facendo sparire
    # in silenzio anche le statistiche di tutte le mailbox successive gia' sane. Allineato alle
    # sorelle.
    $targets | ForEach-Object {
        $stats = Get-EXOMailboxStatistics -Identity $_ -Properties TotalItemSize, ItemCount, LastLogonTime -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Identity      = $_
            SizeGB        = if ($stats.TotalItemSize) { [math]::Round(($stats.TotalItemSize.Value.ToBytes() / 1GB), 2) } else { $null }
            ItemCount     = $stats.ItemCount
            LastLogonTime = $stats.LastLogonTime
        }
    }
}
