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
            Description  = "Elenca SOLO le mailbox condivise del tenant e i permessi (FullAccess/SendAs/SendOnBehalf) di ciascuna. Scatta solo se il messaggio parla esplicitamente di PERMESSI/delega su mailbox condivise - una menzione generica di 'mailbox condivisa' per altri motivi (es. una domanda sui parametri di creazione) o una richiesta di 'permessi mailbox' senza dire 'condivise' passano invece all'AI (che ha accesso a exo_query -> Get-M365OpsMailboxDelegatesReport, copertura su TUTTE le mailbox). Vedi DeferWords sotto e la nota generale in cima al file - bug reale del 17/08/2026."
            Triggers     = @(
                '(?=.*permess\w*)(?=.*(mailbox|casell))(?=.*(condivis\w*|shared))',
                '(?=.*(fullaccess|full access))(?=.*(condivis\w*|shared))',
                '(?=.*send.?as)(?=.*(condivis\w*|shared))',
                '(?=.*send.?on.?behalf)(?=.*(condivis\w*|shared))',
                '(?=.*delega\w*)(?=.*(casella|mailbox|posta))(?=.*(condivis\w*|shared))'
            )
            DeferWords   = @('report', 'xlsx', 'excel', 'csv', 'pdf', 'tab', 'gruppo', 'gruppi', 'distribuzione')
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
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $true
            Handler      = { param($formatWord) Export-M365OpsCompliancePatternsReportChat -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportDevices"
            Description  = "Esporta l'elenco dispositivi in CSV, Excel o PDF (default CSV se non specifichi). Uso: 'esporta dispositivi in excel'"
            Triggers     = @('esporta.*dispositiv', 'esporta.*device', 'report.*dispositiv', 'scarica.*dispositiv', 'dispositiv.*(csv|excel|xlsx|pdf)')
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
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega')
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
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', 'utente', '@\S+\.\S+', 'responsabile', 'capo', 'collega')
            CaptureRegex = '\b(csv|excel|xlsx|pdf)\b'
            RequiresAI   = $false
            Handler      = { param($formatWord) Export-M365OpsExoReportChat -Cmdlet 'Get-M365OpsSharedMailboxReport' -Title 'Mailbox Condivise' -FileSlug 'shared-mailbox-report' -FormatWord $formatWord }
            Formatter    = { param($r) $r }
        }
        [pscustomobject]@{
            Name         = "ExportAllMailboxesReport"
            Description  = "Esporta l'elenco di tutte le mailbox del tenant (ogni tipo) in CSV/Excel/PDF. Uso: 'esporta report mailbox totali'"
            Triggers     = @('report.*mailbox.*total', 'elenco.*tutte.*mailbox', 'tutte le mailbox', 'report.*tutte.*casell')
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega')
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
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega')
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
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', '@\S+\.\S+', 'responsabile', 'capo', 'collega')
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
            DeferWords   = @('tab', 'gruppo', 'gruppi', 'distribuzione', 'formazione', 'training', 'spiega', 'come funziona', 'policy aziendale')
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
            Triggers     = @('dispositiv.{0,30}non compliant', 'dispositiv.{0,30}non conform', 'non conform.{0,30}dispositiv', 'non compliant.{0,30}dispositiv', '^non conform', '^non compliant')
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
            # 'mail'/'email' come DeferWords fanno si' che una richiesta che nomina anche l'invio
            # passi all'AI (che ha propose_send_report_email e puo' gestire l'intera richiesta
            # composta in un unico ragionamento), invece di rispondere solo a meta'.
            DeferWords   = @('piano', 'remediation', 'consigl', 'roadmap', 'perch', 'causa', 'mail', 'email')
            CaptureRegex = $null
            RequiresAI   = $false
            Handler      = { Get-M365OpsManagedDevices -NonCompliantOnly }
            Formatter    = { param($r) if ($r) { ($r | ForEach-Object { "- $($_.deviceName): $($_.complianceState) (encrypted=$($_.isEncrypted))" }) -join "`n" } else { "Nessun dispositivo non conforme." } }
        }
        [pscustomobject]@{
            Name         = "UserOverview"
            Description  = "Panoramica di un utente (gruppi, dispositivi, app e policy assegnate). Uso: 'panoramica utente nome@dominio.it'"
            Triggers     = @('panoramica utente', 'overview utente')
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
            DeferWords   = @('report', 'tutti', 'tenant', 'conditional', 'access', 'zone', 'policy', 'criteri')
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
            CaptureRegex = 'gruppo\s+(.+)$'
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
            DeferWords   = @('account', 'access\w*', 'acced\w*', 'password', 'non riesc\w*', 'errore', 'problema', 'bloccat')
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
    )
}
