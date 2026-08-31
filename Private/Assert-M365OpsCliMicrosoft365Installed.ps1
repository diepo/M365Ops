function Assert-M365OpsCliMicrosoft365Installed {
    <#
    .SYNOPSIS
        Garantisce che il comando 'm365' (pacchetto npm @pnp/cli-microsoft365) sia installato
        GLOBALMENTE su questo PC - richiesto dal server MCP CLI-Microsoft365 (che lo invoca
        internamente ad ogni comando, vedi Connect-M365OpsCliMicrosoft365.ps1), lo installa da
        solo se manca invece di limitarsi a chiedere all'utente di farlo a mano.

        PERCHE' SERVE (26/08/2026, bug reale segnalato dal vivo: l'utente si aspettava che
        l'app installasse questa dipendenza da sola, "come fa per Lokka" - aspettativa
        legittima ma basata su un'analogia imperfetta: Lokka e' completamente autosufficiente
        (npx -y lo scarica ed esegue al volo, nessuna installazione globale necessaria), ma
        @pnp/cli-microsoft365-mcp-server e' solo un wrapper sottile che internamente chiama il
        comando 'm365' come processo ESTERNO gia' installato - npx scarica il WRAPPER, non
        anche la CLI vera e propria che il wrapper si aspetta di trovare gia' pronta). Questa
        funzione chiude quel divario: chiamata PRIMA di avviare il server MCP (stesso
        principio di Assert-M365OpsExoSafeVersion/Assert-M365OpsTeamsSafeVersion, chiamate
        prima di Import-Module), controlla ed eventualmente installa da sola.

        NESSUN RIAVVIO PIU' NECESSARIO dopo l'installazione (corretto il 26/08/2026, durante
        un bug-hunt - limite creduto strutturale, in realta' evitabile): e' vero che Windows
        non propaga da solo un PATH di registro appena aggiornato a un processo GIA' in
        esecuzione, ma QUESTA funzione gira nello STESSO processo server che poi spawna il
        sottoprocesso 'npx' del server MCP CLI-Microsoft365 (vedi Connect-M365OpsMcpServer.ps1,
        chiamata subito dopo questa) - basta ricostruire $env:Path DAL REGISTRO in QUESTO
        processo (stesso trucco gia' usato con successo altrove nel progetto per lo stesso
        identico scenario: Install-M365OpsPrerequisites.ps1/Show-M365OpsPrereqInstaller.ps1
        dopo un'installazione winget/npm) perche' il sottoprocesso spawnato SUBITO DOPO, nello
        stesso processo, erediti il PATH aggiornato - verificato dal vivo che 'm365 status'
        funziona correttamente subito dopo, senza alcun riavvio, nello stesso processo server
        che ha appena eseguito l'installazione.
    #>
    # Bandierina di visibilita' (31/08/2026, richiesta esplicitamente dall'utente dopo aver
    # notato dal vivo, durante un test IA, un'installazione da ~2 minuti scattata in silenzio
    # a meta' di una domanda in chat, senza alcun preavviso): l'auto-installazione qui sotto
    # resta INVARIATA (richiesta esplicitamente dall'utente il 26/08/2026, "installala al
    # primo avvio esattamente come Lokka") - questa bandierina non la impedisce, la rende solo
    # VISIBILE quando scatta durante una conversazione reale invece che solo nei log del
    # server. Azzerata ad ogni chiamata: riflette solo l'ultima chiamata, non uno stato
    # persistente. Letta da Invoke-M365OpsMcpServerTool.ps1, che la usa per anteporre una nota
    # al risultato del primo tool cli_m365_* di una conversazione, cosi' l'utente vede scritto
    # nella risposta finale PERCHE' quel turno e' stato piu' lento del solito, invece di
    # scoprirlo solo controllando i log.
    $script:M365OpsCliJustInstalled = $false

    $m365Cmd = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue).Source
    if (-not $m365Cmd) { $m365Cmd = (Get-Command 'm365' -ErrorAction SilentlyContinue).Source }
    if ($m365Cmd) { return }

    Write-Host "CLI Microsoft 365 (comando 'm365') non trovato su questo PC - lo installo ora (npm install -g @pnp/cli-microsoft365)..." -ForegroundColor Yellow
    Write-M365OpsLog "CLI Microsoft 365 non installato - avvio installazione automatica (npm install -g @pnp/cli-microsoft365)."

    $npmCmd = (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue).Source
    if (-not $npmCmd) { $npmCmd = (Get-Command 'npm' -ErrorAction SilentlyContinue).Source }
    if (-not $npmCmd) {
        throw "CLI Microsoft 365 non e' installato e non posso installarlo da solo: comando 'npm' non trovato su questo PC - serve prima Node.js (stesso prerequisito gia' richiesto per Lokka). Installa Node.js da nodejs.org, poi riprova."
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
        # la pipeline (qui, il primo '| ForEach-Object { Write-Host $_ }'), MOLTO prima di
        # arrivare al controllo esplicito su $LASTEXITCODE sotto - installazione riuscita
        # (verificato dal vivo, exit 0, pacchetto installato per davvero) ma segnalata come
        # fallita, con l'avviso npm scambiato per l'errore vero. Verificato dal vivo che PowerShell
        # 7 (il runtime reale della GUI, vedi altri gap gia' noti "solo 5.1" in
        # Debug-Marathon-State.md) NON soffre di questo problema - ma resta un bug reale per
        # chiunque importi il modulo a mano su Windows PowerShell 5.1 (l'host predefinito su
        # molte installazioni Windows per un .ps1 aperto a doppio clic), quindi corretto qui
        # invece di lasciarlo solo come nota. Fix: EAP locale 'Continue' solo per la durata di
        # questa chiamata (ripristinato subito dopo, in un blocco finally) - le righe di stderr
        # restano visibili (ancora scritte da Write-Host) ma non promosse a eccezione; il
        # controllo esplicito su $LASTEXITCODE sotto resta l'UNICA fonte di verita' su successo/
        # fallimento reale, esattamente come progettato.
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
        Write-M365OpsLog "Installazione automatica di CLI Microsoft 365 fallita: $($_.Exception.Message)" -Level Error
        throw "Installazione automatica di CLI Microsoft 365 fallita: $($_.Exception.Message) - prova a eseguire manualmente 'npm install -g @pnp/cli-microsoft365' in un terminale, poi riavvia completamente M365Ops."
    }

    # Ricostruisce $env:Path di QUESTO processo dal registro (Machine + User) - senza,
    # 'npx' (spawnato subito dopo da Connect-M365OpsMcpServer.ps1 nello stesso processo)
    # erediterebbe ancora il PATH vecchio e non troverebbe 'm365' appena installato, esatto
    # lo stesso motivo per cui questo stesso trucco e' gia' usato altrove nel progetto dopo
    # un'installazione winget/npm (Install-M365OpsPrerequisites.ps1/
    # Show-M365OpsPrereqInstaller.ps1). Verificato dal vivo il 26/08/2026 che basta, senza
    # bisogno di alcun riavvio del server.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $nowPresent = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'm365' -ErrorAction SilentlyContinue)
    if (-not $nowPresent) {
        # Rete di sicurezza per il caso raro in cui la ricostruzione del PATH non basti
        # (es. npm ha installato altrove per una configurazione non standard) - stesso
        # messaggio azionabile di prima invece di proseguire alla cieca.
        Write-M365OpsLog "CLI Microsoft 365 installato ma 'm365' resta non risolvibile anche dopo la ricostruzione del PATH - richiesto un riavvio completo." -Level Error
        throw "CLI Microsoft 365 installato ora per la prima volta su questo PC (npm install -g @pnp/cli-microsoft365 completato con successo), ma il comando 'm365' non risulta ancora risolvibile nemmeno dopo aver ricostruito il PATH di questo processo - possibile configurazione npm non standard. Chiudi ogni finestra/terminale e riapri dal collegamento M365Ops sul Desktop, poi riprova."
    }
    Write-M365OpsLog "CLI Microsoft 365 installato con successo (npm install -g @pnp/cli-microsoft365) - PATH ricostruito, subito utilizzabile senza riavvio."
    $script:M365OpsCliJustInstalled = $true
}
