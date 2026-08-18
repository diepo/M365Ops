function Get-M365OpsDynamicDistributionGroupMember {
    <#
    .SYNOPSIS
        Elenca i membri CALCOLATI ORA di un gruppo di distribuzione dinamico (il filtro
        viene rivalutato ad ogni chiamata, l'elenco puo' cambiare da un momento all'altro -
        a differenza di un gruppo normale non esiste una lista di membri fissa da leggere).
    #>
    param([Parameter(Mandatory)] [string]$Identity)
    Connect-M365OpsExchange
    Get-DynamicDistributionGroupMember -Identity $Identity -ResultSize Unlimited |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientType
}
