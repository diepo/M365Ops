function New-M365OpsWin32App {
    <#
    .SYNOPSIS
        Pacchettizza un exe/msi/ps1/bat/cmd in .intunewin e lo carica su Intune come Win32 app.
        NON assegnata: usa Set-M365OpsAppAssignment per attivarla.
        Richiede il tool IntuneWinAppUtil.exe e il modulo IntuneWin32App (gia' installati oggi).
    .PARAMETER DetectionMode
        'Version' (default, invariato): rileva un file per versione - pensato per un exe
        installato in un percorso noto. 'FileExists'/'RegistryExists' (aggiunti il 18/08/2026 per
        supportare script ps1/bat/cmd, che non installano nulla in un percorso prevedibile):
        rileva la presenza di un marker (file o chiave di registro) che LO SCRIPT STESSO deve
        creare/impostare quando ha successo - non dedotto automaticamente, va sempre fornito da
        chi pacchettizza lo script.
    .EXAMPLE
        New-M365OpsWin32App -ExePath "C:\...\setup.exe" -DisplayName "App (test)" -Publisher "Vendor" `
            -InstallCommandLine "setup.exe /S" -UninstallCommandLine "..." `
            -DetectionPath "C:\Program Files\App" -DetectionFile "App.exe" -DetectionVersion "1.0.0"
    .EXAMPLE
        New-M365OpsWin32App -ExePath "C:\...\install.ps1" -DisplayName "Script (test)" -Publisher "Interno" `
            -InstallCommandLine 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"' -UninstallCommandLine "REM ..." `
            -DetectionMode FileExists -DetectionPath "C:\ProgramData\MiaApp" -DetectionFile "installed.txt"
    #>
    param(
        [Parameter(Mandatory)] [string]$ExePath,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Publisher = "Sconosciuto",
        [string]$Description = "Pacchettizzata da M365Ops.",
        [Parameter(Mandatory)] [string]$InstallCommandLine,
        [Parameter(Mandatory)] [string]$UninstallCommandLine,
        [ValidateSet('Version', 'FileExists', 'RegistryExists')] [string]$DetectionMode = 'Version',
        [string]$DetectionPath,
        [string]$DetectionFile,
        [string]$DetectionVersion,
        [string]$DetectionRegistryKeyPath,
        [string]$DetectionRegistryValueName,
        [string]$Architecture = "x64",
        [string]$MinimumSupportedWindowsRelease = "W10_1607",
        [string]$IntuneWinToolPath = (Join-Path $script:M365OpsModuleRoot 'Tools\IntuneWinAppUtil.exe'),
        [string]$WorkDir = (Join-Path $env:TEMP 'M365OpsPackaging'),
        [string]$IconPath
    )

    switch ($DetectionMode) {
        'Version'        { if (-not $DetectionPath -or -not $DetectionFile -or -not $DetectionVersion) { throw "DetectionMode 'Version' richiede -DetectionPath, -DetectionFile e -DetectionVersion." } }
        'FileExists'     { if (-not $DetectionPath -or -not $DetectionFile) { throw "DetectionMode 'FileExists' richiede -DetectionPath e -DetectionFile." } }
        'RegistryExists' { if (-not $DetectionRegistryKeyPath -or -not $DetectionRegistryValueName) { throw "DetectionMode 'RegistryExists' richiede -DetectionRegistryKeyPath e -DetectionRegistryValueName." } }
    }

    if (-not (Test-Path $IntuneWinToolPath)) { throw "IntuneWinAppUtil.exe non trovato in $IntuneWinToolPath" }
    Import-Module IntuneWin32App -ErrorAction Stop

    $sourceDir = Join-Path $WorkDir 'source'
    $outputDir = Join-Path $WorkDir 'output'
    New-Item -ItemType Directory -Force -Path $sourceDir, $outputDir | Out-Null
    Copy-Item -Path $ExePath -Destination $sourceDir -Force
    $setupFile = Split-Path -Leaf $ExePath

    & $IntuneWinToolPath -c $sourceDir -s $setupFile -o $outputDir -q
    $intunewinFile = Get-ChildItem $outputDir -Filter "*.intunewin" | Select-Object -First 1
    if (-not $intunewinFile) { throw "Packaging fallito: nessun .intunewin generato." }

    # Connect-M365OpsIntune fallisce SUBITO con un messaggio chiaro se il tenant e'
    # Delegated e non c'e' gia' una sessione Intune attiva, invece di bloccare in silenzio
    # l'intero processo qui dentro un flusso composto (incidente reale del 15/08/2026) -
    # l'utente deve cliccare "Connetti Intune (browser)" nella GUI prima, esplicitamente.
    Connect-M365OpsIntune

    $detectionRule = switch ($DetectionMode) {
        'Version' {
            New-IntuneWin32AppDetectionRuleFile -Version -Path $DetectionPath -FileOrFolder $DetectionFile `
                -Operator greaterThanOrEqual -VersionValue $DetectionVersion -Check32BitOn64System $false
        }
        'FileExists' {
            # Per script (ps1/bat/cmd): rileva un marker che lo script stesso crea/imposta al
            # termine con successo - fornito da chi pacchettizza, mai dedotto (18/08/2026).
            New-IntuneWin32AppDetectionRuleFile -Existence -Path $DetectionPath -FileOrFolder $DetectionFile `
                -DetectionType Exists -Check32BitOn64System $false
        }
        'RegistryExists' {
            New-IntuneWin32AppDetectionRuleRegistry -Existence -KeyPath $DetectionRegistryKeyPath -ValueName $DetectionRegistryValueName `
                -DetectionType Exists -Check32BitOn64System $false
        }
    }

    $requirementRule = New-IntuneWin32AppRequirementRule -Architecture $Architecture -MinimumSupportedWindowsRelease $MinimumSupportedWindowsRelease

    $addParams = @{
        FilePath              = $intunewinFile.FullName
        DisplayName           = $DisplayName
        Description           = $Description
        Publisher             = $Publisher
        InstallCommandLine    = $InstallCommandLine
        UninstallCommandLine  = $UninstallCommandLine
        InstallExperience     = "system"
        RestartBehavior       = "suppress"
        DetectionRule         = $detectionRule
        RequirementRule       = $requirementRule
    }
    if ($IconPath -and (Test-Path $IconPath)) {
        $addParams.Icon = New-IntuneWin32AppIcon -FilePath $IconPath
    }

    $app = Add-IntuneWin32App @addParams

    Write-Host "Creata, NON assegnata: $($app.displayName) ($($app.id))" -ForegroundColor Green
    $app
}
