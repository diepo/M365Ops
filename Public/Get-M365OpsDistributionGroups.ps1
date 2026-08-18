function Get-M365OpsDistributionGroups {
    <#
    .SYNOPSIS
        Elenca le distribution list (non le mail-enabled security group, vedi
        Get-M365OpsMailSecurityGroups, ne' i gruppi dinamici, vedi Get-M365OpsDynamicDistributionGroups).
    #>
    Connect-M365OpsExchange
    Get-DistributionGroup -ResultSize Unlimited | Where-Object { $_.GroupType -notmatch 'SecurityEnabled' } |
        Select-Object DisplayName, PrimarySmtpAddress, GroupType, ManagedBy
}
