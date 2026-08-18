function New-M365OpsSendConnector {
    <#
    .SYNOPSIS
        Crea un connettore Send personalizzato (per instradare la posta verso uno spazio di
        indirizzi specifico, es. "*" per tutto internet o un dominio partner). -ExtraParams
        passa altri parametri nativi di New-SendConnector (es. SmartHosts, TlsAuthLevel) -
        se non sei sicuro del nome esatto, consulta prima lookup_ms_docs "New-SendConnector".
        Sintassi verificata contro la documentazione ufficiale Microsoft (non a memoria) il
        18/08/2026.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$AddressSpaces,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; AddressSpaces = $AddressSpaces }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    $conn = New-SendConnector @params -ErrorAction Stop
    Write-Host "Connettore Send creato: $Name" -ForegroundColor Green
    $conn | Select-Object Name, Enabled, AddressSpaces
}
