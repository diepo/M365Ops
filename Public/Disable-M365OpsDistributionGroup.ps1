function Disable-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        Disabilita la posta su un gruppo (resta un gruppo di sicurezza puro, perde
        l'indirizzo email e la capacita' di ricevere messaggi) - NON lo elimina, per quello
        vedi Remove-M365OpsDistributionGroup. -ExtraParams passa altri parametri nativi di
        Disable-DistributionGroup - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "Disable-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity; Confirm = $false }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    # -ErrorAction Stop: vedi nota in Set-M365OpsDistributionGroup.ps1 (bug reale 18/08/2026).
    Disable-DistributionGroup @params -ErrorAction Stop
    Write-Host "Posta disabilitata sul gruppo: $Identity (il gruppo resta, non e' stato eliminato)" -ForegroundColor Green
}
