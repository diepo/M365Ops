function Get-M365OpsMailSecurityGroups {
    <#
    .SYNOPSIS
        Elenca i gruppi di sicurezza abilitati alla posta (mail-enabled security group).
    #>
    Connect-M365OpsExchange
    Get-DistributionGroup -ResultSize Unlimited | Where-Object { $_.GroupType -match 'SecurityEnabled' } |
        Select-Object DisplayName, PrimarySmtpAddress, GroupType, ManagedBy
}
