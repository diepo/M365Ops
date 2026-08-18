function Get-M365OpsTransportRules {
    <#
    .SYNOPSIS
        Elenca le regole di flusso posta (transport rule), in ordine di priorita'.
    #>
    Connect-M365OpsExchange
    Get-TransportRule | Sort-Object Priority |
        Select-Object Name, State, Priority, Description, Comments
}
