function New-M365OpsMailSecurityGroup {
    <#
    .SYNOPSIS
        Crea un gruppo di sicurezza abilitato alla posta. -ExtraParams passa altri
        parametri nativi di New-DistributionGroup (es. ManagedBy, RequireSenderAuthenticationEnabled)
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs "New-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [string[]]$Members,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; Type = 'Security' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $grp = New-DistributionGroup @params
    foreach ($m in $Members) {
        Add-DistributionGroupMember -Identity $grp.Identity -Member $m -Confirm:$false
    }
    Write-Host "Mail security group creato: $($grp.DisplayName) ($($grp.PrimarySmtpAddress))" -ForegroundColor Green
    $grp | Select-Object DisplayName, PrimarySmtpAddress, GroupType
}
