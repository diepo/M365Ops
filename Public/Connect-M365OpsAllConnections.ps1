function Connect-M365OpsAllConnections {
    <#
    .SYNOPSIS
        Riconnette tutto cio' che PUO' essere riconnesso in silenzio per il TENANT ATTIVO, senza
        mai avviare un login interattivo bloccante da solo - pensato per il pulsante "Connetti
        tutto" (mostrato al posto di "Disconnetti tutto" quando nessuna connessione risulta
        attiva) e in particolare per rinforzare la connessione applicativa subito DOPO aver
        concesso un nuovo permesso Graph all'App Registration (Grant admin consent): un token o
        una sessione gia' ottenuti riflettono i permessi presenti AL MOMENTO in cui sono stati
        rilasciati, non quelli aggiunti dopo - vanno rifatti da zero per vederli, e questo e'
        richiesto esplicitamente dall'utente (27/08/2026).
    .NOTES
        SOLO su AppOnly le aree Exchange/Teams/SharePoint/Compliance/Intune e il token Graph
        diretto fanno un lavoro reale: sono tutte certificato/client-secret based, quindi non
        richiedono mai interazione per definizione - stesso principio gia' verificato per
        ognuna di queste funzioni singolarmente. Su Delegated queste NON vengono mai FORZATE a
        una nuova connessione (dipendono tutte dallo stesso token utente radice - device code -
        e chiamarle con -Force senza -AllowInteractive fallirebbe sempre, anche con una sessione
        gia' valida, dato che -Force scarta il controllo "gia' connesso" a monte) - vengono
        invece VERIFICATE cosi' come sono (16/09/2026, bug reale segnalato dal vivo dall'utente:
        "ok che non puo' connettere cio' che richiede l'app, ma il resto??" - la versione
        precedente saltava TUTTE le 5 aree incondizionatamente, anche quando una o piu' erano
        gia' connesse da un login interattivo fatto in precedenza nella stessa sessione del
        server, es. tramite "Accedi con il mio utente"/i pulsanti dedicati Teams/SharePoint/
        Purview/Intune - un risultato onesto ("gia' connesso", verificato sul vero stato del
        processo) e' sempre meglio di un messaggio generico che ignora lo stato reale). Solo le
        aree NON ancora connesse restano segnalate come bisognose di un nuovo login interattivo
        - mai tentate automaticamente da qui (bloccherebbero il server a thread singolo per
        tutti, vedi Connect-M365OpsExchange.ps1), l'utente va sempre verso l'azione dedicata
        giusta per ciascuna.

        I SERVER MCP invece vengono tentati SEMPRE, anche su Delegato (corretto il 31/08/2026,
        bug reale trovato dalla maratona di stress-test: prima venivano saltati del tutto su
        Delegato) - CLI Microsoft 365 in particolare si autentica con uno stato SEPARATO su
        disco (`m365 login`/`connection use`, vedi Connect-M365OpsCliMicrosoft365.ps1),
        INDIPENDENTE dal token utente root di questo modulo: se una connessione CLI365 per
        questo profilo esiste gia' (es. il suo sottoprocesso MCP e' stato ucciso da
        "Disconnetti tutto" ma il login CLI resta valido su disco, quella funzione NON lo
        revoca mai), la riconnessione riesce in silenzio SENZA bisogno di alcun login
        interattivo - saltarla incondizionatamente su Delegato negava questo caso reale. Se
        invece nessuna connessione CLI365 salvata esiste, il tentativo fallisce con un
        messaggio chiaro (gestito dallo stesso try/catch per passo di sotto), mai un blocco.

        Ogni passo e' tentato indipendentemente (try/catch per passo, mai un fallimento che
        blocca i fratelli) - stesso principio gia' applicato sistematicamente altrove nel
        progetto contro la classe di bug "un passo fallito blocca i passi fratelli
        indipendenti" (v0.10.17).
    .PARAMETER OnProgress
        Scriptblock opzionale, invocato con una singola stringa descrittiva PRIMA di iniziare
        ciascun passo (16/09/2026, richiesto esplicitamente dall'utente: "quando clicco connetti
        tutto mi scrive riconnessione in corso ma non mi dice cosa sta facendo... vorrei non
        lasciare sospeso l'utente in questa fase" - prima di questo l'unico segnale durante
        un'operazione che puo' durare 1-3 minuti era un contatore di secondi lato client, nessuna
        indicazione di COSA stesse effettivamente succedendo in quel momento). Pensato per
        Gui\Server.ps1 (POST /api/reconnect-all), che lo usa per scrivere un file di stage
        pollato dalla GUI (stesso principio gia' in uso per l'avvio dell'app, vedi
        Write-M365OpsStartupStage/Config\startup-stage.txt) - ma resta un parametro generico, non
        legato alla GUI: chiamato senza -OnProgress il comportamento e' identico a prima.
    #>
    param([scriptblock]$OnProgress)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo." }
    $ctx = $script:M365OpsContext
    $isDelegated = $ctx.AuthMode -eq 'Delegated'

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $isDelegated) {
        $steps = @(
            @{ Name = 'Token Microsoft Graph (app-only)'; Action = { Get-M365OpsToken | Out-Null } }
            @{ Name = 'Exchange Online';                  Action = { Connect-M365OpsExchange -Force } }
            @{ Name = 'Microsoft Teams';                  Action = { Connect-M365OpsTeams -Force } }
            @{ Name = 'SharePoint';                        Action = { Connect-M365OpsSharePoint -Force } }
            @{ Name = 'Security & Compliance (Purview)';  Action = { Connect-M365OpsCompliance -Force } }
            @{ Name = 'Intune';                            Action = { Connect-M365OpsIntune -Force } }
        )
        foreach ($step in $steps) {
            if ($OnProgress) { try { & $OnProgress "Connessione a $($step.Name)..." } catch {} }
            try {
                & $step.Action
                $results.Add([pscustomobject]@{ Name = $step.Name; Ok = $true; Message = $null })
            } catch {
                $results.Add([pscustomobject]@{ Name = $step.Name; Ok = $false; Message = $_.Exception.Message })
            }
        }
    } else {
        # Ognuna delle 5 aree viene VERIFICATA sul suo vero stato attuale (stessi campi usati da
        # Get-M365OpsActiveTenantInfo per i pallini di stato in GUI), non piu' saltata a
        # prescindere - vedi .NOTES per il bug reale che questo corregge. Nessuna di queste
        # chiamate blocca mai il server: e' una semplice lettura di un flag booleano gia' in
        # memoria, mai una nuova connessione.
        $delegatedAreas = @(
            @{ Name = 'Exchange Online';                 Connected = [bool]$script:M365OpsExchangeConnected;      Hint = "Vai al tab Tenant, sezione 'Stato connessioni', e usa 'Accedi con il mio utente' (Exchange Online)." }
            @{ Name = 'Microsoft Teams';                 Connected = [bool]$script:M365OpsTeamsConnected;         Hint = "Vai al tab Tenant, sezione 'Stato connessioni', e usa il pulsante dedicato 'Connetti Microsoft Teams'." }
            @{ Name = 'SharePoint';                       Connected = [bool]$script:M365OpsSharePointConnectedUrl; Hint = "Vai al tab Tenant, sezione 'Stato connessioni', e usa il pulsante dedicato 'Connetti SharePoint'." }
            @{ Name = 'Security & Compliance (Purview)'; Connected = [bool]$script:M365OpsComplianceConnected;    Hint = "Vai al tab Tenant, sezione 'Stato connessioni', e usa il pulsante dedicato 'Connetti Purview'." }
            @{ Name = 'Intune';                           Connected = [bool]$script:M365OpsIntuneConnected;        Hint = "Vai al tab Tenant, sezione 'Stato connessioni', e usa il pulsante dedicato 'Connetti Intune'." }
        )
        $missingAreas = [System.Collections.Generic.List[string]]::new()
        foreach ($area in $delegatedAreas) {
            if ($OnProgress) { try { & $OnProgress "Verifica $($area.Name)..." } catch {} }
            if ($area.Connected) {
                $results.Add([pscustomobject]@{ Name = $area.Name; Ok = $true; Message = $null })
            } else {
                $missingAreas.Add($area.Name)
                $results.Add([pscustomobject]@{ Name = $area.Name; Ok = $false; Message = "Richiede un nuovo login interattivo (mai avviato automaticamente da qui, bloccherebbe il server per tutti). $($area.Hint)" })
            }
        }
        if ($missingAreas.Count -gt 0 -and $OnProgress) {
            try { & $OnProgress "Aree che richiedono un nuovo login interattivo: $($missingAreas -join ', '). Provo comunque i server MCP..." } catch {}
        }
    }

    foreach ($server in @(Get-M365OpsMcpServers)) {
        if ($OnProgress) { try { & $OnProgress "Connessione al server MCP '$($server.Name)'..." } catch {} }
        try {
            Connect-M365OpsMcpServer -Name $server.Name -Force | Out-Null
            $results.Add([pscustomobject]@{ Name = "MCP: $($server.Name)"; Ok = $true; Message = $null })
        } catch {
            $results.Add([pscustomobject]@{ Name = "MCP: $($server.Name)"; Ok = $false; Message = $_.Exception.Message })
        }
    }

    # Messaggio finale condizionato allo stato VERO appena verificato sopra (16/09/2026, stesso
    # fix): prima era un testo fisso, sempre lo stesso, anche quando una o piu' aree erano gia'
    # connesse - ora avvisa solo se resta davvero qualcosa da fare a mano, altrimenti tace (i
    # risultati per-area, tutti OK, parlano gia' da soli).
    $delegatedMissingCount = if ($isDelegated) { @($results | Where-Object { -not $_.Ok -and $_.Name -notlike 'MCP:*' }).Count } else { 0 }
    [pscustomobject]@{
        AuthMode = $ctx.AuthMode
        Results  = $results
        Message  = if ($isDelegated -and $delegatedMissingCount -gt 0) { "Tenant Delegato: alcune aree richiedono un nuovo login interattivo (dettagli per-area sopra) - mai avviato automaticamente da qui, bloccherebbe il server per tutti dato che gira a thread singolo. Usa l'azione dedicata giusta per ciascuna area mancante." } elseif ($isDelegated) { "Tenant Delegato: tutte le aree gia' verificabili risultano gia' connesse." } else { $null }
    }
}
