function Get-M365OpsGroupsOverviewReport {
    <#
    .SYNOPSIS
        Report aggregato di tutti i tipi di gruppo lato Exchange (distribution list,
        mail-enabled security group, dynamic distribution group) con conteggio membri.
    #>
    Connect-M365OpsExchange
    $static = Get-DistributionGroup -ResultSize Unlimited
    $dynamic = Get-DynamicDistributionGroup -ResultSize Unlimited

    $staticRows = $static | ForEach-Object {
        $type = if ($_.GroupType -match 'SecurityEnabled') { 'MailSecurityGroup' } else { 'DistributionList' }
        $memberCount = (Get-DistributionGroupMember -Identity $_.Identity -ResultSize Unlimited).Count
        [pscustomobject]@{ DisplayName = $_.DisplayName; PrimarySmtpAddress = $_.PrimarySmtpAddress; Type = $type; MemberCount = $memberCount }
    }
    $dynamicRows = $dynamic | ForEach-Object {
        [pscustomobject]@{ DisplayName = $_.DisplayName; PrimarySmtpAddress = $_.PrimarySmtpAddress; Type = 'DynamicDistributionGroup'; MemberCount = $null }
    }

    @($staticRows) + @($dynamicRows)
}
