function Get-M365OpsMailboxStatistics {
    <#
    .SYNOPSIS
        Statistiche di una mailbox (dimensione, numero elementi, ultimo logon) oppure
        di tutte se -Identity non e' specificato. Con -Archive, le STESSE statistiche ma
        dell'archivio (Online Archive) invece della mailbox primaria - per il nome/stato
        dell'archivio (ArchiveName/ArchiveStatus/ArchiveGuid) vedi invece
        Get-M365OpsMailboxDetail -Archive, che espone l'oggetto Get-Mailbox completo
        (Get-Mailbox non ha mai avuto dimensione/numero elementi, solo identita'/config).
    #>
    param([string]$Identity, [switch]$Archive)
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
    # -Archive aggiunto l'11/09/2026 (richiesto esplicitamente dall'utente, generalizzazione
    # dopo aver dovuto costruire una funzione combinata dedicata solo per il caso archivio) -
    # non serve piu' una funzione separata solo per attivare questo switch: Invoke-M365OpsAgentTools
    # espone anche $Archive nei parametri accettati per questo cmdlet nell'allowlist exo_query.
    $targets | ForEach-Object {
        $stats = Get-EXOMailboxStatistics -Identity $_ -Archive:$Archive -Properties TotalItemSize, ItemCount, LastLogonTime -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Identity      = $_
            Archive       = [bool]$Archive
            SizeGB        = if ($stats.TotalItemSize) { [math]::Round(($stats.TotalItemSize.Value.ToBytes() / 1GB), 2) } else { $null }
            ItemCount     = $stats.ItemCount
            LastLogonTime = $stats.LastLogonTime
        }
    }
}
