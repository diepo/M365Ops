function Assert-M365OpsTeamsSafeVersion {
    <#
    .SYNOPSIS
        Garantisce che MicrosoftTeams 6.5.0 - la versione verificata dal vivo, in coppia con
        ExchangeOnlineManagement 3.4.0 (connesso PRIMA), come priva del conflitto di sezione 6.6
        in OGNI modalita' d'uso del progetto (App-only, login delegato Exchange via device-code,
        Purview) - sia installata E integra, poi la importa (i chiamanti non lo fanno piu'
        separatamente) e imposta <code>$script:M365OpsTeamsModuleImported</code> al successo.

        STORIA COMPLETA di come si e' arrivati a questa coppia specifica (25/08/2026), perche' il
        percorso conta quanto il numero di versione: prima si era pinnata solo
        ExchangeOnlineManagement a 3.9.0 (senza pin su Teams), poi si era scoperto che NESSUN
        ordine di connessione era affidabilmente sicuro con quel pin, indipendentemente dalla
        versione di Teams installata (matrice di test su Teams 7.1.0/7.3.1/7.9.0). L'utente ha
        pero' insistito, ricordando correttamente che "fino all'altro giorno" tutto funzionava,
        e ha guidato la ricerca verso versioni piu' vecchie di ENTRAMBI i moduli. Analizzando la
        libreria di autenticazione condivisa (Microsoft.Identity.Client.dll) bundled in ogni
        versione rilasciata di entrambi i moduli (16 versioni Exchange, 16 versioni Teams): NESSUNA
        coppia condivide la build ESATTA in nessun punto della storia di nessuno dei due moduli -
        quindi non esiste una versione "perfettamente compatibile" in senso stretto. La coppia
        3.4.0/6.5.0 (Microsoft.Identity.Client 4.44.0.0 vs 4.29.0.0, non identiche) e' pero'
        risultata VERIFICATA COME SICURA in un ordine specifico (Exchange connesso prima di
        Teams) attraverso un test dal vivo completo di TUTTI i flussi usati da questo progetto:
        Exchange App-only (certificato), Exchange delegato (device-code, -AccessToken - quello che
        l'utente ha confermato di usare attivamente), Purview App-only (Connect-IPPSSession), e
        infine Teams App-only connesso DOPO tutti e tre - nessun conflitto in nessuno dei quattro
        passaggi, verificato due volte per escludere un risultato casuale.

        3.4.0 e' anche la prima versione di ExchangeOnlineManagement con TUTTO cio' che serve
        (CertificateThumbprint aggiunto in 2.0.3, AccessToken aggiunto tra 3.0.0 e 3.4.0,
        CertificateThumbprint su Connect-IPPSSession aggiunto in 3.0.0) - non e' stata scelta a
        caso, e' la piu' vecchia versione VIABILE, per restare il piu' possibile lontana (in
        termini di eta'/dipendenze) dalla soglia 3.10.0 dove il conflitto torna sempre presente.
        6.5.0 e' stata preferita a 5.0.0 (anch'essa verificata sicura nella stessa coppia) perche'
        piu' recente a parita' di Microsoft.Identity.Client bundled (4.29.0.0, condiviso da tutte
        le versioni Teams 4.0.0-6.5.0) - piu' bugfix, e PREDATA anche il passaggio di
        Connect-MicrosoftTeams a WAM come broker di default (introdotto in 7.8.1-preview), quindi
        non soffre nemmeno di quel problema (sezione 10.6/17.14) per costruzione, non serve
        nessuna gestione condizionale di -DisableWAM per questa versione.
    .PARAMETER InstallOnly
        Salta l'import: garantisce solo che la 6.5.0 sia presente sul disco. Usato da
        <code>Install-M365OpsPrerequisites</code>, che gira ad OGNI avvio del server PRIMA che
        l'utente scelga se gli serve Teams o Exchange - stesso motivo di
        Assert-M365OpsExoSafeVersion.ps1: importare qui caricherebbe MicrosoftTeams nel processo
        del server anche per chi vuole usare SOLO Exchange in quella sessione.
    .OUTPUTS
        pscustomobject con Installed (bool, true se la 6.5.0 e' stata installata/reinstallata da
        questa chiamata).
    #>
    param([switch]$InstallOnly)

    $safeVersion = [version]'6.5.0'
    $installedNow = $false

    # Stesso principio di Assert-M365OpsExoSafeVersion.ps1 (25/08/2026): Get-Module -ListAvailable
    # legge solo il manifest, non basta a garantire che ogni DLL referenziata sia integra - un file
    # mancante in una dipendenza caricata pigramente passerebbe inosservato fino al vero tentativo
    # di connessione, quando ormai Windows ha gia' bloccato i file e non e' piu' possibile riparare.
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

    $safeCopy = Get-Module -ListAvailable -Name MicrosoftTeams | Where-Object Version -eq $safeVersion
    $needsInstall = -not $safeCopy
    if ($safeCopy -and -not (Test-TeamsInstallIntegrity -ModuleBase $safeCopy.ModuleBase)) {
        Write-M365OpsLog "MicrosoftTeams $safeVersion presente sul disco ma con file mancanti/danneggiati (rilevato PRIMA di importarla in questo processo) - la reinstallo da zero."
        try { Remove-Item -Path $safeCopy.ModuleBase -Recurse -Force -ErrorAction Stop } catch {
            Write-M365OpsLog "Rimozione della copia danneggiata in '$($safeCopy.ModuleBase)' fallita: $($_.Exception.Message)"
        }
        $needsInstall = $true
    }

    if ($needsInstall) {
        Write-Host "Modulo MicrosoftTeams $safeVersion non trovato o danneggiato, lo (re)installo..." -ForegroundColor Yellow
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Install-Module MicrosoftTeams -RequiredVersion $safeVersion -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        $installedNow = $true
    }

    if (-not $InstallOnly) {
        Import-Module MicrosoftTeams -RequiredVersion $safeVersion -ErrorAction Stop
        $script:M365OpsTeamsModuleImported = $true
    }

    [pscustomobject]@{ Installed = $installedNow }
}
