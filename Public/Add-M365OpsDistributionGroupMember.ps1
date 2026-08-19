function Add-M365OpsDistributionGroupMember {
    <#
    .SYNOPSIS
        Aggiunge un membro a una distribution list o mail-enabled security group.
        -ExtraParams passa altri parametri nativi di Add-DistributionGroupMember - se non
        sei sicuro del nome esatto, consulta prima lookup_ms_docs "Add-DistributionGroupMember".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$Member,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop OBBLIGATORIO - bug reale trovato dal vivo il 19/08/2026 durante un
    # bug-hunt mirato: senza, "Couldn't find object" e' non terminante e veniva ignorato in
    # silenzio, la funzione riportava Added=$true senza aver aggiunto nulla per davvero
    # (verificato: Get-DistributionGroupMember restituiva 0 membri subito dopo).
    $params = @{ Identity = $Identity; Member = $Member; Confirm = $false; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Add-DistributionGroupMember @params
    Write-Host "$Member aggiunto a $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Member = $Member; Added = $true }
}
