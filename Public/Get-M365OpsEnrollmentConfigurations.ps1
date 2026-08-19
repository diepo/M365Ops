function Get-M365OpsEnrollmentConfigurations {
    <#
    .SYNOPSIS
        Elenca/legge tutte le configurazioni di restrizione/limite di iscrizione dispositivi
        (deviceEnrollmentConfiguration e derivati: limite dispositivi, restrizioni piattaforma,
        Enrollment Status Page, ecc.) con priorita' e assegnazioni.
    #>
    param([string]$Identity)
    if ($Identity) {
        $cfg = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceEnrollmentConfigurations/$Identity"
        $cfg | Add-Member -NotePropertyName Assignments -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceEnrollmentConfigurations/$Identity/assignments").value -Force
        return $cfg
    }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceEnrollmentConfigurations").value | Sort-Object priority
}
