function New-M365OpsAcceptedDomain {
    <#
    .SYNOPSIS
        Aggiunge un dominio accettato al tenant. IMPORTANTE: il dominio deve gia' avere il
        record TXT di verifica proprietà pubblicato su Entra ID PRIMA di questa chiamata -
        questa cmdlet non verifica il dominio, registra solo il fatto che Exchange lo
        accetti come proprio dopo che la verifica e' gia' avvenuta altrove (portale Entra
        ID o Set-AcceptedDomain nativo con lo stesso prerequisito).
    .PARAMETER DomainType
        'Authoritative' (il tenant e' l'unico a gestire la posta per questo dominio,
        default) o 'InternalRelay'/'ExternalRelay' (scenari ibridi) - se incerto, lascia il
        default Authoritative.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$DomainName,
        [ValidateSet('Authoritative', 'InternalRelay', 'ExternalRelay')] [string]$DomainType
    )
    Connect-M365OpsExchange
    $params = @{ Name = $Name; DomainName = $DomainName }
    if ($DomainType) { $params.DomainType = $DomainType }
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    $domain = New-AcceptedDomain @params -Confirm:$false -ErrorAction Stop
    Write-Host "Dominio accettato aggiunto: $DomainName" -ForegroundColor Green
    $domain | Select-Object Name, DomainName, DomainType
}
