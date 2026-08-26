function Get-M365OpsMessageHeaderAnalysis {
    <#
    .SYNOPSIS
        Analizza intestazioni email grezze (RFC 5322, incollate da "Visualizza origine
        messaggio"/"Visualizza dettagli messaggio Internet" in Outlook) oppure un blocco di
        diagnostica NDR/message-trace di Exchange (formato RecipientStatus/MessageInfo, es. da
        Get-MessageTrace o dal testo di un rimbalzo incollato in chat) - replica in locale, senza
        nessuna chiamata di rete esterna, l'analisi che offre https://mha.azurewebsites.net (25/08/2026,
        richiesto esplicitamente dall'utente dopo un caso reale di troubleshooting NDR).
    .PARAMETER RawText
        Testo incollato dall'utente - rilevato automaticamente se e' intestazioni RFC 5322 o un
        blocco NDR/message-trace, mai richiesto di specificarlo a mano.
    .OUTPUTS
        pscustomobject con Kind ('Headers' o 'Ndr'), Summary, Hops (solo Kind='Headers'),
        Authentication, AntispamReport, Ndr (solo Kind='Ndr'), Warnings (elenco di anomalie
        rilevate, es. delay lungo tra due hop, SPF/DKIM/DMARC falliti).
    .NOTES
        Nessuna intestazione viene mai spedita a un servizio esterno per il parsing - solo
        l'analisi IA (facoltativa, un pulsante separato) manda il testo incollato all'IA
        configurata, esattamente come ogni altra funzione IA di questo modulo.
    #>
    param(
        [Parameter(Mandatory)] [string]$RawText
    )

    if ([string]::IsNullOrWhiteSpace($RawText)) {
        throw "Nessun testo da analizzare - incolla le intestazioni email o il blocco NDR."
    }

    # Rilevamento automatico del formato (mai chiesto all'utente): un blocco NDR/message-trace
    # di Exchange ha sempre "RecipientStatus" o "{LED=" da qualche parte, le intestazioni RFC
    # 5322 non li contengono mai per costruzione (sono nomi di campo PowerShell, non header SMTP).
    $isNdr = $RawText -match 'RecipientStatus\s*:' -or $RawText -match '\{LED='

    if ($isNdr) {
        return Get-M365OpsNdrAnalysis -RawText $RawText
    }
    return Get-M365OpsRawHeaderAnalysis -RawText $RawText
}

function Get-M365OpsRawHeaderAnalysis {
    param([string]$RawText)

    # Un-folding (26/08/2026, RFC 5322 sezione 2.2.3): una riga di continuazione di un header
    # inizia SEMPRE con uno spazio o un tab - senza unirla alla riga precedente, un header lungo
    # (es. Authentication-Results, X-Forefront-Antispam-Report, spesso spezzati su piu' righe da
    # client/gateway diversi) verrebbe troncato al primo a-capo, perdendo il resto del valore.
    $lines = $RawText -split "`r?`n"
    $unfolded = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^[ \t]' -and $unfolded.Count -gt 0) {
            $unfolded[$unfolded.Count - 1] = $unfolded[$unfolded.Count - 1] + ' ' + $line.Trim()
        } else {
            $unfolded.Add($line)
        }
    }

    # Un header puo' avere piu' occorrenze dello stesso nome (Received in primis, sempre multiplo)
    # - raggruppate qui per nome, valori nell'ordine di apparizione nel testo originale (che per
    # Received e' sempre PIU' RECENTE per primo, l'ordine standard con cui i mail server
    # anteporgono la propria riga in cima ad ogni hop).
    $headerMap = @{}
    foreach ($line in $unfolded) {
        if ($line -match '^([A-Za-z][A-Za-z0-9\-]*)\s*:\s*(.*)$') {
            $name = $Matches[1]
            $value = $Matches[2]
            if (-not $headerMap.ContainsKey($name)) { $headerMap[$name] = New-Object System.Collections.Generic.List[string] }
            $headerMap[$name].Add($value)
        }
    }
    function Get-HeaderValue($name) {
        if ($headerMap.ContainsKey($name) -and $headerMap[$name].Count -gt 0) { return $headerMap[$name][0] }
        return $null
    }

    $warnings = @()

    # --- Riepilogo ---
    $summary = [pscustomobject]@{
        Subject      = Get-HeaderValue 'Subject'
        MessageId    = Get-HeaderValue 'Message-ID'
        Date         = Get-HeaderValue 'Date'
        From         = Get-HeaderValue 'From'
        To           = Get-HeaderValue 'To'
        Cc           = Get-HeaderValue 'CC'
        ReturnPath   = Get-HeaderValue 'Return-Path'
    }
    if (-not $summary.Subject -and -not $summary.From -and -not $summary.MessageId) {
        $warnings += "Non e' stato riconosciuto nessun header standard (Subject/From/Message-ID) - verifica di aver incollato il testo giusto (intestazioni complete, non solo il corpo del messaggio)."
    }

    # --- Hop di consegna (Received:), in ordine CRONOLOGICO (il primo hop e' l'ultimo Received
    # nel testo - gli header Received si accumulano dal basso verso l'alto man mano che il
    # messaggio attraversa i server, il piu' recente e' sempre il primo che si legge). ---
    $receivedRaw = if ($headerMap.ContainsKey('Received')) { $headerMap['Received'] } else { @() }
    $chronological = @($receivedRaw)
    [array]::Reverse($chronological)

    # Pattern tollerante: "from <host> (<ip>)? by <host> (<ip>)? with <tipo> ...; <data>" - non
    # tutti i campi sono sempre presenti (es. "by" puo' mancare su un hop locale, "with" idem) -
    # ogni gruppo e' quindi opzionale, non un'unica regex rigida che fallirebbe silenziosamente
    # su una minima variazione reale (verificato dal vivo contro intestazioni Exchange Online,
    # on-premises Exchange, e gateway di terze parti come Fortinet/Cisco - la sintassi varia
    # abbastanza da richiedere questa tolleranza).
    # "from" e' opzionale in due varianti reali oltre al caso standard "from X by Y":
    # - "(from user@localhost) by host ...;" (hop di consegna locale Sendmail/Postfix, RFC 5321
    #   esempio storico, ancora comune sull'ultimo hop prima della mailbox su MTA Unix) - il from
    #   e' tra parentesi invece che nudo dopo la keyword "from".
    # - "by host with SMTP id ...;" senza "from" affatto (hop puramente interno alla stessa
    #   infrastruttura, visto dal vivo su Gmail/Google Workspace tra i propri datacenter) - qui
    #   non esiste proprio un mittente esplicito da riportare.
    # Data: il nome del giorno + virgola ("Mon,") e' facoltativo per costruzione (RFC 5322
    # permette day-of-week opzionale) - alcuni gateway on-premises e Cisco IronPort/ESA lo
    # omettono, es. "24 Aug 2026 10:00:00 +0200" - richiederlo nella regex faceva fallire l'INTERO
    # match dell'hop (non solo la data), buttando via anche from/by/with gia' corretti.
    $hopPattern = '^(?:from\s+(?<from>.+?)\s+|\(from\s+(?<from2>.+?)\)\s+)?by\s+(?<by>.+?)(?:\s+with\s+(?<with>.+?))?;\s*(?<date>(?:[A-Za-z]{3},\s*)?.+)$'
    $hops = @()
    $prevTime = $null
    $hopNum = 0
    foreach ($h in $chronological) {
        $hopNum++
        $m = [regex]::Match($h, $hopPattern)
        $fromHost = if ($m.Success -and $m.Groups['from'].Success) { $m.Groups['from'].Value.Trim() }
                    elseif ($m.Success -and $m.Groups['from2'].Success) { $m.Groups['from2'].Value.Trim() }
                    else { $null }
        $byHost = if ($m.Success) { $m.Groups['by'].Value.Trim() } else { $null }
        $withClause = if ($m.Success -and $m.Groups['with'].Success) { $m.Groups['with'].Value.Trim() } else { $null }
        $dateText = if ($m.Success) { $m.Groups['date'].Value.Trim() } else { $null }

        $parsedTime = $null
        if ($dateText) {
            # Molti server (Gmail/Google Workspace in testa, ma anche Postfix/Sendmail con
            # "(CEST)"/"(UTC)" ecc.) aggiungono un commento con l'abbreviazione del fuso orario tra
            # parentesi DOPO l'offset numerico, es. "Mon, 24 Aug 2026 01:23:39 -0700 (PDT)" - ne'
            # DateTimeOffset.Parse ne' il cast lo accettano (l'offset numerico e' gia' presente e
            # sufficiente, il commento e' ridondante) - rimosso prima del parsing, altrimenti OGNI
            # hop con questo formato perdeva completamente Time e DelaySec pur avendo una data
            # perfettamente valida.
            $dateForParse = $dateText -replace '\s*\([^)]*\)\s*$', ''

            # Bug reale trovato durante l'audit del 26/08/2026: il nome del giorno (es. "Tue,")
            # viene VALIDATO da .NET contro la data numerica che segue, non solo letto come testo
            # decorativo - un hop con un nome del giorno sbagliato (capita davvero: gateway con
            # l'orologio/fuso configurato male, header composti a mano da script di terze parti,
            # o semplicemente un mittente che mente sull'intestazione) fa fallire ENTRAMBI i
            # tentativi di parsing sotto con "was not recognized as a valid DateTime because the
            # day of week was incorrect" - non un formato non standard (gia' gestito), un
            # mismatch puro fra testo e data. L'hop finiva silenziosamente con Time=testo grezzo e
            # DelaySec=null, esattamente il sintomo che questo blocco esiste per evitare. Il nome
            # del giorno non aggiunge nessuna informazione che non sia gia' nella data numerica
            # (che e' quella davvero usata per il calcolo del ritardo) - rimosso qui PRIMA del
            # parsing, cosi' un giorno sbagliato non blocca mai piu' l'estrazione dell'orario reale.
            $dateForParse = $dateForParse -replace '^[A-Za-z]{3},\s*', ''
            try { $parsedTime = [datetimeoffset]::Parse($dateForParse, [System.Globalization.CultureInfo]::InvariantCulture) } catch {
                # Alcuni gateway on-premises omettono il nome del giorno o usano un formato non
                # standard (verificato dal vivo su un hop Exchange on-prem) - un secondo
                # tentativo senza vincolare la cultura, prima di arrendersi e mostrare il testo
                # grezzo invece di una data vuota che sembrerebbe un bug.
                try { $parsedTime = [datetimeoffset]$dateForParse } catch { $parsedTime = $null }
            }
        }
        $delaySeconds = if ($parsedTime -and $prevTime) { [math]::Round(($parsedTime - $prevTime).TotalSeconds, 1) } else { $null }
        if ($delaySeconds -ne $null -and $delaySeconds -ge 60) {
            $warnings += "Ritardo di $([math]::Round($delaySeconds/60,1)) minuti tra l'hop $($hopNum-1) e l'hop $hopNum ($byHost) - un salto insolitamente lento, spesso segno di una coda/limitazione su quel server piuttosto che di un problema di rete generico."
        }
        if ($parsedTime) { $prevTime = $parsedTime }

        $hops += [pscustomobject]@{
            Hop      = $hopNum
            # Il testo grezzo va in From SOLO se l'intero hop non e' stato riconosciuto (nessun
            # campo strutturato disponibile) - un hop riconosciuto ma senza clausola "from"
            # esplicita (es. Gmail interno "by host with SMTP id ...;", nessun mittente dichiarato)
            # deve restare $null e non mostrare l'intera riga grezza spacciandola per un mittente.
            From     = if ($fromHost) { $fromHost } elseif (-not $m.Success) { $h } else { $null }
            By       = $byHost
            Type     = $withClause
            Time     = if ($parsedTime) { $parsedTime.ToString('dd/MM/yyyy HH:mm:ss zzz') } else { $dateText }
            DelaySec = $delaySeconds
        }
    }

    # --- Autenticazione (SPF/DKIM/DMARC/compauth) - Authentication-Results puo' comparire piu'
    # volte (un hop per ogni gateway che ha fatto una propria verifica, tipico multi-hop
    # ibrido/partner) - qui si riporta SEMPRE quella piu' esterna/vicina al mittente originale
    # (l'ultima nel testo, equivalente alla prima verifica cronologica) perche' e' quella che
    # riflette il controllo sulla connessione SMTP reale, le altre sono spesso solo "propagate"
    # da un hop interno che si fida del passaggio precedente. ---
    $authResults = if ($headerMap.ContainsKey('Authentication-Results')) { $headerMap['Authentication-Results'][-1] } else { $null }
    $authentication = $null
    if ($authResults) {
        $extractVerdict = { param($field) if ($authResults -match "$field=(\w+)") { $Matches[1] } else { $null } }
        $spf = & $extractVerdict 'spf'
        $dkim = & $extractVerdict 'dkim'
        $dmarc = & $extractVerdict 'dmarc'
        $compauth = & $extractVerdict 'compauth'
        $authentication = [pscustomobject]@{ Spf = $spf; Dkim = $dkim; Dmarc = $dmarc; CompAuth = $compauth; Raw = $authResults }
        foreach ($pair in @(@{n='SPF';v=$spf}, @{n='DKIM';v=$dkim}, @{n='DMARC';v=$dmarc})) {
            if ($pair.v -and $pair.v -notin @('pass', 'none')) {
                $warnings += "$($pair.n) risulta '$($pair.v)' (non 'pass') - possibile causa di rifiuto/quarantena se il destinatario applica policy severe su questo controllo."
            }
        }
    }

    # --- X-Forefront-Antispam-Report: coppie chiave:valore separate da ';' - decodifica delle
    # chiavi piu' comuni (elenco Microsoft, non esaustivo apposta: meglio mostrare il valore
    # grezzo per una chiave sconosciuta che ometterla o inventarne il significato). ---
    $fpasRaw = Get-HeaderValue 'X-Forefront-Antispam-Report'
    $antispamReport = $null
    if ($fpasRaw) {
        $knownKeys = @{
            CIP  = 'IP di connessione'
            CTRY = 'Paese (da IP)'
            LANG = 'Lingua rilevata'
            SCL  = 'Spam Confidence Level (-1 = attendibile/whitelisted, 0-1 = non spam, 5-6 = spam probabile, 9 = spam ad alta confidenza)'
            SRV  = 'Servizio speciale (es. SPM = spam, BULK = posta massiva)'
            SFV  = 'Verdetto filtro spam (NSPM = non spam, SPM = spam, SKS = saltato per regola, BLK = bloccato)'
            H    = 'HELO/EHLO dichiarato dal mittente'
            PTR  = 'Reverse DNS (PTR) dell''IP di connessione'
            CAT  = 'Categoria filtro (es. SPM/PHSH/BULK/NONE)'
            DIR  = 'Direzione (INB = in ingresso, OUT = in uscita)'
            IPV  = 'Versione controllo reputazione IP (CAL = calibrato, NLI = nessuna informazione)'
        }
        $parsed = [ordered]@{}
        foreach ($pair in ($fpasRaw -split ';')) {
            if ($pair -match '^([A-Za-z]+):(.*)$') {
                $k = $Matches[1]; $v = $Matches[2]
                if ($v) { $parsed[$k] = [pscustomobject]@{ Value = $v; Label = $knownKeys[$k] } }
            }
        }
        $antispamReport = [pscustomobject]@{ Fields = $parsed; Raw = $fpasRaw }
        if ($parsed.Contains('SCL') -and $parsed['SCL'].Value -match '^\d+$' -and [int]$parsed['SCL'].Value -ge 5) {
            $warnings += "SCL (Spam Confidence Level) = $($parsed['SCL'].Value) - il filtro antispam ha considerato il messaggio sospetto, possibile causa di quarantena o recapito in posta indesiderata anche se non e' stato rifiutato del tutto."
        }
    }

    [pscustomobject]@{
        Kind            = 'Headers'
        Summary         = $summary
        Hops            = $hops
        Authentication  = $authentication
        AntispamReport  = $antispamReport
        Warnings        = $warnings
        RawText         = $RawText
    }
}

function Get-M365OpsNdrAnalysis {
    param([string]$RawText)

    # Formato tipico (Get-MessageTrace/Get-MessageTraceDetail, o incollato da un rimbalzo
    # ricevuto in chat - visto dal vivo il 24/08/2026): campi "Chiave : {valore}" su piu' righe,
    # RecipientStatus contiene un blocco {[{LED=...};{MSG=...};{FQDN=...};{IP=...};{LRT=...}]}.
    $warnings = @()

    $recipientStatusRaw = $null
    if ($RawText -match '(?s)RecipientStatus\s*:\s*(.+?)(?:\r?\n\s*\r?\n|\r?\nMessageInfo|\z)') {
        $recipientStatusRaw = $Matches[1].Trim()
    }

    $led = $null; $msg = $null; $fqdn = $null; $ip = $null; $lrt = $null
    if ($recipientStatusRaw) {
        if ($recipientStatusRaw -match 'LED=([^\}]+)') { $led = $Matches[1].Trim() }
        if ($recipientStatusRaw -match 'MSG=([^\}]*)') { $msg = $Matches[1].Trim() }
        if ($recipientStatusRaw -match 'FQDN=([^\}]+)') { $fqdn = $Matches[1].Trim() }
        if ($recipientStatusRaw -match 'IP=([^\}]+)') { $ip = $Matches[1].Trim() }
        if ($recipientStatusRaw -match 'LRT=([^\}]+)') { $lrt = $Matches[1].Trim() }
    }

    # Bug reale trovato dal vivo il 24/08/2026 (primo test con un NDR reale incollato dall'utente,
    # non un caso costruito a mano): il valore di LED puo' arrivare gia' spezzato su piu' righe
    # (l'ID di tracciamento tra parentesi quadre spesso va a capo da solo, con indentazione, nel
    # testo incollato dall'utente) - '.' non matcha mai un a-capo per default in .NET regex, quindi
    # '^(\d{3})\s+(\d\.\d\.\d)\s+(.*)$' falliva SEMPRE su un LED multi-riga, lasciando
    # SmtpCode/EnhancedCode/Text vuoti nonostante RawLed catturasse correttamente tutto il testo.
    # Normalizzato PRIMA di estrarre i codici: qualunque sequenza di spazi/a-capo diventa un solo
    # spazio, il testo del messaggio resta leggibile ma l'estrazione dei codici funziona sempre,
    # indipendentemente da come il testo e' stato incollato.
    $ledNormalized = if ($led) { ($led -replace '\s+', ' ').Trim() } else { $null }
    $enhancedCode = $null; $smtpCode = $null; $ledText = $null
    if ($ledNormalized -match '^(\d{3})\s+(\d\.\d\.\d)\s+(.*)$') {
        $smtpCode = $Matches[1]; $enhancedCode = $Matches[2]; $ledText = $Matches[3]
    }

    $messageInfoRaw = $null
    if ($RawText -match '(?s)MessageInfo\s*:\s*(.+?)(?:\r?\n\s*\r?\n|\z)') {
        $messageInfoRaw = $Matches[1].Trim()
    }

    if ($enhancedCode -eq '5.4.1') {
        $warnings += "Codice 5.4.1 'Recipient address rejected: Access denied' - nella grande maggioranza dei casi NON e' un blocco di sicurezza/relay: e' il Directory-Based Edge Blocking (DBEB) del tenant di destinazione che non trova un mailbox valido per quell'indirizzo in quel momento. Controlla PRIMA che l'indirizzo destinatario sia scritto correttamente ed esista davvero, prima di indagare su IP/connector/relay."
    } elseif ($smtpCode -eq '550' -and $enhancedCode -match '^5\.7\.') {
        $warnings += "Codice $enhancedCode - tipicamente un blocco di policy/reputazione (SPF/DKIM/DMARC non superati, o IP/mittente in una lista di blocco) piuttosto che un problema di indirizzo destinatario."
    } elseif ($smtpCode -eq '550' -and $enhancedCode -match '^5\.1\.') {
        $warnings += "Codice $enhancedCode - indirizzo destinatario davvero inesistente (non un problema di directory/sync come il 5.4.1), verifica il nome utente/dominio."
    }

    [pscustomobject]@{
        Kind      = 'Ndr'
        Ndr       = [pscustomobject]@{
            SmtpCode      = $smtpCode
            EnhancedCode  = $enhancedCode
            Text          = $ledText
            RawLed        = $ledNormalized
            Message       = $msg
            Fqdn          = $fqdn
            Ip            = $ip
            LastRetryTime = $lrt
            MessageInfo   = $messageInfoRaw
        }
        Warnings  = $warnings
        RawText   = $RawText
    }
}
