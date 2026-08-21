function Assert-M365OpsExoSafeVersion {
    <#
    .SYNOPSIS
        Garantisce che ExchangeOnlineManagement 3.9.0 - unica versione verificata dal vivo come
        conflict-free con MicrosoftTeams nello stesso processo server, vedi
        Connect-M365OpsExchange.ps1 e guida sezione 6.6 per il dettaglio completo della verifica
        - sia installata, disinstallando attivamente qualunque versione nella fascia nota come in
        conflitto (>= 3.10.0) se gia' presente sul disco. Importa anche il modulo (i chiamanti non
        devono piu' farlo separatamente) e imposta
        <code>$script:M365OpsExchangeModuleImported</code> al successo.

        Richiesto esplicitamente dall'utente il 23/08/2026 dopo il primo fix (v0.9.41, che si
        limitava a un pin -RequiredVersion su Import-Module/Install-Module senza mai rimuovere
        una versione sbagliata gia' presente): "aggiungi un check ovvero che se e' installata la
        3.10 allora la disinstalla e mette la 3.9" - il pin da solo protegge questo progetto (che
        chiama sempre -RequiredVersion esplicito), ma una versione 3.10+ lasciata comunque sul
        disco resta un rischio inutile per qualunque altro script/strumento che importi il modulo
        senza pin (compreso un futuro sviluppo distratto di questo stesso progetto), oltre a pura
        confusione per chi ispeziona i moduli installati chiedendosi quale sia quella "vera".

        VERIFICA L'INTEGRITA' DEI FILE, non solo la presenza del manifest (25/08/2026, bug reale
        segnalato dal vivo: dopo un riavvio pulito del server, SENZA MAI toccare Teams,
        Connect-ExchangeOnline falliva con "The given assembly name was invalid.") - un secondo
        tentativo di riparazione DENTRO <code>Invoke-M365OpsWithExoRepairRetry</code> (attorno
        alla connessione vera, non qui) e' stato provato e scartato lo stesso giorno: una volta
        che <code>Import-Module</code> ha caricato l'assembly principale nel processo, Windows
        blocca quel file (e in pratica l'intera cartella) a livello di file system - nemmeno
        <code>Remove-Item</code> riesce piu' a toccarlo, verificato dal vivo con un secondo test
        (il primo tentativo di riparazione "in-process" falliva silenziosamente, dando la falsa
        impressione di aver riparato quando in realta' l'errore restava identico). L'UNICO punto
        sicuro per riparare e' PRIMA che <code>Import-Module</code> venga mai chiamato in questo
        processo - cioe' proprio qui, dentro questa funzione, che i chiamanti invocano sempre
        prima di importare. <code>Get-Module -ListAvailable</code> da solo non basta: legge solo
        il manifest (.psd1), non verifica che OGNI DLL referenziata esista e sia integra - un
        file mancante/danneggiato in una dipendenza usata pigramente (es.
        <code>Microsoft.Identity.Client.dll</code>, toccata solo quando
        <code>Connect-ExchangeOnline</code> esegue davvero l'autenticazione, MAI durante
        <code>Import-Module</code> stesso) passa quindi inosservato finche' non e' troppo tardi
        per ripararlo. Questa funzione ora controlla esplicitamente che i file critici esistano e
        non siano vuoti, e tratta un'installazione "presente ma danneggiata" come "da
        reinstallare", esattamente come farebbe per una versione mancante.
    .PARAMETER InstallOnly
        Salta l'import: garantisce solo che la 3.9.0 sia presente sul disco (comportamento
        originale). Usato da <code>Install-M365OpsPrerequisites</code>, che gira ad OGNI avvio del
        server (non solo al primo) PRIMA che l'utente scelga se gli serve Teams o Exchange -
        importare il modulo li' dentro caricherebbe ExchangeOnlineManagement nel processo del
        server anche per chi vuole usare SOLO Teams in quella sessione, rendendo quel processo
        piu' soggetto al conflitto di sezione 6.6 per un motivo del tutto estraneo alla scelta
        reale dell'utente. Le cmdlet di connessione vere (Connect-M365OpsExchange.ps1 e le altre)
        chiamano invece questa funzione SENZA questo switch, cosi' l'import avviene solo quando
        Exchange serve DAVVERO.
    .OUTPUTS
        pscustomobject con RemovedVersions (array di stringhe, versioni disinstallate con
        successo) e Installed (bool, true se la 3.9.0 e' stata installata da questa chiamata) -
        usato da Install-M365OpsPrerequisites per riportare all'utente cosa e' stato fatto, non
        solo se il modulo e' presente.
    #>
    param([switch]$InstallOnly)

    $safeVersion = [version]'3.9.0'
    $conflictFloor = [version]'3.10.0'
    $removedVersions = @()
    $installedNow = $false

    # File critici la cui assenza/vuotezza indica un'installazione danneggiata - il modulo
    # principale (caricato da Import-Module, se manca Import-Module fallisce da solo e lo
    # scopriamo comunque) e Microsoft.Identity.Client.dll (caricato PIGRAMENTE solo da
    # Connect-ExchangeOnline - se manca, Import-Module NON se ne accorge, questo controllo si').
    function Test-ExoInstallIntegrity {
        param([string]$ModuleBase)
        $criticalFiles = @(
            'netCore\Microsoft.Exchange.Management.ExoPowershellGalleryModule.dll'
            'netCore\Microsoft.Identity.Client.dll'
        )
        foreach ($rel in $criticalFiles) {
            $full = Join-Path $ModuleBase $rel
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
            if ((Get-Item -LiteralPath $full).Length -eq 0) { return $false }
        }
        return $true
    }

    $installed = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement)
    $conflicting = @($installed | Where-Object { $_.Version -ge $conflictFloor })
    foreach ($bad in $conflicting) {
        try {
            Write-M365OpsLog "ExchangeOnlineManagement $($bad.Version) trovata installata - nota per andare in conflitto con MicrosoftTeams nello stesso processo (guida sezione 6.6), la disinstallo per lasciare solo la $safeVersion."
            Uninstall-Module -Name ExchangeOnlineManagement -RequiredVersion $bad.Version -Force -ErrorAction Stop
            $removedVersions += $bad.Version.ToString()
        }
        catch {
            Write-M365OpsLog "Disinstallazione di ExchangeOnlineManagement $($bad.Version) fallita (non bloccante - il pin -RequiredVersion $safeVersion nelle chiamate di connessione resta comunque efficace indipendentemente da questo): $($_.Exception.Message)"
        }
    }

    $safeCopy = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Where-Object Version -eq $safeVersion
    $needsInstall = -not $safeCopy
    if ($safeCopy -and -not (Test-ExoInstallIntegrity -ModuleBase $safeCopy.ModuleBase)) {
        Write-M365OpsLog "ExchangeOnlineManagement $safeVersion presente sul disco ma con file mancanti/danneggiati (rilevato PRIMA di importarla in questo processo, quando e' ancora sicuro ripararla) - la reinstallo da zero."
        try { Remove-Item -Path $safeCopy.ModuleBase -Recurse -Force -ErrorAction Stop } catch {
            Write-M365OpsLog "Rimozione della copia danneggiata in '$($safeCopy.ModuleBase)' fallita: $($_.Exception.Message)"
        }
        $needsInstall = $true
    }

    if ($needsInstall) {
        Write-Host "Modulo ExchangeOnlineManagement $safeVersion non trovato o danneggiato, lo (re)installo..." -ForegroundColor Yellow
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Install-Module ExchangeOnlineManagement -RequiredVersion $safeVersion -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        $installedNow = $true
    }

    if (-not $InstallOnly) {
        Import-Module ExchangeOnlineManagement -RequiredVersion $safeVersion -ErrorAction Stop
        $script:M365OpsExchangeModuleImported = $true
    }

    [pscustomobject]@{ RemovedVersions = $removedVersions; Installed = $installedNow }
}
