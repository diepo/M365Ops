function Get-M365OpsDynamicDistributionGroups {
    <#
    .SYNOPSIS
        Elenca i gruppi di distribuzione dinamici e il loro filtro destinatari.
    #>
    Connect-M365OpsExchange
    Get-DynamicDistributionGroup -ResultSize Unlimited |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientFilter
}
