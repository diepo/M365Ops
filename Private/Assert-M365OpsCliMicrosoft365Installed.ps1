function Assert-M365OpsCliMicrosoft365Installed {
    <#
    .SYNOPSIS
        Garantisce che il comando 'm365' (pacchetto npm @pnp/cli-microsoft365) sia installato
        GLOBALMENTE su questo PC E aggiornato all'ultima versione pubblicata - richiesto dal
        server MCP CLI-Microsoft365 (che lo invoca internamente ad ogni comando, vedi
        Connect-M365OpsCliMicrosoft365.ps1), lo installa/aggiorna da solo invece di limitarsi a
        chiedere all'utente di farlo a mano.

        PERCHE' SERVE L'INSTALLAZIONE (26/08/2026, bug reale segnalato dal vivo: l'utente si
        aspettava che l'app installasse questa dipendenza da sola, "come fa per Lokka" -
        aspettativa legittima ma basata su un'analogia imperfetta: Lokka e' completamente
        autosufficiente (npx -y lo scarica ed esegue al volo, nessuna installazione globale
        necessaria), ma @pnp/cli-microsoft365-mcp-server e' solo un wrapper sottile che
        internamente chiama il comando 'm365' come processo ESTERNO gia' installato - npx
        scarica il WRAPPER, non anche la CLI vera e propria che il wrapper si aspetta di
        trovare gia' pronta). Questa funzione chiude quel divario: chiamata PRIMA di avviare il
        server MCP (stesso principio di Assert-M365OpsExoSafeVersion/Assert-M365OpsTeamsSafeVersion,
        chiamate prima di Import-Module), controlla ed eventualmente installa da sola.

        PERCHE' SERVE ANCHE L'AGGIORNAMENTO (16/09/2026, richiesto esplicitamente dall'utente,
        subito dopo aver notato che CLI Microsoft 365 v11 ha rinominato diversi comandi/opzioni:
        "la nostra app e' pronta a verificare le nuove versioni del cli e aggiornarsi se
        serve?"): la risposta, verificata leggendo il codice invece di supporre, era NO -
        questa funzione installava una volta sola se mancante e non controllava mai piu' dopo,
        quindi chi l'aveva installata mesi fa restava su quella versione per sempre. Scelta
        dell'utente tra "controlla e avvisa soltanto" e "aggiorna da solo in automatico" (stessa
        logica gia' in uso per la prima installazione): aggiorna da solo. Il controllo e'
        limitato a una volta al giorno (Test-M365OpsCliMicrosoft365UpdateCheckDue.ps1) - una
        vera chiamata di rete (npm view) ad OGNI connessione avrebbe rallentato inutilmente
        ogni singolo uso, non solo il primo della giornata. Nessun rischio di rottura per le
        rinomine di comandi/opzioni della CLI stessa (es. v11.0): questo modulo non ha mai un
        comando CLI365 scritto a mano nel codice, la sintassi la costruisce sempre l'IA al volo
        interrogando m365GetCommandDocs/m365SearchCommands (il server MCP stesso, che riflette
        sempre la versione REALMENTE installata) - vedi Invoke-M365OpsAgentTools.ps1.

        NESSUN RIAVVIO NECESSARIO ne' dopo l'installazione ne' dopo un aggiornamento (corretto
        il 26/08/2026, durante un bug-hunt - limite creduto strutturale, in realta' evitabile):
        e' vero che Windows non propaga da solo un PATH di registro appena aggiornato a un
        processo GIA' in esecuzione, ma QUESTA funzione gira nello STESSO processo server che
        poi spawna il sottoprocesso 'npx' del server MCP CLI-Microsoft365 (vedi
        Connect-M365OpsMcpServer.ps1, chiamata subito dopo questa) - basta ricostruire
        $env:Path DAL REGISTRO in QUESTO processo (vedi
        Invoke-M365OpsCliMicrosoft365NpmInstall.ps1) perche' il sottoprocesso spawnato SUBITO
        DOPO, nello stesso processo, erediti il PATH aggiornato.
    #>
    # Bandierine di visibilita' (31/08/2026 per l'installazione, estesa il 16/09/2026
    # all'aggiornamento, stesso principio): l'auto-installazione/auto-aggiornamento restano
    # INVARIATI (comportamento gia' richiesto esplicitamente dall'utente in entrambi i casi) -
    # queste bandierine non li impediscono, li rendono solo VISIBILI quando scattano durante
    # una conversazione reale invece che solo nei log del server. Azzerate ad ogni chiamata:
    # riflettono solo l'ultima chiamata, non uno stato persistente. Lette da
    # Invoke-M365OpsMcpServerTool.ps1, che le usa per anteporre una nota al risultato del primo
    # tool cli_m365_* di una conversazione.
    $script:M365OpsCliJustInstalled = $false
    $script:M365OpsCliJustUpdated = $null

    $m365Cmd = (Get-Command 'm365.cmd' -ErrorAction SilentlyContinue).Source
    if (-not $m365Cmd) { $m365Cmd = (Get-Command 'm365' -ErrorAction SilentlyContinue).Source }

    if (-not $m365Cmd) {
        Write-Host "CLI Microsoft 365 (comando 'm365') non trovato su questo PC - lo installo ora (npm install -g @pnp/cli-microsoft365)..." -ForegroundColor Yellow
        Write-M365OpsLog "CLI Microsoft 365 non installato - avvio installazione automatica (npm install -g @pnp/cli-microsoft365)."
        try {
            Invoke-M365OpsCliMicrosoft365NpmInstall
        } catch {
            Write-M365OpsLog "Installazione automatica di CLI Microsoft 365 fallita: $($_.Exception.Message)" -Level Error
            throw
        }
        Write-M365OpsLog "CLI Microsoft 365 installato con successo (npm install -g @pnp/cli-microsoft365) - PATH ricostruito, subito utilizzabile senza riavvio."
        $script:M365OpsCliJustInstalled = $true
        # Appena installata = certamente l'ultima versione pubblicata in questo momento, nessun
        # motivo di ricontrollare oggi stesso.
        Set-M365OpsCliMicrosoft365UpdateCheckTimestamp
        return
    }

    # Gia' installata - controlla se e' ora di verificare un aggiornamento (throttle 1/giorno,
    # vedi .SYNOPSIS). Un controllo fallito (es. rete assente/registro npm irraggiungibile) non
    # deve MAI bloccare l'uso della CLI gia' installata e funzionante - solo loggato, mai
    # sollevato come eccezione da questa funzione.
    if (-not (Test-M365OpsCliMicrosoft365UpdateCheckDue)) { return }

    try {
        $versions = Get-M365OpsCliMicrosoft365Versions
        Set-M365OpsCliMicrosoft365UpdateCheckTimestamp
        if ($versions.Installed -and $versions.Latest -and $versions.Installed -ne $versions.Latest) {
            Write-Host "CLI Microsoft 365: aggiornamento disponibile ($($versions.Installed) -> $($versions.Latest)) - aggiorno ora automaticamente (npm install -g @pnp/cli-microsoft365)..." -ForegroundColor Yellow
            Write-M365OpsLog "CLI Microsoft 365: aggiornamento $($versions.Installed) -> $($versions.Latest) trovato, avvio aggiornamento automatico."
            Invoke-M365OpsCliMicrosoft365NpmInstall
            Write-M365OpsLog "CLI Microsoft 365 aggiornato con successo ($($versions.Installed) -> $($versions.Latest)) - PATH ricostruito, subito utilizzabile senza riavvio."
            $script:M365OpsCliJustUpdated = [pscustomobject]@{ From = $versions.Installed; To = $versions.Latest }
        }
    } catch {
        # Un aggiornamento fallito (a differenza di un'installazione fallita) non deve MAI
        # bloccare l'uso della versione gia' installata e funzionante - solo loggato come
        # avviso, la CLI resta pienamente utilizzabile alla versione corrente.
        Write-M365OpsLog "Controllo/aggiornamento automatico CLI Microsoft 365 fallito (non bloccante, la versione gia' installata resta utilizzabile): $($_.Exception.Message)" -Level Warn
    }
}
