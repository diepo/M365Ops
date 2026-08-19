function Get-M365OpsAppProtectionPolicies {
    <#
    .SYNOPSIS
        Elenca/legge i criteri di protezione app (MAM) Android e/o iOS, con gruppi assegnati e
        app di destinazione quando si specifica -Identity.
    #>
    param(
        [ValidateSet('Android', 'iOS', 'Both')] [string]$Platform = 'Both',
        [string]$Identity
    )

    function Get-OnePlatform([string]$plat, [string]$id) {
        $base = if ($plat -eq 'Android') { "/deviceAppManagement/androidManagedAppProtections" } else { "/deviceAppManagement/iosManagedAppProtections" }
        if ($id) {
            $policy = Invoke-M365OpsGraphRequest -Method GET -Path "$base/$id"
            $policy | Add-Member -NotePropertyName Assignments -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "$base/$id/assignments").value -Force
            $policy | Add-Member -NotePropertyName TargetedApps -NotePropertyValue (Invoke-M365OpsGraphRequest -Method GET -Path "$base/$id/apps").value -Force
            $policy | Add-Member -NotePropertyName Platform -NotePropertyValue $plat -Force
            return $policy
        }
        (Invoke-M365OpsGraphRequest -Method GET -Path $base).value | ForEach-Object { $_ | Add-Member -NotePropertyName Platform -NotePropertyValue $plat -Force -PassThru }
    }

    if ($Identity) {
        if ($Platform -eq 'Both') { throw "Specifica -Platform Android oppure iOS insieme a -Identity." }
        return Get-OnePlatform -plat $Platform -id $Identity
    }

    $results = @()
    if ($Platform -in 'Android', 'Both') { $results += Get-OnePlatform -plat 'Android' }
    if ($Platform -in 'iOS', 'Both') { $results += Get-OnePlatform -plat 'iOS' }
    $results
}
