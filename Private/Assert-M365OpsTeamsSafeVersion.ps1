function Assert-M365OpsTeamsSafeVersion {
    <#
    .SYNOPSIS
        Garantisce che MicrosoftTeams sia installato (l'ULTIMA versione disponibile, vedi
        PERCHE' sotto) E integro, poi lo importa (i chiamanti non lo fanno piu' separatamente)
        e imposta <code>$script:M365OpsTeamsModuleImported</code> al successo. Rimuove
        attivamente ogni ALTRA versione trovata sul disco. Gemella di
        Assert-M365OpsExoSafeVersion.ps1, stessa logica, stesso motivo (vedi li' per la storia
        completa del perche' non e' piu' un pin fisso a una coppia di versioni "verificata").

        NOTA sul broker WAM: dalla 7.8.1-preview in poi Connect-MicrosoftTeams usa WAM come
        broker di autenticazione di default, che fallisce in un processo server senza sessione
        interattiva - Connect-M365OpsTeams.ps1 gestisce gia' questo dinamicamente (controlla la
        versione effettivamente importata e aggiunge -DisableWAM solo se supportato/necessario),
        quindi installare sempre l'ultima versione qui non richiede nessuna modifica a questa
        funzione: il problema e' gia' risolto a valle, non qui.
    .PARAMETER InstallOnly
        Salta l'import: garantisce solo che una versione sia presente sul disco. Usato da
        <code>Install-M365OpsPrerequisites</code>, che gira ad OGNI avvio del server PRIMA che
        l'utente scelga se gli serve Teams o Exchange - importare qui caricherebbe
        MicrosoftTeams nel processo del server anche per chi vuole usare SOLO Exchange in
        quella sessione.
    .OUTPUTS
        pscustomobject con RemovedVersions (array di stringhe, versioni disinstallate con
        successo), Installed (bool, true se e' stata installata/reinstallata da questa
        chiamata) e Version (la versione in uso dopo questa chiamata).
    #>
    param([switch]$InstallOnly)

    $removedVersions = @()
    $installedNow = $false

    # Stesso principio di Assert-M365OpsExoSafeVersion.ps1: Get-Module -ListAvailable legge
    # solo il manifest, non basta a garantire che ogni DLL referenziata sia integra - un file
    # mancante in una dipendenza caricata pigramente passerebbe inosservato fino al vero
    # tentativo di connessione, quando ormai Windows ha gia' bloccato i file.
    function Test-TeamsInstallIntegrity {
        param([string]$ModuleBase)
        $criticalFiles = @(
            'netcoreapp3.1\Microsoft.TeamsCmdlets.PowerShell.Connect.dll'
            'netcoreapp3.1\Microsoft.Identity.Client.dll'
        )
        foreach ($rel in $criticalFiles) {
            $full = Join-Path $ModuleBase $rel
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
            if ((Get-Item -LiteralPath $full).Length -eq 0) { return $false }
        }
        return $true
    }

    $installedVersions = @(Get-Module -ListAvailable -Name MicrosoftTeams | Sort-Object Version -Descending)
    $bestLocal = $installedVersions | Select-Object -First 1
    $targetVersion = $null

    if ($bestLocal -and (Test-TeamsInstallIntegrity -ModuleBase $bestLocal.ModuleBase)) {
        $targetVersion = $bestLocal.Version
    }
    else {
        if ($bestLocal) {
            Write-M365OpsLog "MicrosoftTeams $($bestLocal.Version) presente sul disco ma con file mancanti/danneggiati (rilevato PRIMA di importarla in questo processo) - la reinstallo da zero."
            try { Remove-Item -Path $bestLocal.ModuleBase -Recurse -Force -ErrorAction Stop } catch {
                Write-M365OpsLog "Rimozione della copia danneggiata in '$($bestLocal.ModuleBase)' fallita: $($_.Exception.Message)"
            }
        }

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Write-Host "Modulo MicrosoftTeams non trovato o danneggiato, installo l'ultima versione disponibile..." -ForegroundColor Yellow
        Install-Module MicrosoftTeams -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        $installedNow = $true
        $targetVersion = (Get-Module -ListAvailable -Name MicrosoftTeams | Sort-Object Version -Descending | Select-Object -First 1).Version
        $installedVersions = @(Get-Module -ListAvailable -Name MicrosoftTeams | Sort-Object Version -Descending)
    }

    foreach ($old in ($installedVersions | Where-Object { $_.Version -ne $targetVersion })) {
        try {
            Write-M365OpsLog "MicrosoftTeams $($old.Version) trovata installata insieme alla $targetVersion in uso - la disinstallo per lasciare solo quella in uso."
            Uninstall-Module -Name MicrosoftTeams -RequiredVersion $old.Version -Force -ErrorAction Stop
            $removedVersions += $old.Version.ToString()
        }
        catch {
            Write-M365OpsLog "Disinstallazione di MicrosoftTeams $($old.Version) fallita (non bloccante - Import-Module qui sotto specifica sempre -RequiredVersion $targetVersion esplicito, quindi resta comunque efficace): $($_.Exception.Message)"
        }
    }

    if (-not $InstallOnly) {
        Import-Module MicrosoftTeams -RequiredVersion $targetVersion -ErrorAction Stop
        $script:M365OpsTeamsModuleImported = $true
    }

    [pscustomobject]@{ RemovedVersions = $removedVersions; Installed = $installedNow; Version = $targetVersion }
}
