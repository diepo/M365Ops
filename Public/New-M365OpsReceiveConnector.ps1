function New-M365OpsReceiveConnector {
    <#
    .SYNOPSIS
        Crea un connettore Receive personalizzato (per accettare posta da un IP/gateway
        specifico, es. un servizio di sicurezza email di terze parti). -ExtraParams passa
        altri parametri nativi di New-ReceiveConnector (es. AuthMechanism, TlsDomainCapabilities)
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "New-ReceiveConnector". Sintassi verificata contro la documentazione ufficiale
        Microsoft (non a memoria) il 18/08/2026.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$Bindings,
        [Parameter(Mandatory)] [string[]]$RemoteIPRanges,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; Bindings = $Bindings; RemoteIPRanges = $RemoteIPRanges; Custom = $true }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    $conn = New-ReceiveConnector @params -ErrorAction Stop
    Write-Host "Connettore Receive creato: $Name" -ForegroundColor Green
    $conn | Select-Object Name, Enabled, RemoteIPRanges
}
