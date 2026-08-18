function Get-M365OpsMailboxUsageReport {
    <#
    .SYNOPSIS
        Report aggregato di utilizzo per tutte le mailbox: dimensione, quota e
        percentuale di occupazione - pensato per l'export diretto con Export-M365OpsReport.
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -ResultSize Unlimited -Properties ProhibitSendQuota | ForEach-Object {
        $mbx = $_
        $stats = Get-EXOMailboxStatistics -Identity $mbx.PrimarySmtpAddress -Properties TotalItemSize -ErrorAction SilentlyContinue
        $usedGB = if ($stats.TotalItemSize) { $stats.TotalItemSize.Value.ToBytes() / 1GB } else { 0 }
        $quotaGB = $null
        if ($mbx.ProhibitSendQuota) {
            try { $quotaGB = $mbx.ProhibitSendQuota.Value.ToBytes() / 1GB } catch { $quotaGB = $null }
        }
        [pscustomobject]@{
            DisplayName          = $mbx.DisplayName
            PrimarySmtpAddress   = $mbx.PrimarySmtpAddress
            RecipientTypeDetails = $mbx.RecipientTypeDetails
            UsedGB               = [math]::Round($usedGB, 2)
            QuotaGB              = if ($quotaGB) { [math]::Round($quotaGB, 2) } else { 'Unlimited' }
            PercentUsed          = if ($quotaGB) { [math]::Round(($usedGB / $quotaGB) * 100, 1) } else { $null }
        }
    }
}
