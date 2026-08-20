function New-M365OpsOutboundConnector {
    <#
    .SYNOPSIS
        Crea un connettore Outbound personalizzato (per instradare la posta verso un
        dominio/partner specifico tramite uno smart host, invece che direttamente via DNS/
        internet). -ExtraParams passa altri parametri nativi di New-OutboundConnector (es.
        TlsSettings, TlsDomain, ConnectorType) - se non sei sicuro del nome esatto, consulta
        prima lookup_ms_docs "New-OutboundConnector". Sintassi verificata contro la
        documentazione ufficiale Microsoft (non a memoria) il 21/08/2026 - vedi nota
        strutturale in Get-M365OpsInboundConnector.ps1 sul motivo del cambio di nome (era
        New-M365OpsSendConnector, un cmdlet on-premises-only che non e' mai esistito in
        Exchange Online). Unico parametro davvero obbligatorio per New-OutboundConnector e'
        Name - RecipientDomains/SmartHosts sono facoltativi ma quasi sempre voluti insieme
        per uno scopo pratico, quindi esposti qui come parametri nominati invece che solo
        via -ExtraParams.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string[]]$RecipientDomains,
        [string[]]$SmartHosts,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name }
    if ($RecipientDomains) { $params.RecipientDomains = $RecipientDomains }
    if ($SmartHosts) { $params.SmartHosts = $SmartHosts; $params.UseMXRecord = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    $conn = New-OutboundConnector @params -ErrorAction Stop
    Write-Host "Connettore Outbound creato: $Name" -ForegroundColor Green
    $conn | Select-Object Name, Enabled, RecipientDomains, SmartHosts
}
