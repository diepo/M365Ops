function Invoke-M365OpsWriteWithIsolationRecovery {
    <#
    .SYNOPSIS
        Esegue $Action (una scrittura Exchange/Teams gia' confermata dall'utente, es.
        Set-M365OpsTeam/New-M365OpsDistributionGroup) e, se fallisce con il conflitto .NET
        noto di sezione 6.6 (Get-M365OpsModuleConflictHint lo riconosce), tenta l'isolamento
        reattivo e RIPROVA la stessa azione una sola volta invece di limitarsi a mostrare
        l'errore .NET grezzo.

        PERCHE' SERVE, oltre al meccanismo gia' esistente nei catch di Connect-M365OpsExchange/
        Teams/Compliance.ps1 (26/08/2026, bug reale trovato dal vivo durante un bug-hunt):
        quel meccanismo scatta SOLO quando il conflitto si manifesta durante la CONNESSIONE
        stessa - ma Teams/Exchange possono connettersi ENTRAMBI con successo nello stesso
        processo (nessun errore a quel punto) e il conflitto manifestarsi solo DOPO, su una
        chiamata autenticata specifica (riprodotto dal vivo: Set-Team ha fallito con
        "Method not found: 'Void Microsoft.Identity.Client.ITokenCache.Deserialize(Byte[])'."
        - MSAL caricato in una versione diversa da quella attesa da QUEL punto del codice,
        mai toccato prima) - un caso che il meccanismo esistente non copriva affatto, l'errore
        arrivava grezzo e criptico fino all'utente in chat.

        Attivazione SEMPRE E SOLO reattiva (stesso principio del meccanismo esistente): mai
        un tentativo di isolamento preventivo, solo in risposta a un'eccezione reale gia'
        avvenuta che corrisponde al pattern noto.

        RISCHIO DI DOPPIA ESECUZIONE (31/08/2026, bug reale trovato dalla maratona di
        stress-test, non ancora completamente risolvibile qui): il commento sopra dice gia'
        che questo conflitto "puo' manifestarsi anche DOPO un connect riuscito" - per lo
        stesso motivo puo' manifestarsi anche DOPO che la scrittura remota e' gia' riuscita
        davvero (es. durante il marshalling locale di una risposta remota GIA' arrivata con
        successo, non durante la richiesta stessa). $Action avvolge cmdlet di scrittura NON
        idempotenti (New-M365OpsTeam, New-M365OpsDistributionGroup, ecc.) - un retry alla
        cieca in quello scenario eseguirebbe la stessa creazione/scrittura una SECONDA volta
        sul tenant reale. Non esiste un modo GENERICO per questa funzione di verificare "e'
        gia' successo?" per un $Action arbitrario (richiederebbe una verifica specifica per
        ogni tipo di cmdlet, fuori scope di un fix in questo wrapper condiviso). Mitigato
        invece rendendo il rischio VISIBILE invece che silenzioso: il parametro opzionale
        -RecoveredViaIsolation (se fornito) viene valorizzato a $true SOLO quando il recupero
        reattivo e' scattato ed e' andato a buon fine al secondo tentativo - i chiamanti
        (Gui\Server.ps1, rami ExoWrite/TeamsWrite) lo usano per aggiungere un avviso esplicito
        nella risposta mostrata all'utente, invece di un "Fatto." che nasconderebbe il rischio
        di duplicato.
    .PARAMETER Action
        Scriptblock che esegue la scrittura vera (es. { & $action.Cmdlet @params }).
    .PARAMETER ModuleType
        'Exchange' o 'Teams' - quale dei due moduli sta eseguendo $Action, usato per scegliere
        quale worker isolato attivare e per il messaggio d'errore se anche l'isolamento fallisce.
    .PARAMETER RecoveredViaIsolation
        [ref] opzionale - se fornito, viene impostato a $true quando (e SOLO quando) il
        recupero reattivo e' scattato e la riprova e' andata a buon fine, cosi' il chiamante
        puo' avvisare l'utente del rischio di doppia esecuzione (vedi sopra). Ignorato se non
        fornito - il percorso normale (nessun conflitto) resta invariato in ogni caso.
    #>
    param(
        [Parameter(Mandatory)] [scriptblock]$Action,
        [Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType,
        [ref]$RecoveredViaIsolation
    )

    try {
        return & $Action
    }
    catch {
        $otherService = if ($ModuleType -eq 'Exchange') { 'Microsoft Teams' } else { 'Exchange Online' }
        $thisService = if ($ModuleType -eq 'Exchange') { 'Exchange Online' } else { 'Microsoft Teams' }
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService $thisService -OtherService $otherService
        if (-not $hint) { throw }

        Write-M365OpsLog "Conflitto .NET reale rilevato durante una scrittura $ModuleType (non al connect, vedi Invoke-M365OpsWriteWithIsolationRecovery) - tento l'isolamento reattivo e riprovo la stessa azione una volta sola."
        try {
            Connect-M365OpsIsolatedModule -ModuleType $ModuleType -ConnectParams (Get-M365OpsIsolatedConnectParams -ModuleType $ModuleType)
        }
        catch {
            throw "$hint`n`n(tentata anche l'attivazione dell'isolamento reattivo per riprovare subito, ma e' fallita a sua volta: $($_.Exception.Message))"
        }

        # Riprova UNA sola volta - i proxy globali installati da Connect-M365OpsIsolatedModule
        # intercettano ora i cmdlet nativi (es. Set-Team) sotto lo stesso nome, quindi $Action
        # (che li chiama per nome, mai tramite un riferimento gia' risolto) instrada da sola
        # verso il processo isolato senza bisogno di cambiare nulla qui.
        try {
            $result = & $Action
            # Messaggio corretto il 26/08/2026 (era troppo ottimista: diceva "nessun riavvio
            # necessario") dopo aver scoperto dal vivo, nella stessa sessione in cui questa
            # funzione e' stata scritta, che il conflitto puo' lasciare un'instabilita'
            # residua nel processo anche DOPO che questo recupero e' riuscito (letture
            # Exchange indipendenti, minuti dopo, hanno cominciato a fallire con un errore
            # correlato - IDX12729, decodifica token JWT - risolto solo da un riavvio
            # completo, vedi guida sezione 6.6 per il dettaglio completo). Il recupero qui
            # resta comunque utile (l'azione confermata dall'utente va a buon fine), ma non
            # e' una garanzia di stabilita' per il resto della sessione.
            Write-M365OpsLog "Scrittura $ModuleType riuscita al secondo tentativo tramite isolamento reattivo (processo separato). Il conflitto rilevato puo' pero' aver lasciato un'instabilita' residua nel processo per operazioni successive non correlate (vedi guida sezione 6.6) - se compaiono altri errori insoliti (es. decodifica token JWT), un riavvio completo del server resta la soluzione piu' sicura." -Level Warn
            if ($RecoveredViaIsolation) { $RecoveredViaIsolation.Value = $true }
            return $result
        }
        catch {
            throw "$hint`n`n(tentato anche un secondo tentativo tramite isolamento reattivo, fallito anch'esso: $($_.Exception.Message))"
        }
    }
}
