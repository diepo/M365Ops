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
        $fullAccess = (Get-EXOMailboxPermission -Identity $mbx.PrimarySmtpAddress | Where-Object { $_.User -notlike "NT AUTHORITY\*" -and -not $_.IsInherited }).User -join '; '
        $sendAs = (Get-EXORecipientPermission -Identity $mbx.PrimarySmtpAddress | Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" }).Trustee -join '; '
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
