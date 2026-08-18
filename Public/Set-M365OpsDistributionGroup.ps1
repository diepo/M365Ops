function Set-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        Modifica una distribution list esistente (nome, visibilita' in rubrica, o qualunque
        altra proprieta' via -ExtraParams). Passa solo i parametri da cambiare - quelli
        omessi restano invariati. -ExtraParams passa altri parametri nativi di
        Set-DistributionGroup (es. RequireSenderAuthenticationEnabled, ModeratedBy,
        ManagedBy) - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "Set-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [string]$DisplayName,
        [Nullable[bool]]$HiddenFromAddressListsEnabled,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    if ($DisplayName) { $params.DisplayName = $DisplayName }
    if ($null -ne $HiddenFromAddressListsEnabled) { $params.HiddenFromAddressListsEnabled = $HiddenFromAddressListsEnabled }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    # -ErrorAction Stop obbligatorio (bug reale trovato dal vivo il 18/08/2026 su un cmdlet
    # gemello - New-TenantAllowBlockListSpoofItems): molti cmdlet Exchange nativi emettono un
    # errore NON terminante e non lanciano un'eccezione - senza Stop, questa funzione
    # riporterebbe "aggiornato" anche quando la scrittura e' silenziosamente fallita.
    Set-DistributionGroup @params -ErrorAction Stop
    Write-Host "Gruppo di distribuzione aggiornato: $Identity" -ForegroundColor Green
    Get-DistributionGroup -Identity $Identity | Select-Object DisplayName, PrimarySmtpAddress, HiddenFromAddressListsEnabled
}
