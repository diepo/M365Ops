function New-M365OpsTenantAllowBlockListEntry {
    <#
    .SYNOPSIS
        Aggiunge una voce alla Tenant Allow/Block List (consente o blocca esplicitamente un
        mittente/URL/hash file/IP a livello di tenant, a prescindere da cosa direbbero i
        criteri anti-spam/anti-phishing normali).
    .PARAMETER ExpirationDate
        Se omessa insieme a -NoExpiration, il default e' 30 giorni (comportamento nativo del
        servizio) - specifica sempre uno dei due esplicitamente per evitare ambiguita'.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Sender', 'Url', 'FileHash', 'IP')] [string]$ListType,
        [Parameter(Mandatory)] [ValidateSet('Allow', 'Block')] [string]$Action,
        [Parameter(Mandatory)] [string[]]$Entries,
        [datetime]$ExpirationDate,
        [switch]$NoExpiration,
        [string]$Notes
    )
    Connect-M365OpsExchange
    $params = @{ ListType = $ListType; Entries = $Entries }
    $params[$Action] = $true
    if ($NoExpiration) { $params.NoExpiration = $true }
    elseif ($ExpirationDate) { $params.ExpirationDate = $ExpirationDate }
    else { $params.NoExpiration = $true }
    if ($Notes) { $params.Notes = $Notes }

    New-TenantAllowBlockListItems @params
    Write-Host "Voce aggiunta alla Tenant Allow/Block List ($Action, $ListType): $($Entries -join ', ')" -ForegroundColor Green
}
