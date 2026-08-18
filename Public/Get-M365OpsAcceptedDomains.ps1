function Get-M365OpsAcceptedDomains {
    <#
    .SYNOPSIS
        Elenca i domini accettati dal tenant e il relativo tipo (Authoritative, InternalRelay, ExternalRelay).
    #>
    Connect-M365OpsExchange
    Get-AcceptedDomain | Select-Object DomainName, DomainType, Default
}
