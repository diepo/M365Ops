function Complete-M365OpsExchangeDelegatedLogin {
    <#
    .SYNOPSIS
        UN singolo tentativo di verifica che l'utente abbia completato il login Exchange
        avviato con Start-M365OpsExchangeDelegatedLogin - pensata per essere chiamata
        ripetutamente (polling) dalla GUI. Finche' il login non e' completato, ogni chiamata
        e' rapida (una sola richiesta HTTP di verifica, Status=Pending). Solo quando il
        token e' pronto viene chiamato Connect-ExchangeOnline -AccessToken (rapido, nessuna
        interazione umana necessaria a quel punto) per stabilire la sessione PowerShell vera
        e propria - questo e' l'unico momento in cui questa funzione puo' impiegare qualche
        secondo in piu' del solito, mai piu' di questo.
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $pending = $script:M365OpsPendingExoDeviceCode[$tenantName]
    if (-not $pending) {
        # Bug reale segnalato dal vivo il 21/08/2026, test pulito (nessun riavvio server nel
        # mezzo): l'utente incolla il codice, la GUI resta "in attesa" e poi mostra proprio
        # questo errore - ma cambiando tab la connessione risultava GIA' attiva. Causa: il
        # server e' single-thread/sincrono (Gui\Server.ps1, $listener.GetContext() in un unico
        # ciclo) - se UNA chiamata di poll impiega piu' del solito (qui dentro si chiama anche
        # Connect-ExchangeOnline, l'unico punto per cui questa funzione puo' richiedere qualche
        # secondo in piu', vedi .SYNOPSIS) e il fetch lato browser va in timeout/si interrompe
        # (rete/proxy/antivirus locali, non sotto il nostro controllo) PRIMA che la risposta
        # arrivi, il browser pianifica un poll successivo - che pero' il server processa SOLO
        # dopo aver finito il primo, ormai riuscito e con la voce pending gia' rimossa. Il poll
        # "in piu'" trovava quindi nessuna voce pending e restituiva questo errore, anche se la
        # connessione era gia' a buon fine. Invece di assumere "nessun login mai iniziato",
        # controlliamo lo stato REALE prima di dichiarare errore - stesso principio gia' usato
        # per Intune in Test-M365OpsIntuneAuthValid: mai fidarsi ciecamente dell'assenza di un
        # flag interno quando lo stato vero e' verificabile.
        if ($script:M365OpsExchangeConnected) {
            return [pscustomobject]@{ Status = 'Completed'; Message = 'Gia connesso (un tentativo di verifica precedente era andato a buon fine).' }
        }
        return [pscustomobject]@{ Status = 'Error'; Message = "Nessun login Exchange in corso per '$tenantName' - avvialo prima con Start-M365OpsExchangeDelegatedLogin." }
    }
    if ((Get-Date) -gt $pending.ExpiresAt) {
        $script:M365OpsPendingExoDeviceCode.Remove($tenantName)
        return [pscustomobject]@{ Status = 'Error'; Message = "Codice scaduto - riavvia il login." }
    }

    $result = Receive-M365OpsDeviceCodeToken -TenantId $script:M365OpsContext.TenantId -DeviceCode $pending.DeviceCode -ClientId $script:M365OpsExoDeviceCodeClientId

    if ($result.Status -eq 'Completed') {
        $script:M365OpsPendingExoDeviceCode.Remove($tenantName)
        # BUG DI SICUREZZA reale trovato dal vivo il 26/08/2026 (stesso giro del bug sopra):
        # $result qui contiene AccessToken/RefreshToken VERI (Receive-M365OpsDeviceCodeToken li
        # popola per poterli passare a Connect-ExchangeOnline -AccessToken subito sotto) - la
        # vecchia versione di questa funzione restituiva $result COSI' COM'E' come output,
        # che Gui\Server.ps1 serializza direttamente in JSON e spedisce al browser: il
        # refresh token (che permette di ottenere nuovi access token senza rifare login,
        # quindi il "materiale" piu' sensibile di tutti) finiva quindi leggibile nella
        # risposta HTTP e nella console del browser, senza che servisse mai fuori da questo
        # processo server. Da qui in poi la funzione costruisce sempre esplicitamente un
        # oggetto Status/Message pulito, mai piu' $result grezzo.
        # Conflitto noto MicrosoftTeams/ExchangeOnlineManagement, riprodotto dal vivo il
        # 22/08/2026 esattamente su QUESTA funzione (il messaggio d'errore dell'utente -
        # "Could not load file or assembly ...Microsoft.IdentityModel.Abstractions...
        # manifest definition does not match" - corrisponde esattamente). Nessuna guardia
        # preventiva (vedi Connect-M365OpsExchange.ps1 per la storia completa e il perche') - si
        # prova sempre, il catch sotto riveste l'eventuale conflitto con un messaggio chiaro solo
        # se scatta davvero, invece di bloccare a priori un tentativo che potrebbe funzionare.
        try {
            # Fallback di auto-installazione (22/08/2026, bug reale segnalato dal vivo: login
            # delegato riuscito, poi fallito qui con "no valid module file was found" su un PC
            # senza il modulo) - Install-M365OpsPrerequisites lo installa gia' in anticipo al
            # primo avvio, questo resta solo come rete di sicurezza se quel passaggio e' stato
            # saltato o e' fallito, stesso principio gia' in Connect-M365OpsExchange.ps1 (che
            # pero' non passa mai da QUESTA funzione, da cui il buco originale).
            # Versione FISSATA a 3.4.0, verificata dal vivo come conflict-free con MicrosoftTeams
            # 6.5.0 (25/08/2026) - vedi Assert-M365OpsExoSafeVersion.ps1 per il dettaglio completo
            # della verifica, ESATTAMENTE con -AccessToken (il percorso usato proprio qui sotto,
            # confermato funzionante nel test dal vivo). Assert-M365OpsExoSafeVersion (Private)
            # disinstalla anche attivamente una eventuale versione >= 3.10.0 gia' presente sul
            # disco, installa/importa la 3.4.0 (i chiamanti non lo fanno piu' separatamente) e
            # ripara da sola un'installazione locale corrotta se ne trova una. Output SEMPRE
            # scartato (-> Out-Null): BUG SERIO trovato dal vivo il 26/08/2026 durante il
            # riverifica di questo stesso login - il valore restituito da questa chiamata
            # (pscustomobject RemovedVersions/Installed) non era mai stato catturato ne'
            # soppresso, quindi finiva anch'esso sull'output pipeline di QUESTA funzione,
            # trasformando il risultato atteso (un singolo oggetto Status/Message) in un
            # ARRAY di due oggetti - lato client (Gui\index.html) result.Status risultava
            # quindi sempre undefined su un login riuscito, ne' "Completed" ne' "Error"
            # venivano mai riconosciuti, e il poll continuava a ripetersi all'infinito
            # mostrando "in attesa" anche a connessione gia' avvenuta (root cause reale
            # dietro il sintomo "Nessun login Exchange in corso" via una voce pending gia'
            # rimossa da un poll successivo che invece TROVAVA questo stato malformato).
            Assert-M365OpsExoSafeVersion | Out-Null
            # Invoke-M365OpsWithExoRepairRetry (Private, 25/08/2026) - vedi
            # Connect-M365OpsExchange.ps1 per il dettaglio completo.
            Invoke-M365OpsWithExoRepairRetry { Connect-ExchangeOnline -AccessToken $result.AccessToken -UserPrincipalName $script:M365OpsContext.DelegatedUpn -ShowBanner:$false -ErrorAction Stop }
            $script:M365OpsExchangeConnected = $true
            Write-Host "Exchange Online (delegato) connesso per '$tenantName'." -ForegroundColor Green
            return [pscustomobject]@{ Status = 'Completed'; Message = 'Connesso.' }
        }
        catch {
            $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Exchange Online' -OtherService 'Microsoft Teams'
            $msg = if ($hint) { $hint } else { "Token ottenuto ma la connessione a Exchange e' fallita: $($_.Exception.Message)" }
            return [pscustomobject]@{ Status = 'Error'; Message = $msg }
        }
    }
    elseif ($result.Status -eq 'Error') {
        $script:M365OpsPendingExoDeviceCode.Remove($tenantName)
    }

    # Solo Status='Pending' (l'utente non ha ancora completato il login) o Status='Error'
    # arrivano qui (il caso Completed esce sempre prima con un return esplicito, sopra) -
    # ricostruito esplicitamente invece di restituire $result cosi' com'e' per non
    # ripetere l'errore di sicurezza appena corretto: anche se OGGI Receive-
    # M365OpsDeviceCodeToken non mette mai token nei rami Pending/Error, un domani non e'
    # garantito, e qui non c'e' modo per chi legge questa riga di saperlo senza andare a
    # controllare l'altra funzione.
    [pscustomobject]@{ Status = $result.Status; Message = $result.Message }
}
