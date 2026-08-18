function Get-M365OpsGroupMembershipReport {
    <#
    .SYNOPSIS
        Report unico con una riga per ogni coppia gruppo-membro, per tutte le
        distribution list e mail-enabled security group del tenant. Utile per audit
        di membership su larga scala. Puo' essere lento su tenant con molti gruppi.
    #>
    Connect-M365OpsExchange
    Get-DistributionGroup -ResultSize Unlimited | ForEach-Object {
        $group = $_
        Get-DistributionGroupMember -Identity $group.Identity -ResultSize Unlimited | ForEach-Object {
            [pscustomobject]@{
                GroupDisplayName  = $group.DisplayName
                GroupSmtpAddress  = $group.PrimarySmtpAddress
                MemberDisplayName = $_.DisplayName
                MemberSmtpAddress = $_.PrimarySmtpAddress
                MemberType        = $_.RecipientType
            }
        }
    }
}
