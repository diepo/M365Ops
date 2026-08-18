function Get-M365OpsDistributionGroupMembers {
    <#
    .SYNOPSIS
        Elenca i membri di una distribution list o mail-enabled security group.
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Get-DistributionGroupMember -Identity $Identity -ResultSize Unlimited |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientType
}
