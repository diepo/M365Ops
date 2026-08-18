function Get-M365OpsInstallerInsight {
    <#
    .SYNOPSIS
        Ispeziona un installer (exe) SENZA eseguirlo: legge i metadati embedded e cerca
        firme di installer framework noti (Inno Setup, NSIS, InstallShield, WiX). Aiuta a
        dedurre switch silenziosi e percorso di installazione plausibili — da verificare,
        non garantiti.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path $Path)) { throw "File non trovato: $Path" }

    $vi = (Get-Item $Path).VersionInfo
    $signatures = @{
        "Inno Setup"     = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
        "Nullsoft"       = "/S"
        "InstallShield"  = "/s /v`"/qn`""
        "WiX Toolset"    = "/quiet /norestart"
        "Wise Installation" = "/s"
    }

    $found = $null
    foreach ($sig in $signatures.Keys) {
        if (Select-String -Path $Path -Pattern $sig -Encoding Ascii -SimpleMatch -Quiet -ErrorAction SilentlyContinue) {
            $found = $sig
            break
        }
    }

    [pscustomobject]@{
        ProductName        = if ($vi.ProductName) { $vi.ProductName.Trim() } else { $null }
        CompanyName        = if ($vi.CompanyName) { $vi.CompanyName.Trim() } else { $null }
        FileVersion        = if ($vi.FileVersion) { $vi.FileVersion.Trim() } else { $null }
        InstallerFramework = $found
        SuggestedSilentSwitch = if ($found) { $signatures[$found] } else { $null }
        Confidence          = if ($found) { "Dedotto dalla firma nel binario - non verificato eseguendo l'installer" } else { "Nessuna firma nota trovata - servono switch noti dal vendor" }
    }
}
