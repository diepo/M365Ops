function Get-M365OpsSetupStatus {
    <#
    .SYNOPSIS
        Controllo dello stato reale dell'ambiente per il tenant attivo: cosa manca
        (secret, chiavi AI, certificato, dipendenze di sistema) e come sistemarlo. Pensato
        per rilevare un ambiente "a meta'" - es. dopo aver copiato la cartella su un PC
        nuovo, dove il codice c'e' ma segreti/certificato/dipendenze non si spostano mai
        per design (vedi sezione 18 della guida). Non lancia mai eccezioni: ogni controllo
        e' isolato, un problema in uno non deve nascondere lo stato degli altri.
    #>
    $items = @()

    if (-not $script:M365OpsContext) {
        return @([pscustomobject]@{ Name = 'Tenant attivo'; Status = 'Missing'; Detail = 'Nessun tenant attivo.'; Fix = 'Attiva un profilo dal tab Tenant.' })
    }
    $ctx = $script:M365OpsContext
    $authMode = if ($ctx.AuthMode) { $ctx.AuthMode } else { 'AppOnly' }

    if ($authMode -eq 'AppOnly') {
        # Bug reale trovato dal vivo il 20/08/2026 su un PC di test: "Cannot bind argument to
        # parameter 'Name' because it is an empty string." - un tenant AppOnly puo' legittimamente
        # avere SOLO il certificato configurato (Set-M365OpsTenant accetta SecretEnvVar O
        # ExchangeCertThumbprint, non richiede entrambi - vedi quella funzione), quindi
        # $ctx.SecretEnvVar puo' essere una stringa vuota per design, non un errore di dati.
        # Get-M365OpsSecret ha -Name Mandatory: PowerShell tratta una stringa vuota passata a un
        # parametro Mandatory come "nessun valore" e in un host non interattivo (questo processo
        # server, senza console) lancia quell'eccezione invece di chiedere input - stesso motivo
        # per cui Get-M365OpsToken.ps1 e Connect-M365OpsIntune.ps1 gia' proteggono la stessa
        # chiamata con un controllo "if ($ctx.SecretEnvVar)" a monte. Qui il controllo mancava.
        if ($ctx.SecretEnvVar) {
            $secret = Get-M365OpsSecret -Name $ctx.SecretEnvVar
            $items += [pscustomobject]@{
                Name = "Client secret ($($ctx.SecretEnvVar))"
                Status = if ($secret) { 'OK' } else { 'Missing' }
                Detail = if ($secret) { 'Impostato.' } else { "Variabile d'ambiente '$($ctx.SecretEnvVar)' non trovata su questo PC." }
                Fix = 'Tab Tenant -> campo "Valore client secret" -> Salva profilo (oppure setx e riavvia il terminale).'
            }
        }
        if ($ctx.ExchangeCertThumbprint) {
            $certPresent = Test-Path "Cert:\CurrentUser\My\$($ctx.ExchangeCertThumbprint)"
            $items += [pscustomobject]@{
                Name = "Certificato Exchange ($($ctx.ExchangeCertThumbprint))"
                Status = if ($certPresent) { 'OK' } else { 'Missing' }
                Detail = if ($certPresent) { 'Presente nel certificate store di questo utente Windows.' } else { "Non trovato in Cert:\CurrentUser\My su questo PC - la chiave privata non si sposta mai copiando la cartella." }
                Fix = 'Esporta il .pfx (con chiave privata) dal PC originale e importalo qui - vedi sezione 18.3 della guida. Se non hai accesso al PC originale, va rigenerato un nuovo certificato (sezione 5.1) e ricaricato su Entra ID.'
            }
        }
    }
    else {
        $items += [pscustomobject]@{
            Name = "UPN delegato"
            Status = if ($ctx.DelegatedUpn) { 'OK' } else { 'Missing' }
            Detail = if ($ctx.DelegatedUpn) { $ctx.DelegatedUpn } else { 'Non impostato.' }
            Fix = 'Tab Tenant -> campo UPN (modalita Delegata) -> Salva profilo.'
        }
        # Bug reale segnalato dal vivo il 21/08/2026: chiamata "Sessione delegata", generica -
        # un utente che aveva appena completato con successo il login DELEGATO SPECIFICO di
        # Exchange (tab Tenant -> riquadro Exchange Online -> codice dispositivo, vedi
        # Complete-M365OpsExchangeDelegatedLogin.ps1) continuava a vedere questa voce come
        # "Missing", sembrando contraddittorio ("ho appena fatto login, perche' dice ancora di
        # no?"). Sono in realta' DUE sessioni indipendenti: questa e' quella di Microsoft Graph
        # generico (pulsante "Accedi con il mio utente", usata per utenti/gruppi/licenze/ecc via
        # Graph/Lokka), Exchange PowerShell ha la propria sessione separata (device code sotto il
        # riquadro Exchange, verificabile in "Stato connessioni" -> Exchange Online) - restare
        # senza login su Graph mentre Exchange e' gia' connesso e' uno stato normale e valido,
        # non un problema a meta'. Rinominata per chiarire la distinzione invece di lasciare
        # "sessione delegata" ambiguo tra le due.
        $delegatedSession = $script:M365OpsTokenCache[$ctx.Name].Delegated
        $sessionActive = [bool]($delegatedSession -and $delegatedSession.ExpiresAt -gt (Get-Date))
        $items += [pscustomobject]@{
            Name = 'Sessione Microsoft Graph delegata (generale)'
            Status = if ($sessionActive) { 'OK' } else { 'Missing' }
            Detail = if ($sessionActive) { 'Attiva.' } else { "Nessuna sessione attiva su questo PC - il login non si sposta mai, va sempre rifatto dopo un riavvio o su un PC nuovo. Nota: questa e' la sessione Graph generica (utenti/gruppi/licenze), SEPARATA da quella di Exchange PowerShell - se hai gia' fatto il login delegato di Exchange (riquadro Exchange Online), questa voce puo' restare 'Missing' senza che sia un problema." }
            Fix = 'Tab Tenant -> "Accedi con il mio utente" (solo se ti serve anche questa, es. per gestire utenti/gruppi via Graph).'
        }
    }

    # Bug reale segnalato dal vivo il 21/08/2026 su un PC pulito, corretto DUE volte: la prima
    # correzione aveva migliorato solo il TESTO ("e' il default, non l'unico"), ma la LOGICA
    # restava sbagliata - continuava a controllare una sola variabile scelta in base a
    # $script:ActiveAIProvider, che e' semplicemente il valore INIZIALE del processo
    # (Server.ps1) prima che l'utente scelga mai nulla, non una preferenza reale. Correzione
    # vera, richiesta esplicitamente dall'utente ("non ci deve essere un provider di default"):
    # controlla ENTRAMBI i provider alla pari, senza trattarne nessuno come predefinito -
    # Claude e Azure OpenAI sono due alternative equivalenti, la scelta e' sempre dell'utente.
    $hasClaudeKey = [bool](Get-M365OpsSecret -Name 'ANTHROPIC_API_KEY')
    $hasAzureKey = [bool]((Get-M365OpsSecret -Name 'AZURE_OPENAI_KEY') -and (Get-M365OpsSecret -Name 'AZURE_OPENAI_ENDPOINT') -and (Get-M365OpsSecret -Name 'AZURE_OPENAI_DEPLOYMENT'))
    $items += [pscustomobject]@{
        Name = "Chiave motore AI (Claude o Azure OpenAI)"
        Status = if ($hasClaudeKey -or $hasAzureKey) { 'OK' } else { 'Missing' }
        # $script:ActiveAIProvider NON e' leggibile qui: e' una variabile di Server.ps1, questa
        # funzione vive nel modulo - il suo $script: e' un altro scope (stesso bug di scope gia'
        # visto piu' volte in questo progetto, es. isDelegated in /api/sharepoint-test).
        # Scoperto proprio scrivendo questa riga: il codice ORIGINALE di questo controllo aveva
        # lo stesso identico bug (leggeva $script:ActiveAIProvider per decidere quale DELLE DUE
        # chiavi controllare) - risultava SEMPRE $null, quindi il controllo finiva SEMPRE nel
        # ramo ANTHROPIC_API_KEY indipendentemente da quale provider fosse davvero selezionato
        # lato server. Root cause vera del "perche' solo anthropic?" originale, non solo un
        # problema di testo. Rimosso il riferimento invece di costruire un bridge (vedi
        # Get-M365OpsActiveTenantInfo per il pattern, qui non necessario): la scelta tra i due
        # resta comunque sempre dell'utente dal tab Motore AI, non serve indovinare quale sia
        # "attivo ora" per dare un'informazione corretta.
        Detail = if ($hasClaudeKey -and $hasAzureKey) { "Entrambi i provider sono configurati (Claude e Azure OpenAI) - scegli quale usare dal tab Motore AI." }
                 elseif ($hasClaudeKey) { 'Claude (Anthropic) configurato.' }
                 elseif ($hasAzureKey) { 'Azure OpenAI configurato.' }
                 else { 'Nessun motore AI configurato su questo PC - le richieste in linguaggio libero e il catalogo con RequiresAI falliranno. Scegli uno dei due provider equivalenti dal tab Motore AI (Claude/Anthropic o Azure OpenAI) e inserisci la chiave corrispondente - non c''e'' una scelta consigliata, sono alternative complete.' }
        Fix = 'Tab Motore AI -> scegli Claude o Azure OpenAI -> inserisci la chiave -> Salva.'
    }

    $npx = (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue)
    $items += [pscustomobject]@{
        Name = 'Node.js (npx, richiesto da Lokka)'
        Status = if ($npx) { 'OK' } else { 'Missing' }
        Detail = if ($npx) { 'Trovato.' } else { 'Non trovato su questo PC - non si installa da solo (dipendenza di sistema).' }
        Fix = 'Installa da nodejs.org oppure "winget install OpenJS.NodeJS", poi riavvia il server. Senza, l''AI usa comunque le cmdlet dirette come fallback.'
    }

    $edge = (Get-Command 'msedge.exe' -ErrorAction SilentlyContinue) -or (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")
    $items += [pscustomobject]@{
        Name = 'Microsoft Edge (per export PDF)'
        Status = if ($edge) { 'OK' } else { 'Missing' }
        Detail = if ($edge) { 'Trovato.' } else { 'Non trovato su questo PC - export CSV/XLSX restano disponibili, solo il PDF non funziona.' }
        Fix = 'Installa Microsoft Edge, oppure usa CSV/Excel invece di PDF per i report.'
    }

    $items
}
