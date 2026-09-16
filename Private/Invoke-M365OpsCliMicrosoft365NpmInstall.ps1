function Invoke-M365OpsCliMicrosoft365NpmInstall {
    <#
    .SYNOPSIS
        Esegue davvero 'npm install -g @pnp/cli-microsoft365' e ricostruisce il PATH di questo
        processo - estratto da Assert-M365OpsCliMicrosoft365Installed.ps1 (16/09/2026) perche'
        la STESSA identica azione (npm install -g, nessun pin di versione = prende sempre
        l'ultima pubblicata) serve ora in DUE casi distinti: installazione la prima volta
        (nessuna versione presente) e aggiornamento (una versione piu' vecchia gia' presente,
        vedi Assert-M365OpsCliMicrosoft365Installed.ps1 per il controllo di versione che decide
        quando chiamare questa funzione). Nessuna logica cambiata rispetto a prima, solo resa
        riusabile invece di duplicata.
    .NOTES
        Lancia un'eccezione con un messaggio azionabile su qualunque fallimento reale - i
        chiamanti decidono come/se mostrarlo, questa funzione non ingoia mai un errore vero.
    #>
    $npmCmd = (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue).Source
    if (-not $npmCmd) { $npmCmd = (Get-Command 'npm' -ErrorAction SilentlyContinue).Source }
    if (-not $npmCmd) {
        throw "CLI Microsoft 365 non e' installata/aggiornabile: comando 'npm' non trovato su questo PC - serve prima Node.js (stesso prerequisito gia' richiesto per Lokka). Installa Node.js da nodejs.org, poi riprova."
    }

    try {
        # -NoNewWindow + Wait: installazione sincrona, l'utente vede il progresso reale nella
        # console del server (stesso posto dove compaiono gia' i log di avvio) invece di un
        # tentativo silenzioso che sembra bloccato senza spiegazione.
        #
        # BUG REALE trovato dal vivo il 23/08/2026 (maratona "CLI365 mai toccate con dati
        # reali"): '2>&1' su un comando nativo (npm) impacchetta ogni riga di STDERR come
        # ErrorRecord - npm scrive normalissimi avvisi non fatali su stderr (es. "npm warn
        # allow-scripts ..." per protobufjs, presente su OGNI installazione recente di questo
        # pacchetto, nessun problema reale). Sotto $ErrorActionPreference = 'Stop' - impostato
        # deliberatamente a livello di modulo (vedi M365Ops.psm1) - Windows PowerShell 5.1
        # promuove il primo di quegli ErrorRecord a eccezione terminante NON APPENA attraversa
        # la pipeline, MOLTO prima di arrivare al controllo esplicito su $LASTEXITCODE sotto -
        # installazione riuscita ma segnalata come fallita, con l'avviso npm scambiato per
        # l'errore vero. PowerShell 7 (il runtime reale della GUI) non soffre di questo
        # problema, ma resta un bug reale per chiunque importi il modulo a mano su Windows
        # PowerShell 5.1 - corretto qui con un EAP locale 'Continue' solo per la durata di
        # questa chiamata (ripristinato subito dopo).
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $installOutput = & $npmCmd install -g "@pnp/cli-microsoft365" 2>&1
        }
        finally {
            $ErrorActionPreference = $previousEap
        }
        $installOutput | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "npm install terminato con codice di uscita $LASTEXITCODE."
        }
    }
    catch {
        throw "npm install -g @pnp/cli-microsoft365 fallito: $($_.Exception.Message) - prova a eseguirlo manualmente in un terminale, poi riavvia completamente M365Ops."
    }

    # Ricostruisce $env:Path di QUESTO processo dal registro (Machine + User) - senza, 'npx'
    # (spawnato subito dopo da Connect-M365OpsMcpServer.ps1 nello stesso processo) erediterebbe
    # ancora il PATH vecchio e non troverebbe 'm365' appena installato/aggiornato - stesso
    # trucco gia' usato altrove nel progetto dopo un'installazione winget/npm.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $nowPresent = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'm365' -ErrorAction SilentlyContinue)
    if (-not $nowPresent) {
        throw "npm install -g @pnp/cli-microsoft365 completato con successo, ma il comando 'm365' non risulta ancora risolvibile nemmeno dopo aver ricostruito il PATH di questo processo - possibile configurazione npm non standard. Chiudi ogni finestra/terminale e riapri dal collegamento M365Ops sul Desktop, poi riprova."
    }
}
