function Invoke-M365OpsWithExoRepairRetry {
    <#
    .SYNOPSIS
        Esegue $Action (una connessione reale Connect-ExchangeOnline/Connect-IPPSSession) e, se
        fallisce con un errore tipico di installazione ExchangeOnlineManagement danneggiata E
        MicrosoftTeams non e' caricato in questa sessione (quindi non puo' essere il conflitto
        noto di sezione 6.6), ripara l'installazione SU DISCO (cancella la cartella della
        versione fissata e la reinstalla da zero) e lancia un errore chiaro che richiede un
        riavvio - NON riprova $Action nello stesso processo (vedi sotto il perche').

        Bug reale segnalato dal vivo il 25/08/2026: dopo un riavvio pulito del server, SENZA MAI
        toccare Teams in quella sessione, la connessione a Exchange falliva con "The given
        assembly name was invalid." Riprodotto qui cancellando deliberatamente
        Microsoft.Identity.Client.dll dalla cartella di installazione: <code>Import-Module</code>
        riesce comunque (non carica ogni DLL referenziata, solo l'assembly principale), l'errore
        compare SOLO quando <code>Connect-ExchangeOnline</code> tenta davvero l'autenticazione e
        tocca quella dipendenza caricata pigramente.

        PERCHE' NON SI RIPROVA NELLO STESSO PROCESSO, e perche' questa e' solo una rete di
        sicurezza secondaria (scoperto con due test dal vivo il 25/08/2026): una volta che
        <code>Import-Module</code> ha caricato l'assembly principale nel processo, Windows blocca
        quel file (e in pratica l'intera cartella di installazione) a livello di file system -
        nemmeno un <code>Remove-Item</code> qui dentro riesce piu' a toccarlo, verificato dal vivo
        (il primo tentativo di riparazione-in-process falliva silenziosamente, dando la falsa
        impressione di aver riparato quando l'errore restava identico). Il vero punto di
        riparazione affidabile e' quindi <code>Assert-M365OpsExoSafeVersion</code> (Private, che
        ora verifica l'integrita' dei file, non solo la presenza del manifest) - chiamata SEMPRE
        PRIMA di qualunque <code>Import-Module</code> nei chiamanti, quindi prima che Windows possa
        bloccare i file. Questa funzione resta solo come rete di sicurezza per il caso raro in cui
        il danno avvenga DOPO che il modulo e' gia' stato importato in questa sessione (es. un
        antivirus o un processo esterno tocca i file a meta' sessione) - li' una riparazione vera
        non e' possibile, il messaggio finale dice sempre di riavviare.
    #>
    param([Parameter(Mandatory)] [scriptblock]$Action)

    try {
        # Out-Null aggiunto il 26/08/2026: nessuno dei chiamanti cattura ne' usa il valore
        # restituito da $Action (sempre una chiamata bare a Connect-ExchangeOnline/
        # Connect-IPPSSession) - senza sopprimerlo qui, un'eventuale emissione non
        # silenziosa di quei cmdlet finirebbe sull'output pipeline di QUESTA funzione e, a
        # cascata, su quello dei chiamanti (esattamente il bug di leak trovato dal vivo lo
        # stesso giorno in Complete-M365OpsExchangeDelegatedLogin.ps1 con
        # Assert-M365OpsExoSafeVersion, stessa causa - un valore di ritorno non voluto non
        # soppresso). Soppresso qui una volta sola invece che in ognuno dei quattro punti
        # di chiamata.
        & $Action | Out-Null
    }
    catch {
        $msg = $_.Exception.Message
        $looksLikeBrokenInstall = ($msg -match 'Could not load file or assembly' -or $msg -match 'The given assembly name was invalid')
        if (-not $looksLikeBrokenInstall -or $script:M365OpsTeamsModuleImported) {
            throw
        }

        # $safeVersion RIMOSSO (26/08/2026): era rimasta una '3.9.0' hardcoded, gia' allora
        # disallineata dal pin reale in vigore (3.4.0) - da quando Assert-M365OpsExoSafeVersion
        # non pinna piu' una versione specifica (installa/tiene sempre l'ultima disponibile,
        # vedi quel file per il perche'), qualunque versione fissata qui sarebbe comunque
        # sbagliata per definizione. Ripara rimuovendo OGNI copia installata (non solo una
        # versione specifica) e reinstallando l'ultima disponibile, stessa filosofia.
        Write-M365OpsLog "Connessione Exchange fallita con un errore tipico di installazione danneggiata ($msg), e MicrosoftTeams non e' caricato in questa sessione (quindi non puo' essere il conflitto noto) - riparo l'installazione su disco per il prossimo tentativo (un retry immediato nello stesso processo non puo' funzionare, .NET non scarica mai un assembly gia' caricato)."
        Remove-Module -Name ExchangeOnlineManagement -Force -ErrorAction SilentlyContinue
        $copies = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement)
        $removalFailed = $false
        foreach ($copy in $copies) {
            try { Remove-Item -Path $copy.ModuleBase -Recurse -Force -ErrorAction Stop }
            catch {
                $removalFailed = $true
                Write-M365OpsLog "Rimozione della copia danneggiata in '$($copy.ModuleBase)' fallita: $($_.Exception.Message)"
            }
        }

        $repairOk = $true
        if (-not $removalFailed) {
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
                Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                Write-M365OpsLog "ExchangeOnlineManagement reinstallato sul disco (ultima versione disponibile) - servira' un riavvio del server per usarlo in questo processo."
            }
            catch {
                $repairOk = $false
                Write-M365OpsLog "Reinstallazione di ExchangeOnlineManagement fallita: $($_.Exception.Message)"
            }
        }
        else {
            $repairOk = $false
        }

        if ($repairOk) {
            throw "Connessione a Exchange Online fallita per un'installazione locale del modulo ExchangeOnlineManagement danneggiata (errore .NET: $msg) - probabilmente un file mancante o incompleto, non il conflitto con Teams (Teams non e' caricato in questa sessione). Il modulo e' stato reinstallato pulito sul disco, ma .NET non puo' scaricare un assembly gia' caricato in QUESTO processo: riavvia il server (pulsante Manutenzione, o 'M365Ops - Termina e riavvia' sul Desktop se non risponde) e riprova - la connessione dovrebbe funzionare nel nuovo processo."
        }
        else {
            $manualCmd1 = "Get-Module -ListAvailable ExchangeOnlineManagement | ForEach-Object { Remove-Item `$_.ModuleBase -Recurse -Force }"
            $manualCmd2 = "Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck"
            throw "Connessione a Exchange Online fallita per un'installazione locale del modulo ExchangeOnlineManagement probabilmente danneggiata (errore .NET: $msg), e il tentativo automatico di ripararla e' anch'esso fallito. Prova a farlo manualmente: chiudi il server, apri PowerShell 7 ed esegui questi due comandi in sequenza - '$manualCmd1' poi '$manualCmd2' - infine riavvia il server."
        }
    }
}
