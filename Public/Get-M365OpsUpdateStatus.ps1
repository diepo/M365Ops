function Get-M365OpsUpdateStatus {
    <#
    .SYNOPSIS
        Confronta la versione installata (ModuleVersion in M365Ops.psd1) con l'ultima
        Release pubblicata su GitHub per il canale scelto (Get-M365OpsUpdateChannel) e
        segnala se c'e' un aggiornamento disponibile. Sola lettura: non scarica ne'
        applica nulla (vedi Install-M365OpsUpdate per quello).
    .NOTES
        Mode: ReadOnly
    #>
    $manifestPath = Join-Path $script:M365OpsModuleRoot 'M365Ops.psd1'
    $currentVersion = (Import-PowerShellDataFile -Path $manifestPath).ModuleVersion
    $channel = Get-M365OpsUpdateChannel

    $release = $null
    $errorMessage = $null
    try {
        $release = Get-M365OpsGitHubRelease -Channel $channel
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    $updateAvailable = $false
    if ($release -and $release.Version) {
        try { $updateAvailable = [version]$release.Version -gt [version]$currentVersion } catch { $updateAvailable = $release.Version -ne $currentVersion }
    }

    [pscustomobject]@{
        CurrentVersion  = $currentVersion
        Channel         = $channel
        LatestVersion   = if ($release) { $release.Version } else { $null }
        LatestTag       = if ($release) { $release.Tag } else { $null }
        UpdateAvailable = $updateAvailable
        Notes           = if ($release) { $release.Notes } else { $null }
        PublishedAt     = if ($release) { $release.PublishedAt } else { $null }
        HtmlUrl         = if ($release) { $release.HtmlUrl } else { $null }
        IsPrerelease    = if ($release) { $release.IsPrerelease } else { $null }
        Error           = $errorMessage
    }
}
