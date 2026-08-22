function Assert-M365OpsExoSafeVersion {
    <#
    .SYNOPSIS
        Garantisce che ExchangeOnlineManagement sia installato (l'ULTIMA versione disponibile,
        vedi PERCHE' sotto) E integro, poi lo importa (i chiamanti non lo fanno piu'
        separatamente) e imposta <code>$script:M365OpsExchangeModuleImported</code> al successo.
        Rimuove attivamente ogni ALTRA versione trovata sul disco.

        PERCHE' "ULTIMA VERSIONE" e non piu' un pin fisso (26/08/2026, sostituisce il pin a
        3.4.0 in vigore dal 25/08/2026): la ragion d'essere di un pin - evitare il conflitto
        .NET con MicrosoftTeams nello stesso processo (guida sezione 6.6) - non regge piu' come
        approccio dopo aver scoperto (v0.9.44) che NESSUNA coppia di versioni si e' rivelata
        affidabilmente sicura in OGNI ordine di connessione: la 3.4.0/6.5.0 stessa, presentata
        come "verificata", si e' poi rotta dal vivo nell'ordine Teams-poi-Purview (v0.9.50/52).
        Da qui la richiesta esplicita dell'utente: "implementa il processo isolato, usa le
        ultime versioni, rimuovi quelle vecchie". Con l'isolamento reattivo dei processi ora in
        vigore (vedi sezione 6.6 della guida per il meccanismo completo), il conflitto non e'
        piu' qualcosa da EVITARE scegliendo con cura una versione - e' qualcosa che, se scatta
        davvero, viene gestito spostando quella specifica connessione in un processo separato,
        per QUALUNQUE versione dei moduli. Non c'e' quindi piu' alcun motivo per restare indietro
        su una versione vecchia (si perdono solo bugfix/funzionalita' Microsoft nel frattempo) -
        l'ultima disponibile e' sempre la scelta giusta.

        NESSUNA query di rete ad ogni connessione (per non aggiungere latenza/dipendenza di
        rete a ogni singolo tentativo, ne' rischiare un cambio di versione a meta' sessione se
        Microsoft pubblica un aggiornamento mentre l'utente sta lavorando): se una versione e'
        GIA' installata e integra, questa funzione usa quella (la piu' recente tra quelle sul
        disco, se ce ne fossero piu' d'una) senza contattare PSGallery - la query alla galleria
        per la VERA ultima versione disponibile scatta solo quando serve un'installazione (nulla
        di gia' presente, o tutto danneggiato). Un aggiornamento a una versione piu' recente
        pubblicata da Microsoft dopo l'installazione arriva quindi al prossimo avvio pulito del
        server su un'installazione danneggiata/assente, non a meta' di una sessione attiva.

        VERIFICA L'INTEGRITA' DEI FILE, non solo la presenza del manifest (25/08/2026, bug reale
        segnalato dal vivo: dopo un riavvio pulito del server, SENZA MAI toccare Teams,
        Connect-ExchangeOnline falliva con "The given assembly name was invalid.") - un secondo
        tentativo di riparazione DENTRO <code>Invoke-M365OpsWithExoRepairRetry</code> (attorno
        alla connessione vera, non qui) e' stato provato e scartato lo stesso giorno: una volta
        che <code>Import-Module</code> ha caricato l'assembly principale nel processo, Windows
        blocca quel file (e in pratica l'intera cartella) a livello di file system - nemmeno
        <code>Remove-Item</code> riesce piu' a toccarlo. L'UNICO punto sicuro per riparare e'
        PRIMA che <code>Import-Module</code> venga mai chiamato in questo processo - cioe'
        proprio qui, dentro questa funzione, che i chiamanti invocano sempre prima di importare.
    .PARAMETER InstallOnly
        Salta l'import: garantisce solo che una versione sia presente sul disco (comportamento
        originale). Usato da <code>Install-M365OpsPrerequisites</code>, che gira ad OGNI avvio del
        server (non solo al primo) PRIMA che l'utente scelga se gli serve Teams o Exchange -
        importare il modulo li' dentro caricherebbe ExchangeOnlineManagement nel processo del
        server anche per chi vuole usare SOLO Teams in quella sessione. Le cmdlet di connessione
        vere (Connect-M365OpsExchange.ps1 e le altre) chiamano invece questa funzione SENZA
        questo switch, cosi' l'import avviene solo quando Exchange serve DAVVERO.
    .OUTPUTS
        pscustomobject con RemovedVersions (array di stringhe, versioni disinstallate con
        successo), Installed (bool, true se e' stata installata/reinstallata da questa chiamata)
        e Version (la versione in uso dopo questa chiamata) - usato da
        Install-M365OpsPrerequisites per riportare all'utente cosa e' stato fatto.
    #>
    param([switch]$InstallOnly)

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

    $installedVersions = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending)
    $bestLocal = $installedVersions | Select-Object -First 1
    $targetVersion = $null

    if ($bestLocal -and (Test-ExoInstallIntegrity -ModuleBase $bestLocal.ModuleBase)) {
        $targetVersion = $bestLocal.Version
    }
    else {
        if ($bestLocal) {
            Write-M365OpsLog "ExchangeOnlineManagement $($bestLocal.Version) presente sul disco ma con file mancanti/danneggiati (rilevato PRIMA di importarla in questo processo, quando e' ancora sicuro ripararla) - la reinstallo da zero."
            try { Remove-Item -Path $bestLocal.ModuleBase -Recurse -Force -ErrorAction Stop } catch {
                Write-M365OpsLog "Rimozione della copia danneggiata in '$($bestLocal.ModuleBase)' fallita: $($_.Exception.Message)"
            }
        }

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Write-Host "Modulo ExchangeOnlineManagement non trovato o danneggiato, installo l'ultima versione disponibile..." -ForegroundColor Yellow
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        $installedNow = $true
        $targetVersion = (Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1).Version
        $installedVersions = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending)
    }

    # Rimozione attiva di OGNI altra versione trovata (non solo quelle sopra una soglia nota
    # come "sempre in conflitto", come faceva il pin precedente) - richiesto esplicitamente
    # dall'utente ("ultime versioni, rimozione delle precedenti"), non piu' solo difesa in
    # profondita' ma il comportamento normale, dato che l'isolamento reattivo (non piu' un
    # pin) e' ora la difesa contro il conflitto di sezione 6.6.
    foreach ($old in ($installedVersions | Where-Object { $_.Version -ne $targetVersion })) {
        try {
            Write-M365OpsLog "ExchangeOnlineManagement $($old.Version) trovata installata insieme alla $targetVersion in uso - la disinstallo per lasciare solo quella in uso."
            Uninstall-Module -Name ExchangeOnlineManagement -RequiredVersion $old.Version -Force -ErrorAction Stop
            $removedVersions += $old.Version.ToString()
        }
        catch {
            Write-M365OpsLog "Disinstallazione di ExchangeOnlineManagement $($old.Version) fallita (non bloccante - Import-Module qui sotto specifica sempre -RequiredVersion $targetVersion esplicito, quindi resta comunque efficace): $($_.Exception.Message)"
        }
    }

    if (-not $InstallOnly) {
        Import-Module ExchangeOnlineManagement -RequiredVersion $targetVersion -ErrorAction Stop
        $script:M365OpsExchangeModuleImported = $true
    }

    [pscustomobject]@{ RemovedVersions = $removedVersions; Installed = $installedNow; Version = $targetVersion }
}
