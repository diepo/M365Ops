function Get-M365OpsCompliancePolicyDetail {
    <#
    .SYNOPSIS
        Restituisce nome e impostazioni configurate di un criterio di compliance, dato il suo id.
    #>
    param(
        [Parameter(Mandatory)] [string]$PolicyId
    )
    Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceCompliancePolicies/$PolicyId"
}
