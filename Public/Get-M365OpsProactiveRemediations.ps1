function Get-M365OpsProactiveRemediations {
    <#
    .SYNOPSIS
        Elenca/legge gli script di Proactive Remediation. Con -Identity include anche il
        riepilogo esiti (RunSummary: quanti dispositivi rilevati/corretti/falliti).
    #>
    param([string]$Identity)
    if ($Identity) {
        $script = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceHealthScripts/$Identity" -Beta
        try { $summary = Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceHealthScripts/$Identity/getRemediationSummary" -Beta } catch { $summary = $null }
        $script | Add-Member -NotePropertyName RunSummary -NotePropertyValue $summary -Force
        return $script
    }
    (Invoke-M365OpsGraphRequest -Method GET -Path "/deviceManagement/deviceHealthScripts" -Beta).value
}
