function Get-M365OpsSharedMailboxReport {
    <#
    .SYNOPSIS
        Report aggregato di tutte le mailbox condivise: dimensione, data creazione e
        permessi (FullAccess/SendAs/SendOnBehalf) in un'unica riga per mailbox - pensato
        per l'export diretto con Export-M365OpsReport.
    #>
    Connect-M365OpsExchange
    $shared = Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo

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
