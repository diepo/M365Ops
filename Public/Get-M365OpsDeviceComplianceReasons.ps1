function Get-M365OpsDeviceComplianceReasons {
    <#
    .SYNOPSIS
        Per un dispositivo specifico, restituisce i criteri di compliance valutati e quale
        stato hanno. Dato grezzo — nessuna interpretazione qui.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$Id
    )
    process {
        (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/managedDevices/$Id/deviceCompliancePolicyStates").value
    }
}
