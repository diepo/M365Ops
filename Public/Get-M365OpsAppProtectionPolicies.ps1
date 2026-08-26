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

    if ($Platform -ne 'Both') {
        return @(Get-OnePlatform -plat $Platform)
    }

    # Platform 'Both': Android e iOS sono due chiamate Graph indipendenti su due collezioni
    # diverse (androidManagedAppProtections / iosManagedAppProtections) - try/catch separato
    # per piattaforma (26/08/2026, stesso schema gia' trovato piu' volte in questo progetto,
    # vedi Get-M365OpsDelegatedPermissionsCheck, commit 0dfc6fd): prima di questo fix, un
    # errore Graph su UNA sola piattaforma (es. throttling, o un problema momentaneo solo su
    # quella collezione) faceva fallire l'intera funzione, nascondendo anche i criteri
    # dell'altra piattaforma gia' recuperati con successo.
    $results = @()
    $errors = @()
    try { $results += Get-OnePlatform -plat 'Android' } catch { $errors += "Android: $($_.Exception.Message)" }
    try { $results += Get-OnePlatform -plat 'iOS' } catch { $errors += "iOS: $($_.Exception.Message)" }
    if ($errors) {
        Write-M365OpsLog "Get-M365OpsAppProtectionPolicies: recupero fallito per $($errors -join '; ') - mostrati solo i risultati della/e piattaforma/e riuscita/e." -Level Warn
    }
    $results
}
