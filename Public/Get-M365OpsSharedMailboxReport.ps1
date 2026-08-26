function Get-M365OpsSharedMailboxReport {
    <#
    .SYNOPSIS
        Report aggregato di tutte le mailbox condivise: dimensione, data creazione e
        permessi (FullAccess/SendAs/SendOnBehalf) in un'unica riga per mailbox - pensato
        per l'export diretto con Export-M365OpsReport.
    #>
    Connect-M365OpsExchange
    # -Properties deve includere anche WhenMailboxCreated: Get-EXOMailbox restituisce di
    # default un set ridotto di proprieta' e WhenMailboxCreated non ne fa parte - senza
    # elencarlo esplicitamente WhenCreated sotto risultava sempre $null (bug reale verificato
    # dal vivo, 23/08/2026, stesso bug di Get-M365OpsAllMailboxes/Get-M365OpsSharedMailboxes).
    $shared = Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo, WhenMailboxCreated

    $shared | ForEach-Object {
        $mbx = $_
        $stats = Get-EXOMailboxStatistics -Identity $mbx.PrimarySmtpAddress -Properties TotalItemSize, ItemCount -ErrorAction SilentlyContinue
        # Bug reale (stesso schema di v0.10.1/v0.10.2/v0.10.6, trovato durante l'audit del
        # 26/08/2026): a differenza della riga statistiche sopra (gia' protetta con
        # -ErrorAction SilentlyContinue), queste due chiamate non avevano nessuna protezione -
        # un errore terminante di Get-EXOMailboxPermission/Get-EXORecipientPermission su UNA
        # sola mailbox condivisa (es. throttling momentaneo) uccideva l'intero report, facendo
        # sparire in silenzio anche tutte le mailbox condivise successive nel ciclo, per quanto
        # perfettamente lette. Isolate come le statistiche, cosi' un fallimento resta locale a
        # quella singola mailbox invece di propagarsi a tutte le altre.
        $fullAccess = try { (Get-EXOMailboxPermission -Identity $mbx.PrimarySmtpAddress -ErrorAction Stop | Where-Object { $_.User -notlike "NT AUTHORITY\*" -and -not $_.IsInherited }).User -join '; ' } catch { "Impossibile leggere: $($_.Exception.Message)" }
        $sendAs = try { (Get-EXORecipientPermission -Identity $mbx.PrimarySmtpAddress -ErrorAction Stop | Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" }).Trustee -join '; ' } catch { "Impossibile leggere: $($_.Exception.Message)" }
        $sendOnBehalf = ($mbx.GrantSendOnBehalfTo) -join '; '

        [pscustomobject]@{
            DisplayName        = $mbx.DisplayName
            PrimarySmtpAddress = $mbx.PrimarySmtpAddress
            WhenCreated        = $mbx.WhenMailboxCreated
            SizeGB             = if ($stats) { [math]::Round(($stats.TotalItemSize.Value.ToBytes() / 1GB), 2) } else { $null }
            ItemCount          = $stats.ItemCount
            FullAccess         = $fullAccess
            SendAs             = $sendAs
            SendOnBehalf       = $sendOnBehalf
        }
    }
}
