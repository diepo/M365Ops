function New-M365OpsInboundConnector {
    <#
    .SYNOPSIS
        Crea un connettore Inbound personalizzato (per accettare posta da un dominio/IP
        sorgente specifico, es. un gateway di sicurezza email di terze parti). -ExtraParams
        passa altri parametri nativi di New-InboundConnector (es. SenderIPAddresses,
        RestrictDomainsToIPAddresses, RequireTls, TlsSenderCertificateName) - se non sei
        sicuro del nome esatto, consulta prima lookup_ms_docs "New-InboundConnector".
        Sintassi verificata contro la documentazione ufficiale Microsoft (non a memoria) il
        21/08/2026 - vedi nota strutturale in Get-M365OpsInboundConnector.ps1 sul motivo del
        cambio di nome (era New-M365OpsReceiveConnector, un cmdlet on-premises-only che non
        e' mai esistito in Exchange Online).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$SenderDomains,
        [ValidateSet('Partner', 'OnPremises')] [string]$ConnectorType = 'Partner',
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; SenderDomains = $SenderDomains; ConnectorType = $ConnectorType }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    $conn = New-InboundConnector @params -ErrorAction Stop
    Write-Host "Connettore Inbound creato: $Name" -ForegroundColor Green
    $conn | Select-Object Name, Enabled, ConnectorType, SenderDomains
}
