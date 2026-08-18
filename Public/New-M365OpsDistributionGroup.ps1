function New-M365OpsDistributionGroup {
    <#
    .SYNOPSIS
        Crea una distribution list, opzionalmente con membri iniziali (indirizzi email).
        -ExtraParams passa altri parametri nativi di New-DistributionGroup (es.
        ManagedBy, RequireSenderAuthenticationEnabled, ModeratedBy) - se non sei sicuro
        del nome esatto, consulta prima lookup_ms_docs "New-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [string[]]$Members,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; Type = 'Distribution' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $dl = New-DistributionGroup @params
    foreach ($m in $Members) {
        Add-DistributionGroupMember -Identity $dl.Identity -Member $m -Confirm:$false
    }
    Write-Host "Distribution list creata: $($dl.DisplayName) ($($dl.PrimarySmtpAddress))" -ForegroundColor Green
    $dl | Select-Object DisplayName, PrimarySmtpAddress, GroupType
}
