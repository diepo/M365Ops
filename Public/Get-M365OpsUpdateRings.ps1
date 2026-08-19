function Get-M365OpsUpdateRings {
    <#
    .SYNOPSIS
        Elenca/legge gli anelli di aggiornamento Windows Update for Business, filtrando
        deviceConfigurations per @odata.type (la stessa collezione ospita molti altri tipi di
        profilo di configurazione legacy).
    #>
    param([string]$Identity)
    if ($Identity) {
        $ring = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceConfigurations/$Identity"
        $ring | Add-Member -NotePropertyName Assignments -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceConfigurations/$Identity/assignments").value -Force
        return $ring
    }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceConfigurations").value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' }
}
