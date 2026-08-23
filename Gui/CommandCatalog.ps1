<#
    Catalogo dei comandi locali che il motore di chat riconosce SENZA chiamare l'AI
    (eccetto le voci con RequiresAI = $true, dove il ragionamento e' proprio lo scopo).

    Aggiungere una capacita' nuova = aggiungere una voce qui, non riscrivere il router.
    Le voci con flussi a piu' turni (creazione gruppo, packaging app, assegnazione) restano
    codice dedicato in Server.ps1 perche' richiedono stato/conferma - questo catalogo copre
    le richieste dirette, senza conferma necessaria (sola lettura).
#>

function Format-M365OpsOverview {
    param($r)
    $lines = @()
    if ($r.User) { $lines += "UTENTE: $($r.User)" }
    if ($r.Group) { $lines += "GRUPPO: $($r.Group)" }

    if ($r.Groups) {
        $lines += ""; $lines += "Gruppi ($($r.Groups.Count)):"
        $lines += ($r.Groups | ForEach-Object { "  - $($_.displayName)" })
    }
    if ($r.Members) {
        $lines += ""; $lines += "Membri ($($r.Members.Count)):"
        $lines += ($r.Members | ForEach-Object { "  - $($_.displayName) ($($_.userPrincipalName))" })
    }
    if ($r.Devices) {
        $lines += ""; $lines += "Dispositivi ($($r.Devices.Count)):"
        $lines += ($r.Devices | ForEach-Object { "  - $($_.deviceName): $($_.complianceState)" })
    } else {
        $lines += ""; $lines += "Dispositivi: nessuno"
    }

    $lines += ""; $lines += "App assegnate ($($r.AssignedApps.Count)):"
    $lines += if ($r.AssignedApps) { ($r.AssignedApps | ForEach-Object { "  - $($_.Name) [$($_.Intent)] via $($_.Via)" }) } else { @("  (nessuna)") }

    $lines += ""; $lines += "Profili di configurazione assegnati ($($r.AssignedConfigProfiles.Count)):"
    $lines += if ($r.AssignedConfigProfiles) { ($r.AssignedConfigProfiles | ForEach-Object { "  - $($_.Name) via $($_.Via)" }) } else { @("  (nessuno)") }

    $lines += ""; $lines += "Criteri di compliance assegnati ($($r.AssignedCompliancePolicies.Count)):"
    $lines += if ($r.AssignedCompliancePolicies) { ($r.AssignedCompliancePolicies | ForEach-Object { "  - $($_.Name) via $($_.Via)" }) } else { @("  (nessuno)") }

    return ($lines -join "`n")
}

function Get-M365OpsCommandCatalog {
    @(
        [pscustomobject]@{
            Name         = "EmailLastReport"
            Description  = "Invia per email l'ultimo report generato in questa sessione. Uso: 'invialo per email a nome@dominio.it'"
            Triggers     = @('invia\w*.{0,20}(email|mail)', 'manda\w*.{0,20}(email|mail)', 'spedisci\w*.{0,20}(email|mail)')
            # Il dominio non termina mai con un punto letterale, cosi' un punto di fine frase
            # subito dopo l'indirizzo non finisce dentro l'email catturata (stesso bug/fix di
            # Get-M365OpsGroupPlanFromMessage in Server.ps1).
            CaptureRegex = '([\w\.\-]+@[\w\-]+(?:\.[\w\-]+)+)'
            # Un messaggio composito ("genera il report X e mandalo a Y") deve andare all'AI
            # (che genera il report POI propone l'invio in un unico ragionamento, vedi
            # propose_send_report_email in Invoke-M365OpsAgentTools) invece di far scattare
            # subito questa scorciatoia: se il report non esiste ancora in questa sessione,
            # l'handler sotto fallirebbe con "genera prima un report" anche se la richiesta
            # completa lo chiedeva nello stesso messaggio (bug reale, stesso schema gia' visto
            # per SharedMailboxPermissions il 17/08/2026).
            #
            # BUG SERIO trovato dal vivo il 18/08/2026 durante uno stress test: questo handler
            # invia SEMPRE e SOLO $script:LastReportPath (l'ultimo file generato in sessione),
            # senza mai controllare se corrisponde davvero all'argomento del messaggio. Con
            # "mandami via mail un report dei dispositivi non conformi a X" dopo aver appena
            # generato un report DIVERSO (es. mailbox condivise), l'app proponeva di inviare
            # a X il file sbagliato con dati non richiesti - nessun errore, nessun avviso.
            # 'report\s+(dei|delle|di|degli|su|sui|sulle|sull)' intercetta il caso in cui il
            # messaggio DESCRIVE esplicitamente il contenuto del report voluto (rischio di
            # scambio) e lo devia all'AI, che ha il contesto per accorgersi della discrepanza
            # invece di inviare alla cieca. Un "invialo"/"mandalo" senza descrizione resta
            # invece sul percorso rapido, corretto: si riferisce sempre all'ultimo generato.
            DeferWords   = @('genera\w*', 'crea\w*', 'esporta\w*', 'aggiorna\w*', 'report\s+(dei|delle|di|degli|su|sui|sulle|sull)')
            RequiresAI   = $false
            Handler      = {
                param($toAddress)
                if (-not $script:LastReportPath -or -not (Test-Path $script:LastReportPath)) {
                    return @{ ok = $false; error = "Nessun report generato in questa sessione. Genera prima un report (es. 'esporta dispositivi in pdf')." }
                }
                if (-not $toAddress) {
                    return @{ ok = $false; error = "Non ho trovato un indirizzo email nel messaggio." }
                }
                # Non invia piu' direttamente (bug reale corretto il 17/08/2026: un'email a un
                # indirizzo estratto da regex, potenzialmente esterno al tenant, partiva senza
                # nessuna conferma - unica scrittura dell'app senza quel passaggio). Stessa
                # infrastruttura di conferma di ogni altra scrittura, riusando il case
                # 'SendReportEmail' gia' costruito per il percorso AI (propose_send_report_email).
                $fileName = Split-Path -Leaf $script:LastReportPath
                $confirmText = "Invio il report '$fileName' via email a $toAddress. Confermi?"
                $script:PendingAction = @{
                    Type = 'SendReportEmail'; To = $toAddress; Subject = "Report M365Ops"
                    Body = "In allegato il report generato da M365Ops."; AttachmentPath = $script:LastReportPath
                    ConfirmText = $confirmText
                }
                @{ ok = $true; text = "$confirmText`n(rispondi 'si' o 'no')" }
            }
            Formatter    = {
                param($r)
                if ($r.ok) { return $r.text }
                return "Invio fallito: $($r.error)"
            }
        }
        [pscustomobject]@{
            Name         = "SharedMailboxPermissions"
            # BUG UX trovato dal vivo il 19/08/2026 (richiesto un controllo di coerenza sul testo
            # di "aiuto" dopo le modifiche di oggi): questo campo Description e' anche il testo
            # mostrato DAVVERO all'utente dal comando locale "Help" - la spiegazione tecnica sul
            # perche' il trigger e' cosi' specifico (con riferimento a "DeferWords" e a un bug del
            # 17/08/2026, gergo interno privo di senso per un utente) ci finiva dentro per errore.
            # Spostata qui come commento; il campo Description ora contiene solo cio' che ha senso
            # mostrare a un utente reale, come per ogni altra voce del catalogo.
            #
            # Scatta solo se il messaggio parla esplicitamente di PERMESSI/delega su mailbox
            # condivise - una menzione generica di 'mailbox condivisa' per altri motivi (es. una
            # domanda sui parametri di creazione) o una richiesta di 'permessi mailbox' senza dire
            # 'condivise' passano invece all'AI (che ha accesso a exo_query ->
            # Get-M365OpsMailboxDelegatesReport, copertura su TUTTE le mailbox). Vedi DeferWords
            # sotto e la nota generale in cima al file - bug reale del 17/08/2026.
            Description  = "Elenca le mailbox condivise del tenant e i permessi (FullAccess/SendAs/SendOnBehalf) di ciascuna. Uso: 'permessi mailbox condivise'"
            Triggers     = @(
                '(?=.*permess\w*)(?=.*(mailbox|casell))(?=.*(condivis\w*|shared))',
                '(?=.*(fullaccess|full access))(?=.*(condivis\w*|shared))',
                '(?=.*send.?as)(?=.*(condivis\w*|shared))',
                '(?=.*send.?on.?behalf)(?=.*(condivis\w*|shared))',
                '(?=.*delega\w*)(?=.*(casella|mailbox|posta))(?=.*(condivis\w*|shared))'
            )
            # Verbi di scrittura (23/08/2026, bug-hunt di 16 ore, stesso schema gia' corretto su
            # MfaStatus): i trigger sopra sono puri lookahead sui SOSTANTIVI ("permessi",
            # "mailbox", "condivisa"), senza controllo sul verbo - "aggiungi il permesso
            # FullAccess sulla mailbox condivisa Vendite a mario@contoso.com" matcha comunque
            # tutti i lookahead, e questo handler (sola lettura) elencava i permessi ESISTENTI
            # invece di proporre la scrittura richiesta (Grant-M365OpsMailboxPermission esiste
            # gia' come propose_exo_write) - nessun errore, nessuna scrittura, richiesta ignorata.
            DeferWords   = @('report', 'xlsx', 'excel', 'csv', 'pdf', 'tab', 'gruppo', 'gruppi', 'distribuzione', 'aggiung\w*', 'rimuov\w*', 'togli\w*', 'revoc\w*', 'concedi\w*', 'assegna\w*', 'grant\w*')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = {
                try {
                    $mailboxes = @(Get-M365OpsSharedMailboxes)
                    $data = foreach ($mb in $mailboxes) {
                        $perms = @(Get-M365OpsMailboxPermissions -Identity $mb.PrimarySmtpAddress)
                        [pscustomobject]@{ Mailbox = $mb.DisplayName; Email = $mb.PrimarySmtpAddress; Permissions = $perms }
                    }
                    @{ ok = $true; data = $data }
                }
                catch {
                    @{ ok = $false; error = $_.Exception.Message }
                }
            }
            Formatter    = {
                param($r)
                if (-not $r.ok) {
                    return "Non sono riuscito a leggere i dati da Exchange Online: $($r.error)`n`nSe il collegamento non e' ancora completo (certificato caricato su Entra ID, permesso Exchange.ManageAsApp con consenso admin, ruolo RBAC assegnato al service principal), e' questo il motivo."
                }
                if (-not $r.data -or @($r.data).Count -eq 0) { return "Nessuna mailbox condivisa trovata nel tenant." }
                $lines = @("Mailbox condivise ($(@($r.data).Count)):")
                foreach ($item in $r.data) {
                    $lines += ""
                    $lines += "- $($item.Mailbox) ($($item.Email))"
                    if ($item.Permissions -and @($item.Permissions).Count -gt 0) {
                        foreach ($p in $item.Permissions) { $lines += "    $($p.Type): $($p.User) [$($p.Rights)]" }
                    } else {
                        $lines += "    (nessun permesso delegato oltre al proprietario)"
                    }
                }
                return ($lines -join "`n")
            }
        }
        [pscustomobject]@{
            Name         = "ExportCompliancePatterns"
            Description  = "Esporta l'analisi pattern di non conformita' in PDF (richiede l'AI per generare l'analisi). Uso: 'esporta l'analisi pattern in pdf'"
            # Bug latente corretto per ispezione il 18/08/2026 (stesso schema di CompliancePatterns
            # qui sopra, mai innescato dal vivo): 'esporta.*analisi' con distanza illimitata e
            # senza l'ancora "pattern" avrebbe intercettato qualunque richiesta di esportare
            # un'analisi di qualsiasi tipo. Distanza limitata e "pattern" richiesto ovunque.
            Triggers     = @('esporta.{0,30}pattern', 'report.{0,30}pattern', 'pdf.{0,30}pattern', 'pattern.{0,30}(pdf|excel|csv)')
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): stesso schema
            # gia' visto sulle voci gemelle - senza, "manda via mail un report sui pattern di
            # conformita'" veniva risposto con l'export grezzo, ignorando in silenzio l'invio.
            # 'phishing'/'attacc'/'naming'/'convenzion' (23/08/2026, bug-hunt di 16 ore): questa
            # voce non puo' richiedere "conform*" nel trigger (l'uso documentato sopra, "esporta
            # l'analisi pattern in pdf", non lo contiene affatto - l'utente lo sa gia' dal
            # contesto). Il trigger 'pattern' + parola di export resta quindi ambiguo con
            # TUTT'ALTRI tipi di pattern (es. "esporta i pattern di attacco di phishing rilevati
            # in pdf") - un vero export di pattern DI SICUREZZA/PHISHING, non di non conformita'
            # dispositivi, che questo handler dedicato non sa affatto generare. Segnali di
            # un tipo di pattern diverso deviano ora all'AI invece di produrre in silenzio il
            # report sbagliato.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', 'invia', 'manda', 'spedisci', 'phishing', 'attacc\w*', 'attack', 'naming', 'convenzion\w*')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $true
            Handler      = { param($formatWord) Export-M365OpsCompliancePatternsReportChat -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportDevices"
            Description  = "Esporta l'elenco dispositivi in CSV, Excel o PDF (default CSV se non specifichi). Uso: 'esporta dispositivi in excel'"
            # Distanza limitata a {0,30} (23/08/2026, bug-hunt di 16 ore): questi 5 pattern
            # usavano ancora '.*' SENZA LIMITI (a differenza della voce gemella
            # ExportCompliancePatterns, dove '{0,30}' fu introdotto apposta il 18/08/2026 per lo
            # stesso identico motivo) - "Puoi fare un report su cosa e' successo ieri con
            # Exchange e SharePoint, includendo anche eventuali dispositivi compromessi?" fa
            # scattare 'report.*dispositiv' nonostante "report" e "dispositiv" siano a distanza
            # enorme e la richiesta reale sia un'indagine multi-servizio, non un export.
            Triggers     = @('esporta.{0,30}dispositiv', 'esporta.{0,30}device', 'report.{0,30}dispositiv', 'scarica.{0,30}dispositiv', 'dispositiv.{0,30}(csv|excel|xlsx|pdf)')
            # Bug reale trovato dal vivo il 18/08/2026: 'scarica.*dispositiv' con .* senza limiti
            # intercettava anche richieste composte molto piu' ricche di un semplice export con le
            # colonne di default - es. "scarica un report con seriale, versione SO, cifrato si/no,
            # antivirus si/no di tutti i dispositivi intune e invialo a x@y.it" veniva risposto con
            # l'elenco dispositivi grezzo (colonne di default, NON quelle richieste) e la parte
            # "invialo a" veniva silenziosamente ignorata perche' questo handler deterministico non
            # sa concatenare un invio email - mai arrivato all'AI, che invece gestisce entrambe le
            # cose. Aggiunti segnali di richiesta piu' ampia: campi/colonne specifiche richieste,
            # verbi di invio, o un indirizzo email presente nel messaggio (anche senza la parola
            # "email"/"mail" - l'utente puo' scrivere solo l'indirizzo).
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', 'seriale', 'versione', 'cifrat', 'antivirus', 'compliance', 'colonne', 'campi', 'invia', 'manda', 'spedisci', '@\S+\.\S+')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsDeviceReportChat -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportMailboxUsageReport"
            Description  = "Esporta il report di utilizzo/quota di tutte le mailbox (CSV/Excel/PDF). Uso: 'esporta report utilizzo mailbox in excel'"
            Triggers     = @('report.*(utilizzo|usage|spazio|quota).*mailbox', 'mailbox.*(utilizzo|usage|spazio|quota)')
            # @\S+\.\S+/responsabile/capo/collega (18/08/2026): stesso schema trovato dal vivo su
            # ExportMailFlowReport - "report su X ... e inoltralo/mandalo a persona Y" va all'AI
            # (che genera il report POI propone l'invio), non a un export diretto senza invio.
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): senza,
            # "invia via mail il report delle mailbox condivise" (nessun indirizzo email
            # letterale, solo l'intento "via mail") veniva risposto col solo report grezzo in
            # chat, ignorando in silenzio l'invio - stesso identico bug gia' corretto su
            # ExportDevices/EmailLastReport/ListNonCompliant ma mai propagato a questa voce
            # gemella. '@\S+\.\S+' da solo copriva solo il caso con un indirizzo email esplicito.
            # Guardia domanda di supporto (23/08/2026, bug-hunt di 16 ore): a differenza della
            # PRIMA alternativa del trigger sopra ('report.*(utilizzo|...).*mailbox', che
            # richiede la parola "report"), la SECONDA ('mailbox.*(utilizzo|...)') non richiede
            # alcun verbo di export - "la mailbox di Mario ha superato la quota, cosa faccio?"
            # la fa scattare comunque, proponendo un export invece di rispondere alla domanda.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega', 'invia', 'manda', 'spedisci', 'cosa faccio', 'perch[eé]', 'puoi (controllare|verificare|aiutarmi|dirmi)', 'non riesc\w*')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsMailboxUsageReport' -Title 'Utilizzo Mailbox' -FileSlug 'mailbox-usage' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportSharedMailboxReport"
            Description  = "Esporta il report completo delle mailbox condivise (dimensione, permessi) in CSV/Excel/PDF. Uso: 'esporta report mailbox condivise in pdf'"
            Triggers     = @('report.*mailbox.*condivis', 'esporta.*mailbox.*condivis', 'report.*shared.*mailbox')
            # 'utente' in piu': questo report copre SOLO le condivise - un messaggio che chiede
            # anche le mailbox utente vuole piu' di quanto questa voce sappia fare (bug reale
            # del 17/08/2026, insieme a tab/gruppo/gruppi/distribuzione).
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): stesso schema
            # gia' visto sulle voci gemelle (vedi ExportMailboxUsageReport) - senza, l'intento
            # "invia via mail" senza un indirizzo email letterale veniva ignorato in silenzio.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', 'utente', '@\S+\.\S+', 'responsabile', 'capo', 'collega', 'invia', 'manda', 'spedisci')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsSharedMailboxReport' -Title 'Mailbox Condivise' -FileSlug 'shared-mailbox-report' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportAllMailboxesReport"
            Description  = "Esporta l'elenco di tutte le mailbox del tenant (ogni tipo) in CSV/Excel/PDF. Uso: 'esporta report mailbox totali'"
            Triggers     = @('report.*mailbox.*total', 'elenco.*tutte.*mailbox', 'tutte le mailbox', 'report.*tutte.*casell')
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): senza,
            # "invia via mail il report delle mailbox condivise" (nessun indirizzo email
            # letterale, solo l'intento "via mail") veniva risposto col solo report grezzo in
            # chat, ignorando in silenzio l'invio - stesso identico bug gia' corretto su
            # ExportDevices/EmailLastReport/ListNonCompliant ma mai propagato a questa voce
            # gemella. '@\S+\.\S+' da solo copriva solo il caso con un indirizzo email esplicito.
            # Negazione (23/08/2026, bug-hunt di 16 ore): il trigger 'tutte le mailbox' e' una
            # sottostringa letterale senza ancora di verbo - "non tutte le mailbox sono state
            # migrate correttamente, puoi controllare quali mancano?" la contiene comunque (la
            # negazione "non" precede semplicemente la stessa frase), scatenando un export
            # completo invece di rispondere alla domanda sulla migrazione.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega', 'invia', 'manda', 'spedisci', 'non tutte', 'perch[eé]', 'puoi (controllare|verificare)', 'mancano', 'migrat\w*')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsAllMailboxes' -Title 'Tutte le Mailbox' -FileSlug 'all-mailboxes' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportMailFlowReport"
            Description  = "Esporta il report del flusso posta (mail flow) in CSV/Excel/PDF. Uso: 'esporta report mail flow'"
            Triggers     = @('report.*mail.?flow', 'report.*flusso.*posta', 'mail.?flow.*report')
            # Bug reale trovato dal vivo il 18/08/2026: "prepara un report della configurazione
            # mail flow e poi inoltralo al mio responsabile diego@contoso.com" veniva intercettato
            # qui (prima ancora di arrivare a ExportForwardingReport), rispondendo "nessun dato
            # trovato" invece di generare il report E proporre l'invio via AI.
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): senza,
            # "invia via mail il report delle mailbox condivise" (nessun indirizzo email
            # letterale, solo l'intento "via mail") veniva risposto col solo report grezzo in
            # chat, ignorando in silenzio l'invio - stesso identico bug gia' corretto su
            # ExportDevices/EmailLastReport/ListNonCompliant ma mai propagato a questa voce
            # gemella. '@\S+\.\S+' da solo copriva solo il caso con un indirizzo email esplicito.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega', 'invia', 'manda', 'spedisci')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsMailFlowReport' -Title 'Mail Flow' -FileSlug 'mail-flow' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportForwardingReport"
            Description  = "Esporta il report delle mailbox con inoltro automatico configurato (sicurezza) in CSV/Excel/PDF. Uso: 'esporta report inoltri'"
            Triggers     = @('report.*inoltr', 'forwarding.*report', 'mailbox.*inoltr')
            # Bug reale trovato dal vivo il 18/08/2026 durante un giro di stress-test: 'report.*
            # inoltr' intercettava anche "prepara un report [su TUTT'ALTRO] e poi inoltralo al mio
            # responsabile diego@contoso.com" - "inoltralo" (forward IT, a una persona) e non
            # "inoltro" (le regole di forwarding automatico, l'argomento reale di questa voce).
            # Un indirizzo email o un riferimento a una persona destinataria segnala questo
            # secondo significato, non richiesto qui.
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): senza,
            # "invia via mail il report delle mailbox condivise" (nessun indirizzo email
            # letterale, solo l'intento "via mail") veniva risposto col solo report grezzo in
            # chat, ignorando in silenzio l'invio - stesso identico bug gia' corretto su
            # ExportDevices/EmailLastReport/ListNonCompliant ma mai propagato a questa voce
            # gemella. '@\S+\.\S+' da solo copriva solo il caso con un indirizzo email esplicito.
            # Guardia domanda di supporto (23/08/2026, bug-hunt di 16 ore): la terza alternativa
            # del trigger sopra ('mailbox.*inoltr') non richiede alcun verbo di export - "la
            # mailbox di Mario continua a fare inoltro automatico anche se doveva essere
            # disabilitato, puoi controllare perche'?" la fa scattare comunque.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega', 'invia', 'manda', 'spedisci', 'cosa faccio', 'perch[eé]', 'puoi (controllare|verificare|aiutarmi|dirmi)', 'non riesc\w*')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsForwardingReport' -Title 'Mailbox con Inoltro Automatico' -FileSlug 'forwarding-report' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportInboxRulesReport"
            Description  = "Esporta il report delle regole posta in arrivo, con evidenza di quelle sospette (sicurezza) in CSV/Excel/PDF. Uso: 'esporta report regole sospette'"
            Triggers     = @('regole.*sospett', 'inbox rule', 'report.*regole.*posta')
            # Bug reale trovato dal vivo il 18/08/2026: 'regole.*sospett' intercettava anche una
            # domanda di spiegazione/formazione ("ho letto della policy su regole sospette,
            # spiegami come funziona la formazione utenti") invece di una richiesta di export -
            # nessun bisogno di un file qui, l'utente vuole una spiegazione discorsiva.
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato): stesso schema
            # gia' visto sulle voci gemelle - senza, "invia via mail il report delle regole
            # sospette" veniva risposto con l'export grezzo, ignorando in silenzio l'invio.
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', 'formazione', 'training', 'spiega', 'come funziona', 'policy aziendale', 'invia', 'manda', 'spedisci')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsInboxRulesReport' -Title 'Regole Posta in Arrivo' -FileSlug 'inbox-rules-report' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ListNonCompliant"
            Description  = "Elenca i dispositivi Intune non conformi."
            # Bug reale trovato il 18/08/2026 durante un batch di test con prompt reali estratti
            # da mail: il trigger 'non conform' da solo intercettava QUALSIASI richiesta che
            # contenesse quella sottostringa, anche del tutto estranea ai dispositivi - es.
            # "Analizza configurazioni di sicurezza Microsoft 365 non conformi: MFA, DKIM,
            # DMARC..." veniva risposta con un elenco dispositivi non conformi invece che
            # inoltrata all'AI per l'analisi di sicurezza richiesta davvero. Il trigger ora
            # richiede che 'dispositiv' compaia vicino a 'non conform*' (o che il messaggio sia
            # una richiesta diretta che comincia cosi'), invece di una sottostringa isolata.
            # BUG reale trovato dal vivo il 19/08/2026 durante un bug-hunt mirato con italiano
            # sgrammaticato: "dispositivi mostrami quali sono kelli nn conformi" (typo comune
            # da tastiera, "nn" per "non") NON faceva scattare questo trigger (richiedeva "non
            # conform" letterale) - cadeva invece sul catch-all '^dispositiv' di ListDevices
            # qui sotto, che ha risposto con TUTTI i dispositivi (compresi quelli conformi)
            # invece dei soli non conformi richiesti, senza alcun segnale che il filtro fosse
            # stato ignorato. '(non|nn)\s*conform*' tollera ora anche questa abbreviazione.
            # BUG reale trovato dal vivo il 19/08/2026, stesso bug-hunt: "quali dispositivi nn
            # sono conformi" (forma verbale del tutto normale, non un refuso) non faceva
            # scattare NEMMENO il fix sopra - '(non|nn)\s*conform' richiede "non"/"nn" ADIACENTE
            # a "conform*", ma qui in mezzo c'e' il verbo "sono". Cadeva su ListDevices (elenco
            # non filtrato) esattamente come il caso "nn" gia' corretto. '(\s+\w+){0,2}' tollera
            # ora fino a 2 parole di mezzo (sono/e'/risultano/appaiono...) tra la negazione e
            # "conform*", senza aprire a distanze arbitrarie che intercetterebbero frasi estranee.
            Triggers     = @('dispositiv.{0,30}(non|nn)(\s+\w+){0,2}\s*compliant', 'dispositiv.{0,30}(non|nn)(\s+\w+){0,2}\s*conform', '(non|nn)(\s+\w+){0,2}\s*conform.{0,30}dispositiv', '(non|nn)(\s+\w+){0,2}\s*compliant.{0,30}dispositiv', '^(non|nn)(\s+\w+){0,2}\s*conform', '^(non|nn)(\s+\w+){0,2}\s*compliant')
            # Bug reale trovato dal vivo il 18/08/2026: il trigger riconosce correttamente il
            # topic "dispositivi non conformi", ma una richiesta che chiede ANCHE un piano di
            # remediation/analisi ("...e qual e' il piano di remediation consigliato") veniva
            # risposta col solo elenco grezzo, troncando silenziosamente la parte che richiede
            # ragionamento AI - stesso schema di richiesta composta gia' visto altrove.
            #
            # BUG SERIO trovato dal vivo lo stesso giorno, durante lo stress test che ha corretto
            # anche EmailLastReport: "mandami via mail un report dei dispositivi non conformi a
            # X" veniva deviato correttamente da EmailLastReport (grazie al fix su quella voce),
            # ma cadeva DRITTO su questa voce subito dopo - che mostrava l'elenco grezzo in chat
            # e ignorava in silenzio "mandami via mail", senza mai proporre un invio email.
            # 'mail'/'email' come DeferWords fanno si' che una richiesta che nomini anche l'invio
            # passi all'AI (che ha propose_send_report_email e puo' gestire l'intera richiesta
            # composta in un unico ragionamento), invece di rispondere solo a meta'.
            #
            # BUG SERIO trovato dal vivo il 19/08/2026 durante lo stress test sulla seconda ondata
            # Intune: "controlla i dispositivi non conformi e poi dimmi se ci sono anelli di
            # aggiornamento Windows configurati e anche i criteri MAM Android" ha risposto SOLO con
            # l'elenco grezzo dei dispositivi, ignorando in silenzio il resto - questa voce non
            # aveva mai ricevuto le parole di continuazione generiche ('e poi'/'e anche'/'quindi')
            # gia' aggiunte alle voci gemelle (ListDevices/CompliancePatterns/UserOverview/
            # GroupOverview/MfaStatus) lo stesso giorno per lo stesso identico schema di bug -
            # questa voce era rimasta indietro perche' le sue DeferWords erano gia' state estese
            # con parole SPECIFICHE (piano/remediation/mail) in un fix precedente, dando la falsa
            # impressione di essere gia' a posto.
            # 'pattern'/'correlazion' aggiunti lo stesso giorno (bug-hunt mirato): "mostrami
            # pattern di conformita' dei dispositivi non conformi" veniva risposto con l'elenco
            # grezzo invece di essere inoltrato a CompliancePatterns (RequiresAI, la voce
            # pensata apposta per raggruppare/correlare) - la sua voce gemella qui sotto ha un
            # trigger che matcha ANCHE questo messaggio, ma essendo elencata dopo nell'array non
            # veniva mai raggiunta.
            # 'poi'/'dopo' isolate (23/08/2026, bug-hunt di 16 ore): 'e poi'/'e anche'/'quindi'
            # sono frasi LETTERALI - "dispositivi non conformi, poi manda la lista al mio capo"
            # (virgola invece di "e", "poi" da solo) non le contiene, quindi non deviava
            # all'AI nonostante la seconda parte della richiesta fosse reale quanto negli altri
            # casi gia' corretti. 'rimuov\w*'/'rimoss\w*'/'elimin\w*' aggiunti per lo stesso
            # motivo di MfaStatus: "i dispositivi non conformi dovrebbero essere rimossi dal
            # gruppo Intune, puoi farlo?" e' un intento di SCRITTURA che questa voce (sola
            # lettura) ignorava silenziosamente.
            DeferWords   = @('piano', 'remediation', 'consigl', 'roadmap', 'perch', 'causa', 'mail', 'email', 'e poi', 'e anche', 'quindi', 'poi', 'dopo', 'pattern', 'correlazion', 'rimuov\w*', 'rimoss\w*', 'elimin\w*')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = { Get-M365OpsManagedDevices -NonCompliantOnly }
            Formatter    = { param($r) if ($r) { ($r | ForEach-Object { "- $($_.deviceName): $($_.complianceState) (encrypted=$($_.isEncrypted))" }) -join "`n" } else { "Nessun dispositivo non conforme." } }
        }
        [pscustomobject]@{
            Name         = "UserOverview"
            Description  = "Panoramica di un utente (gruppi, dispositivi, app e policy assegnate). Uso: 'panoramica utente nome@dominio.it'"
            Triggers     = @('panoramica utente', 'overview utente')
            # Bug reale trovato dal vivo il 19/08/2026 (stesso schema di MfaStatus): "panoramica
            # utente X e poi elenca i gruppi di distribuzione" mostrava solo la panoramica (che
            # include gia' i GRUPPI DI CUI L'UTENTE E' MEMBRO, un dato diverso e piu' ristretto
            # di "tutti i gruppi di distribuzione del tenant" richiesto nella seconda parte) -
            # la vera richiesta finale spariva senza risposta.
            # 'poi'/'dopo' isolate (23/08/2026, bug-hunt di 16 ore): 'e poi'/'e anche'/'quindi'
            # sono frasi LETTERALI - "panoramica utente X, poi disattivagli l'account" (virgola
            # invece di "e") non le contiene, la seconda parte spariva in silenzio.
            DeferWords   = @('e poi', 'e anche', 'quindi', 'poi', 'dopo')
            # Il dominio non termina mai con un punto letterale, cosi' un punto di fine frase
            # subito dopo l'indirizzo non finisce dentro l'email catturata (stesso bug/fix di
            # Get-M365OpsGroupPlanFromMessage in Server.ps1).
            CaptureRegex = '([\w\.\-]+@[\w\-]+(?:\.[\w\-]+)+)'
            RequiresAI   = $false
            Handler      = {
                param($upn)
                if (-not $upn) { return @{ error = "Non ho trovato un indirizzo email nel messaggio. Uso: 'panoramica utente nome@dominio.it'" } }
                Get-M365OpsUserOverview -Upn $upn
            }
            Formatter    = { param($r) if ($r -is [hashtable] -and $r.error) { $r.error } else { Format-M365OpsOverview $r } }
        }
        [pscustomobject]@{
            Name         = "MfaStatus"
            Description  = "Stato MFA di un utente: quali metodi di autenticazione ha registrato (Authenticator, telefono, FIDO2, ecc.). Uso: 'stato mfa di nome@dominio.it'"
            Triggers     = @('stato mfa', 'mfa\s+(di|per)', 'metodi.{0,10}autenticazione')
            # Bug reale trovato dal vivo il 18/08/2026 (stesso schema di ListDevices/
            # ListNonCompliant/ExportDevices): 'metodi.{0,10}autenticazione' da solo
            # intercettava anche una richiesta di REPORT a livello tenant su Conditional
            # Access/MFA ("...metodi di autenticazione consentiti" dentro un report molto piu'
            # ampio), rispondendo con "non ho trovato un indirizzo email" invece di passare
            # all'AI. Segnali di richiesta piu' ampia (report/tenant/CA), non di un singolo
            # utente, fanno passare oltre.
            # Secondo bug reale, stesso giorno, stesso schema ma sul lato "richiesta composta":
            # "controlla lo stato mfa di X e poi elenca i gruppi di distribuzione" veniva
            # gestito interamente da questo catalogo (zero costo AI) - la seconda parte della
            # richiesta ("e poi...") spariva silenziosamente, mai eseguita da nessuno. Le parole
            # di continuazione fanno ora passare l'intero messaggio all'AI, che gestisce
            # correttamente richieste composte in un solo ragionamento.
            # Terzo bug reale, stesso schema, trovato dal vivo il 23/08/2026 durante lo stress
            # test di 16 ore: "resetta l'mfa di X, si e' bloccato il telefono" veniva
            # intercettato QUI (il trigger 'mfa\s+(di|per)' matcha anche "l'mfa di X") e
            # rispondeva SOLO con lo stato MFA attuale (Get-M365OpsUserMfaStatus, sola lettura),
            # ignorando silenziosamente il verbo "resetta" - l'utente non otteneva ne' un reset
            # ne' un errore ne' una richiesta di chiarimento, solo una risposta che sembrava
            # pertinente ma non faceva quello che aveva chiesto (l'unico modo reale per proporre
            # un reset e' propose_mfa_reset, uno strumento AI - questo catalogo lo bypassa del
            # tutto per costruzione, RequiresAI = $false). Stesso principio delle due voci sopra:
            # un segnale di intento diverso (qui, un verbo di reset/rimozione) fa passare
            # l'intero messaggio all'AI invece di eseguire alla cieca la sola lettura.
            # 'poi'/'dopo' isolate (23/08/2026, stesso bug-hunt): "stato mfa di X, poi
            # disattivagli l'account" (virgola invece di "e poi") non veniva deviato.
            DeferWords   = @('report', 'tutti', 'tenant', 'conditional', 'access', 'zone', 'policy', 'criteri', 'e poi', 'e anche', 'quindi', 'poi', 'dopo', 'reset\w*', 'rimuov\w*', 'cancell\w*', 'elimin\w*', 'disattiv\w*', 'sblocc\w*')
            CaptureRegex = '([\w\.\-]+@[\w\-]+(?:\.[\w\-]+)+)'
            RequiresAI   = $false
            Handler      = {
                param($upn)
                if (-not $upn) { return @{ error = "Non ho trovato un indirizzo email nel messaggio. Uso: 'stato mfa di nome@dominio.it'" } }
                Get-M365OpsUserMfaStatus -Upn $upn
            }
            Formatter    = {
                param($r)
                if ($r -is [hashtable] -and $r.error) { return $r.error }
                $lines = @("MFA per $($r.Upn): $(if ($r.MfaConfigured) { 'configurata' } else { 'NON configurata (nessun metodo oltre alla password)' })")
                if ($r.AllMethods -and $r.AllMethods.Count -gt 0) {
                    $lines += ""
                    $lines += "Metodi registrati:"
                    $lines += ($r.AllMethods | ForEach-Object { "  - $($_.Type)$(if ($_.DisplayName) { ": $($_.DisplayName)" })" })
                }
                return ($lines -join "`n")
            }
        }
        [pscustomobject]@{
            Name         = "GroupOverview"
            Description  = "Panoramica di un gruppo (membri, app e policy assegnate). Uso: 'panoramica gruppo NomeGruppo'"
            Triggers     = @('panoramica gruppo', 'overview gruppo')
            # Bug reale trovato dal vivo il 19/08/2026 (stesso schema di MfaStatus/UserOverview):
            # "panoramica gruppo build e poi dimmi quali connettori send sono configurati" veniva
            # gestito qui - il CaptureRegex, greedy fino a fine stringa, catturava l'INTERO resto
            # del messaggio come se fosse il nome del gruppo ("build e poi dimmi quali connettori
            # send sono configurati"), fallendo con "nessun gruppo trovato" invece di rispondere
            # a nessuna delle due richieste reali.
            # 'poi'/'dopo' isolate (23/08/2026, stesso bug-hunt): "panoramica gruppo X, poi
            # rimuovi Mario dai membri" (virgola invece di "e poi") non veniva deviato.
            DeferWords   = @('e poi', 'e anche', 'quindi', 'poi', 'dopo')
            # Secondo bug reale, stesso schema, trovato dal vivo il 23/08/2026 (bug-hunt di 16
            # ore): DeferWords sopra intercetta solo le tre frasi di continuazione LETTERALI
            # ("e poi"/"e anche"/"quindi") - una richiesta altrettanto naturale ma diversamente
            # formulata ("panoramica gruppo IT-Support, elenca anche i membri" o "panoramica
            # gruppo Marketing e dimmi chi ne fa parte") non le contiene, quindi non scatta il
            # defer, e il vecchio CaptureRegex greedy fino a fine stringa ('gruppo\s+(.+)$')
            # catturava l'INTERA coda come se fosse il nome del gruppo (es. "IT-Support, elenca
            # anche i membri") - Get-M365OpsGroupOverview cerca con un filtro Graph ESATTO su
            # quel nome, quindi falliva sempre con "nessun gruppo trovato" invece di rispondere
            # alla panoramica vera e propria (che avrebbe comunque incluso i membri richiesti).
            # Corretto rendendo la cattura NON greedy e fermandola al primo segnale di frase
            # successiva (virgola, o " e " seguito da un verbo di continuazione comune) invece
            # di continuare fino alla fine - un nome di gruppo reale non contiene mai questi
            # pattern, quindi non c'e' rischio di troncare un nome legittimo.
            CaptureRegex = 'gruppo\s+(.+?)(?:\s*,|\s+e\s+(?:dimmi|elenca|mostra|dammi|chi|poi|anche)\b|\s*$)'
            RequiresAI   = $false
            Handler      = {
                param($name)
                if (-not $name -or -not $name.Trim()) { return @{ error = "Non ho trovato un nome di gruppo nel messaggio. Uso: 'panoramica gruppo NomeGruppo'" } }
                Get-M365OpsGroupOverview -GroupName $name.Trim()
            }
            Formatter    = { param($r) if ($r -is [hashtable] -and $r.error) { $r.error } else { Format-M365OpsOverview $r } }
        }
        [pscustomobject]@{
            Name         = "CompliancePatterns"
            Description  = "Analizza e raggruppa i pattern di non conformita' — usa l'AI (Claude), unica voce del catalogo con un costo."
            # Bug latente trovato per ispezione il 18/08/2026 (stesso schema di ListDevices/
            # MfaStatus/ExportDevices, qui pero' mai innescato dal vivo prima di essere corretto):
            # 'pattern' da solo, senza alcun vincolo, avrebbe intercettato QUALSIASI messaggio
            # contenente quella parola in un contesto completamente diverso (es. "pattern di
            # attacco phishing", "naming pattern per i gruppi"), dirottandolo su una chiamata AI
            # a pagamento dedicata invece del normale flusso conversazionale. Richiede ora che
            # "pattern" e "non conform*"/"conformit*" compaiano vicini, entrambi presenti.
            Triggers     = @('pattern.{0,20}(non conform|conformit)', '(non conform|conformit).{0,20}pattern')
            # Bug reale trovato dal vivo il 19/08/2026 (stesso schema di MfaStatus): l'handler
            # chiama una funzione AI dedicata a un solo scopo (analisi pattern), senza accesso
            # agli altri strumenti - "analizza i pattern di non conformita' e poi controlla lo
            # stato mfa di X" produceva un'ottima analisi pattern ma ignorava del tutto la parte
            # MFA, che nessuno eseguiva mai. Le parole di continuazione deviano ora l'intero
            # messaggio al loop AI generale (Invoke-M365OpsAgentTools), che ha accesso a tutti
            # gli strumenti e puo' gestire la richiesta composta in un solo ragionamento.
            # 'invia'/'manda'/'spedisci' aggiunti il 19/08/2026 (bug-hunt mirato), stesso motivo:
            # l'handler dedicato non ha accesso a propose_send_report_email - "manda via mail un
            # report sui pattern di conformita'" produceva l'analisi ma ignorava l'invio.
            # 'poi'/'dopo' isolate (23/08/2026, stesso bug-hunt): stessa lacuna delle voci
            # gemelle - "e poi"/"e anche"/"quindi" sono frasi letterali, "analizza i pattern di
            # non conformita', poi controlla lo stato mfa di X" (virgola) non le contiene.
            DeferWords   = @('e poi', 'e anche', 'quindi', 'poi', 'dopo', 'invia', 'manda', 'spedisci')
            CaptureRegex = $null
            RequiresAI   = $true
            Handler      = { Get-M365OpsCompliancePatterns -Provider $script:ActiveAIProvider }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ListDevices"
            Description  = "Elenca tutti i dispositivi Intune gestiti."
            # Bug reale trovato il 18/08/2026 (stesso schema di ListNonCompliant qui sotto): il
            # trigger 'dispositiv' da solo intercettava qualunque frase che nominasse un
            # dispositivo di sfuggita, anche dentro una richiesta completamente diversa - es.
            # "...Verifica se il problema e' lato Teams, account, dispositivo o infrastruttura
            # VDI" (troubleshooting microfono Teams) o "training HD1 su join dispositivi, LAPS,
            # admin locale" (richiesta di supporto) venivano risposte con il semplice elenco
            # dispositivi invece di essere inoltrate all'AI. Il trigger ora richiede un verbo di
            # richiesta esplicita (elenca/lista/mostra/quali/vedi/dammi) vicino a 'dispositiv',
            # o che il messaggio sia un comando diretto che comincia cosi'.
            Triggers     = @('(elenca|lista|mostra|mostrami|quali( sono)?|vedi|dammi).{0,20}dispositiv', '^dispositiv')
            # Bug reale trovato dal vivo il 19/08/2026 (stesso schema di MfaStatus): "elenca i
            # dispositivi e poi dimmi anche quanti gruppi di distribuzione ci sono" mostrava solo
            # l'elenco dispositivi, ignorando silenziosamente "e poi..." - nessuno (ne' il
            # catalogo ne' l'AI) rispondeva alla seconda parte.
            #
            # 'conform'/'compliant'/'nn conform' aggiunti lo stesso giorno (bug-hunt mirato): il
            # catch-all '^dispositiv' intercetta ANCHE una richiesta che parla di conformita' con
            # "dispositivi" messo in testa alla frase (fronting comune nel parlato/scritto
            # informale, es. "dispositivi, quali sono i non conformi" con ordine invertito) -
            # rete di sicurezza in piu' oltre al fix diretto su ListNonCompliant: se il messaggio
            # nomina la conformita' (anche fuori dai pattern gia' coperti sopra), questa voce si
            # fa da parte invece di rispondere con l'elenco NON filtrato spacciandolo per
            # completo. NON si usa il solo 'non' come DeferWord: e' una delle parole piu' comuni
            # dell'italiano ("dispositivi non aggiornati da tempo" ecc.) - avrebbe fatto deviare
            # all'AI anche richieste semplicissime senza alcun legame con la conformita'.
            # 'poi'/'dopo' isolate (23/08/2026, stesso bug-hunt): "elenca i dispositivi, poi
            # dimmi quanti gruppi ci sono" (virgola) non veniva deviato dalle sole frasi letterali.
            DeferWords   = @('e poi', 'e anche', 'quindi', 'poi', 'dopo', 'nn\s*conform', 'compliant', 'conform')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = { Get-M365OpsManagedDevices }
            Formatter    = { param($r) ($r | ForEach-Object { "- $($_.deviceName): $($_.complianceState)" }) -join "`n" }
        }
        [pscustomobject]@{
            Name         = "ResetChatHistory"
            Description  = "Azzera lo storico della conversazione salvato in locale per il tenant attivo. Uso: 'nuova conversazione'"
            Triggers     = @('nuova conversazione', 'dimentica (tutto|la conversazione)', 'cancella (la )?cronologia', 'resetta (la )?chat')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = { Clear-M365OpsChatHistory -TenantName $script:ActiveTenantProfile; $script:PendingAction = $null }
            Formatter    = { param($r) "Storico della conversazione azzerato. Ripartiamo da qui." }
        }
        [pscustomobject]@{
            Name         = "Help"
            Description  = "Elenca le funzioni disponibili in locale (nessuna chiamata AI)."
            Triggers     = @('^aiuto', 'cosa sai fare', '^help', 'elenco comandi')
            # Bug reale trovato dal vivo il 18/08/2026: '^aiuto' da solo intercettava anche un
            # vero problema dell'utente che iniziava per caso con quella parola ("aiuto! ho perso
            # l'accesso al mio account, cosa devo fare"), rispondendo con l'elenco comandi invece
            # di passare all'AI che avrebbe potuto aiutare davvero con il problema reale.
            #
            # BUG SERIO trovato dal vivo durante uno stress test lo stesso giorno: 'accesso' e
            # 'non riesco' come stringhe letterali non coprivano le coniugazioni piu' comuni -
            # "un dipendente NON RIESCE PIU' ad ACCEDERE alla mail" (terza persona, verbo
            # "accedere" invece del sostantivo "accesso") non veniva deviato da NESSUNO dei sei
            # DeferWords, e l'AI non veniva mai interpellata su un problema reale di un utente.
            # 'access\w*|acced\w*' copre sia il sostantivo (accesso/accessi) sia le forme del
            # verbo accedere (accedo/accedi/accede/accedere/acceduto); 'non riesc\w*' copre
            # tutte le persone (riesco/riesci/riesce/riescono), non solo la prima singolare.
            # 'blocc\w*' invece di 'bloccat' (23/08/2026, bug-hunt di 16 ore): la stringa
            # letterale 'bloccat' matcha solo il participio passato (bloccato/bloccata/i) - "aiuto,
            # Teams si blocca ogni volta che condivido lo schermo" (presente, "blocca") non veniva
            # deviato da nessuna DeferWord.
            DeferWords   = @('account', 'access\w*', 'acced\w*', 'password', 'non riesc\w*', 'errore', 'problema', 'blocc\w*')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = { $null }
            Formatter    = {
                param($r)
                $lines = @("Comandi riconosciuti in locale (nessun costo AI, tranne dove segnalato):")
                foreach ($e in (Get-M365OpsCommandCatalog)) {
                    $aiTag = if ($e.RequiresAI) { " [usa AI]" } else { "" }
                    $lines += "- $($e.Name)$aiTag`: $($e.Description)"
                }
                $lines += ""
                $lines += "Inoltre: 'crea gruppo NOME', 'pacchettizza' (dopo aver caricato un file), 'assegna [required|available] [a tutti|al gruppo]' — questi richiedono conferma prima di eseguire."
                return ($lines -join "`n")
            }
        }
        [pscustomobject]@{
            # Aggiunta il 21/08/2026, richiesta esplicitamente dall'utente: "vorrei fare una
            # sezione check permessi app dove... l'interfaccia scrive all'utente se puo' usare
            # Teams, SharePoint, Exchange etc, in lettura o anche in scrittura". Discusso con
            # l'utente dove farla vivere (sotto-sezione statica nel tab Tenant vs pulsante in
            # chat) - scelto il pulsante/comando in chat, coerente con come ogni altro insight
            # di quest'app viene presentato, e riconoscibile anche scrivendo la domanda a mano.
            # RequiresAI=$false: i dati (quali permessi sono REALMENTE concessi via Graph) sono
            # gia' precisi e verificabili da soli, un riassunto AI aggiungerebbe solo rischio di
            # parafrasare male un nome di permesso senza alcun beneficio.
            Name         = "AppPermissionsCheck"
            Description  = "Verifica quali permessi ha davvero l'app registrata (Graph/Exchange/SharePoint/Teams) e cosa manca per lettura o scrittura completa. Uso: 'verifica permessi app'"
            Triggers     = @('(verific|controll|check).{0,15}permess', 'che permess.{0,20}(ha|hai)', 'stato permess', 'permess.{0,20}(app|applicazione|service principal)')
            # Bug reale trovato dal vivo il 21/08/2026 durante lo stress test: "come funziona il
            # check permessi per un tenant delegato?" - una domanda INFORMATIVA sulla
            # funzionalita', mai una richiesta di eseguirla - veniva comunque intercettata dal
            # trigger 'check.{0,15}permess' (letteralmente presente nella frase) ed eseguiva il
            # controllo vero invece di rispondere alla domanda con l'AI/la guida. Parole che
            # segnalano una domanda SU come funziona qualcosa, non una richiesta di farlo,
            # dirottano all'AI - stesso principio gia' usato altrove nel catalogo per le domande
            # meta sulle altre funzionalita'.
            DeferWords   = @('come funziona', 'cosa fa', 'spiega', 'spiegami', 'perche')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = { Get-M365OpsAppPermissionsCheck }
            Formatter    = {
                param($r)
                $icon = @{ 'lettura+scrittura' = '✅'; 'lettura' = '🟡'; 'nessun accesso' = '❌'; 'informativo' = 'ℹ️' }
                # Intestazione condizionale App-only vs Delegated (21/08/2026, bug reale
                # segnalato dall'utente: su un tenant Delegato non esiste "l'app registrata" -
                # e' l'UTENTE con cui si e' fatto login, stesso marcatore "RBAC Exchange di" gia'
                # usato per il testo di chiusura sotto).
                $isDelegatedResult = @($r | Where-Object { $_.Resource -like '*RBAC Exchange di*' -or $_.Resource -like '*directory Entra ID di*' -or $_.Resource -like '*directoryRole*' }).Count -gt 0
                $headerText = if ($isDelegatedResult) { "Permessi reali del TUO utente su questo tenant (verificati ora, non un elenco statico):" } else { "Permessi reali dell'app registrata su questo tenant (verificati ora su Microsoft Graph, non un elenco statico):" }
                $lines = @($headerText, "")
                foreach ($area in $r) {
                    $lines += "$($icon[$area.Status]) $($area.Area) — $($area.Status)"
                    if ($area.MissingForWrite -and $area.MissingForWrite.Count -gt 0) {
                        $lines += "    per anche modificare (scrittura), aggiungi: $($area.MissingForWrite -join ', ')"
                    }
                    elseif ($area.MissingForRead -and $area.MissingForRead.Count -gt 0) {
                        $lines += "    per abilitarlo, aggiungi: $($area.MissingForRead -join ', ')"
                    }
                    if ($area.Note) { $lines += "    nota: $($area.Note)" }
                }
                $lines += ""
                # Testo di chiusura diverso per App-only vs Delegated (21/08/2026, bug reale
                # trovato dal vivo: il suggerimento "aggiungi da App Registration" non ha senso
                # su un tenant Delegato, dove non esiste nessuna App Registration da modificare -
                # rilevato controllando se un'area ha "RBAC Exchange di" nel Resource, marcatore
                # esclusivo del ramo Delegated (Get-M365OpsDelegatedPermissionsCheck).
                $isDelegated = @($r | Where-Object { $_.Resource -like '*RBAC Exchange di*' }).Count -gt 0
                if ($isDelegated) {
                    $lines += "Un ruolo Exchange mancante si assegna da Exchange admin center → Ruoli, oppure con Add-RoleGroupMember/New-ManagementRoleAssignment - le mappature area->ruolo sopra sono verificate solo in parte (vedi le note), non un catalogo esaustivo di tutti i ruoli Exchange."
                } else {
                    $lines += "Ogni permesso mancante si aggiunge da App Registration → API permissions → Add a permission, poi 'Grant admin consent' (sezioni 4.2/4.3/4.4 della guida) - le assegnazioni RBAC Exchange (sezione 6) restano un controllo separato, non verificabile da qui."
                }
                return ($lines -join "`n")
            }
        }
    )
}
