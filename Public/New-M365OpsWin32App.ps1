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
    .PARAMETER MinimumFreeDiskSpaceInMB / MinimumMemoryInMB / MinimumNumberOfProcessors / MinimumCPUSpeedInMHz
        Requisiti hardware aggiuntivi, oltre ad Architecture/MinimumSupportedWindowsRelease
        (19/08/2026, richiesti esplicitamente dall'utente) - tutti facoltativi, omessi = nessun
        requisito aggiuntivo (comportamento Intune di default, invariato se non specificati).
    .PARAMETER InstallExperience
        'system' (default, invariato) o 'user' - contesto di esecuzione dell'installazione.
    .PARAMETER DeviceRestartBehavior
        'suppress' (default, invariato) 'allow', 'basedOnReturnCode' o 'force'.
    .PARAMETER MaximumInstallationTimeInMinutes
        Facoltativo - se omesso usa il default del modulo IntuneWin32App (60).
    .PARAMETER AllowAvailableUninstall
        Switch - consente la disinstallazione dal Company Portal quando l'app e' assegnata come
        'available'. Default Intune (omesso) = non consentita.
    .PARAMETER ReturnCodes
        Array di hashtable @{ ReturnCode = <int>; Type = 'success'|'softReboot'|'hardReboot'|'retry'|'failed' }
        - codici di uscita del programma di installazione oltre ai default impliciti del modulo
        (0=success, 3010=softReboot sono gia' gestiti automaticamente da Add-IntuneWin32App se
        questo parametro e' omesso).
    .PARAMETER ScopeTagNames
        Array di nomi di Scope Tag Intune GIA' esistenti (non creati da questa funzione) - da
        assegnare all'app invece del tag Default.
    .PARAMETER DependsOn / Supersedes
        Array di hashtable @{ Id = '<id app esistente>'; Type = 'AutoInstall'|'Detect' } (per
        DependsOn) o @{ Id = '<id app esistente>'; Type = 'Replace'|'Update' } (per Supersedes) -
        applicati con una chiamata SEPARATA dopo la creazione (cosi' funziona anche
        Add-IntuneWin32AppDependency/Supersedence del modulo IntuneWin32App: richiedono che
        l'app esista gia'). Facoltativi, richiedono l'ID di un'app Intune GIA' esistente - mai
        indovinato, va cercato prima con una lettura (Get-M365OpsManagedApps o graph_api_call).
    .EXAMPLE
        New-M365OpsWin32App -ExePath "C:\...\setup.exe" -DisplayName "App (test)" -Publisher "Vendor" `
            -InstallCommandLine "setup.exe /S" -UninstallCommandLine "..." `
            -DetectionPath "C:\Program Files\App" -DetectionFile "App.exe" -DetectionVersion "1.0.0"
    .EXAMPLE
        New-M365OpsWin32App -ExePath "C:\...\install.ps1" -DisplayName "Script (test)" -Publisher "Interno" `
            -InstallCommandLine 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"' -UninstallCommandLine "REM ..." `
            -DetectionMode FileExists -DetectionPath "C:\ProgramData\MiaApp" -DetectionFile "installed.txt"
    .EXAMPLE
        New-M365OpsWin32App -ExePath "C:\...\setup.exe" -DisplayName "App (test)" -InstallCommandLine "setup.exe /S" -UninstallCommandLine "..." `
            -DetectionPath "C:\Program Files\App" -DetectionFile "App.exe" -DetectionVersion "1.0.0" `
            -MinimumMemoryInMB 4096 -DeviceRestartBehavior basedOnReturnCode -AllowAvailableUninstall `
            -ReturnCodes @(@{ReturnCode=1641; Type='hardReboot'}) -ScopeTagNames @('Finance')
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
        [int]$MinimumFreeDiskSpaceInMB,
        [int]$MinimumMemoryInMB,
        [int]$MinimumNumberOfProcessors,
        [int]$MinimumCPUSpeedInMHz,
        [ValidateSet('system', 'user')] [string]$InstallExperience = 'system',
        [ValidateSet('allow', 'basedOnReturnCode', 'suppress', 'force')] [string]$DeviceRestartBehavior = 'suppress',
        [int]$MaximumInstallationTimeInMinutes,
        [switch]$AllowAvailableUninstall,
        [hashtable[]]$ReturnCodes,
        [string[]]$ScopeTagNames,
        [hashtable[]]$DependsOn,
        [hashtable[]]$Supersedes,
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

    # BUG SERIO reale trovato dal vivo il 19/08/2026: $sourceDir/$outputDir erano cartelle FISSE
    # e mai svuotate, condivise da OGNI packaging eseguito da questa funzione dall'inizio della
    # sua esistenza. Con piu' file .intunewin accumulati in $outputDir da run precedenti,
    # "Get-ChildItem $outputDir -Filter *.intunewin | Select-Object -First 1" restituiva sempre
    # il PRIMO in ordine alfabetico ("audacity-*.intunewin", presente da giorni), MAI
    # necessariamente quello appena generato in questa chiamata - un'app Intune REALE e' stata
    # creata con il payload SBAGLIATO (Audacity al posto di Git) senza alcun errore, in
    # silenzio, scoperta solo rileggendo setupFilePath dopo la creazione. Corretto rendendo
    # $sourceDir/$outputDir univoci per OGNI chiamata (sottocartella con un GUID), eliminando
    # per costruzione qualunque possibilita' di collisione con un run precedente o concorrente -
    # non serve piu' nemmeno scegliere "il primo" perche' la cartella contiene sempre e solo
    # l'output di QUESTA chiamata. Ripulita anche a fine funzione (successo o errore) per non
    # accumulare .intunewin da decine/centinaia di MB indefinitamente in %TEMP%.
    $runDir = Join-Path $WorkDir ([guid]::NewGuid().ToString())
    $sourceDir = Join-Path $runDir 'source'
    $outputDir = Join-Path $runDir 'output'
    New-Item -ItemType Directory -Force -Path $sourceDir, $outputDir | Out-Null

    try {
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

        # -ErrorAction Stop su tutte le chiamate al modulo IntuneWin32App qui sotto: fix
        # difensivo (bug-hunt 19/08/2026), stesso principio gia' applicato a EXO/PnP/Teams in
        # questo giro - non riprodotto dal vivo per questo modulo specifico (un packaging reale
        # richiede file/tempi non compatibili con un test rapido), ma nessuna di queste chiamate
        # aveva mai un controllo esplicito sull'esito.
        $detectionRule = switch ($DetectionMode) {
            'Version' {
                New-IntuneWin32AppDetectionRuleFile -Version -Path $DetectionPath -FileOrFolder $DetectionFile `
                    -Operator greaterThanOrEqual -VersionValue $DetectionVersion -Check32BitOn64System $false -ErrorAction Stop
            }
            'FileExists' {
                # Per script (ps1/bat/cmd): rileva un marker che lo script stesso crea/imposta al
                # termine con successo - fornito da chi pacchettizza, mai dedotto (18/08/2026).
                New-IntuneWin32AppDetectionRuleFile -Existence -Path $DetectionPath -FileOrFolder $DetectionFile `
                    -DetectionType Exists -Check32BitOn64System $false -ErrorAction Stop
            }
            'RegistryExists' {
                New-IntuneWin32AppDetectionRuleRegistry -Existence -KeyPath $DetectionRegistryKeyPath -ValueName $DetectionRegistryValueName `
                    -DetectionType Exists -Check32BitOn64System $false -ErrorAction Stop
            }
        }

        $requirementParams = @{ Architecture = $Architecture; MinimumSupportedWindowsRelease = $MinimumSupportedWindowsRelease; ErrorAction = 'Stop' }
        if ($MinimumFreeDiskSpaceInMB) { $requirementParams.MinimumFreeDiskSpaceInMB = $MinimumFreeDiskSpaceInMB }
        if ($MinimumMemoryInMB) { $requirementParams.MinimumMemoryInMB = $MinimumMemoryInMB }
        if ($MinimumNumberOfProcessors) { $requirementParams.MinimumNumberOfProcessors = $MinimumNumberOfProcessors }
        if ($MinimumCPUSpeedInMHz) { $requirementParams.MinimumCPUSpeedInMHz = $MinimumCPUSpeedInMHz }
        $requirementRule = New-IntuneWin32AppRequirementRule @requirementParams

        $addParams = @{
            FilePath              = $intunewinFile.FullName
            DisplayName           = $DisplayName
            Description           = $Description
            Publisher             = $Publisher
            InstallCommandLine    = $InstallCommandLine
            UninstallCommandLine  = $UninstallCommandLine
            InstallExperience     = $InstallExperience
            RestartBehavior       = $DeviceRestartBehavior
            DetectionRule         = $detectionRule
            RequirementRule       = $requirementRule
        }
        if ($IconPath -and (Test-Path $IconPath)) { $addParams.Icon = New-IntuneWin32AppIcon -FilePath $IconPath }
        if ($MaximumInstallationTimeInMinutes) { $addParams.MaximumInstallationTimeInMinutes = $MaximumInstallationTimeInMinutes }
        if ($AllowAvailableUninstall) { $addParams.AllowAvailableUninstall = $true }
        if ($ScopeTagNames) { $addParams.ScopeTagName = $ScopeTagNames }
        if ($ReturnCodes) {
            $addParams.ReturnCode = @($ReturnCodes | ForEach-Object { New-IntuneWin32AppReturnCode -ReturnCode $_.ReturnCode -Type $_.Type })
        }

        $addParams.ErrorAction = 'Stop'
        $app = Add-IntuneWin32App @addParams

        $notes = @()
        if ($DependsOn) {
            $depObjects = @($DependsOn | ForEach-Object { New-IntuneWin32AppDependency -ID $_.Id -DependencyType $_.Type -ErrorAction Stop })
            Add-IntuneWin32AppDependency -ID $app.id -Dependency $depObjects -ErrorAction Stop
            $notes += "dipendenze aggiunte: $($DependsOn.Count)"
        }
        if ($Supersedes) {
            $supObjects = @($Supersedes | ForEach-Object { New-IntuneWin32AppSupersedence -ID $_.Id -SupersedenceType $_.Type -ErrorAction Stop })
            Add-IntuneWin32AppSupersedence -ID $app.id -Supersedence $supObjects -ErrorAction Stop
            $notes += "supersedence aggiunta: $($Supersedes.Count)"
        }
        $notesText = if ($notes) { " ($($notes -join ', '))" } else { "" }

        Write-Host "Creata, NON assegnata: $($app.displayName) ($($app.id))$notesText" -ForegroundColor Green
        $app
    }
    finally {
        Remove-Item -Path $runDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
