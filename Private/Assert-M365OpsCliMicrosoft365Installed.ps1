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

        LIMITE CHE RESTA COMUNQUE, anche con l'installazione automatica: Windows non rende
        visibile un programma npm appena installato globalmente a un processo GIA' in
        esecuzione (il PATH aggiornato a livello di registro non si propaga a processi gia'
        avviati) - quindi anche dopo un'installazione riuscita QUI, il PROCESSO SERVER
        ATTUALE non vedra' comunque 'm365' finche' non viene riavviato per davvero (chiudere
        tutto e riaprire, non solo "Riavvia server" se anche quello discende dalla stessa
        shell/processo di prima dell'installazione). Questa funzione lo dice chiaramente
        nel messaggio finale invece di lasciare che l'utente scopra lo stesso errore un
        minuto dopo pensando che l'installazione sia fallita.
    #>
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
        $installOutput = & $npmCmd install -g "@pnp/cli-microsoft365" 2>&1
        $installOutput | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "npm install terminato con codice di uscita $LASTEXITCODE."
        }
    }
    catch {
        Write-M365OpsLog "Installazione automatica di CLI Microsoft 365 fallita: $($_.Exception.Message)" -Level Error
        throw "Installazione automatica di CLI Microsoft 365 fallita: $($_.Exception.Message) - prova a eseguire manualmente 'npm install -g @pnp/cli-microsoft365' in un terminale, poi riavvia completamente M365Ops."
    }

    Write-M365OpsLog "CLI Microsoft 365 installato con successo (npm install -g @pnp/cli-microsoft365) - richiesto un riavvio completo per renderlo visibile a questo processo."
    throw "CLI Microsoft 365 installato ora per la prima volta su questo PC (npm install -g @pnp/cli-microsoft365 completato con successo). Prima di poterlo usare serve pero' un riavvio COMPLETO: chiudi ogni finestra/terminale e riapri dal collegamento M365Ops sul Desktop - il solo pulsante 'Riavvia server' non basta se il processo attuale e' partito prima di questa installazione (Windows non rende visibile un programma npm appena installato a un processo gia' in esecuzione). Dopo il riavvio, 'Connetti CLI Microsoft 365' funzionera' direttamente."
}
