function Assert-M365OpsExoSafeVersion {
    <#
    .SYNOPSIS
        Garantisce che ExchangeOnlineManagement 3.9.0 - unica versione verificata dal vivo come
        conflict-free con MicrosoftTeams nello stesso processo server, vedi
        Connect-M365OpsExchange.ps1 e guida sezione 6.6 per il dettaglio completo della verifica
        - sia installata, e disinstalla attivamente qualunque versione nella fascia nota come in
        conflitto (>= 3.10.0) se gia' presente sul disco.

        Richiesto esplicitamente dall'utente il 23/08/2026 dopo il primo fix (v0.9.41, che si
        limitava a un pin -RequiredVersion su Import-Module/Install-Module senza mai rimuovere
        una versione sbagliata gia' presente): "aggiungi un check ovvero che se e' installata la
        3.10 allora la disinstalla e mette la 3.9" - il pin da solo protegge questo progetto (che
        chiama sempre -RequiredVersion esplicito), ma una versione 3.10+ lasciata comunque sul
        disco resta un rischio inutile per qualunque altro script/strumento che importi il modulo
        senza pin (compreso un futuro sviluppo distratto di questo stesso progetto), oltre a pura
        confusione per chi ispeziona i moduli installati chiedendosi quale sia quella "vera".

        Non lancia mai eccezioni: la disinstallazione di una versione in conflitto e'
        best-effort (puo' fallire se quella versione risulta gia' importata in QUESTA sessione,
        raro dato che questa funzione gira sempre prima di qualunque Import-Module nei chiamanti)
        - un fallimento qui e' solo loggato, il pin -RequiredVersion nei chiamanti resta comunque
        efficace indipendentemente da cosa rimane sul disco.
    .OUTPUTS
        pscustomobject con RemovedVersions (array di stringhe, versioni disinstallate con
        successo) e Installed (bool, true se la 3.9.0 e' stata installata da questa chiamata) -
        usato da Install-M365OpsPrerequisites per riportare all'utente cosa e' stato fatto,
        non solo se il modulo e' presente.
    #>
    $safeVersion = [version]'3.9.0'
    $conflictFloor = [version]'3.10.0'
    $removedVersions = @()
    $installedNow = $false

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

    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement | Where-Object Version -eq $safeVersion)) {
        Write-Host "Modulo ExchangeOnlineManagement $safeVersion non trovato, lo installo..." -ForegroundColor Yellow
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Install-Module ExchangeOnlineManagement -RequiredVersion $safeVersion -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        $installedNow = $true
    }

    [pscustomobject]@{ RemovedVersions = $removedVersions; Installed = $installedNow }
}
