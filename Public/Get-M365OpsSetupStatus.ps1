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
        $secret = Get-M365OpsSecret -Name $ctx.SecretEnvVar
        $items += [pscustomobject]@{
            Name = "Client secret ($($ctx.SecretEnvVar))"
            Status = if ($secret) { 'OK' } else { 'Missing' }
            Detail = if ($secret) { 'Impostato.' } else { "Variabile d'ambiente '$($ctx.SecretEnvVar)' non trovata su questo PC." }
            Fix = 'Tab Tenant -> campo "Valore client secret" -> Salva profilo (oppure setx e riavvia il terminale).'
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
        $delegatedSession = $script:M365OpsTokenCache[$ctx.Name].Delegated
        $sessionActive = [bool]($delegatedSession -and $delegatedSession.ExpiresAt -gt (Get-Date))
        $items += [pscustomobject]@{
            Name = 'Sessione delegata'
            Status = if ($sessionActive) { 'OK' } else { 'Missing' }
            Detail = if ($sessionActive) { 'Attiva.' } else { 'Nessuna sessione attiva su questo PC - il login non si sposta mai, va sempre rifatto dopo un riavvio o su un PC nuovo.' }
            Fix = 'Tab Tenant -> "Accedi con il mio utente".'
        }
    }

    $aiKeyVar = if ($script:ActiveAIProvider -eq 'AzureOpenAI') { 'AZURE_OPENAI_KEY' } else { 'ANTHROPIC_API_KEY' }
    $aiKey = Get-M365OpsSecret -Name $aiKeyVar
    $items += [pscustomobject]@{
        Name = "Chiave motore AI ($aiKeyVar)"
        Status = if ($aiKey) { 'OK' } else { 'Missing' }
        Detail = if ($aiKey) { 'Impostata.' } else { "Variabile d'ambiente '$aiKeyVar' non trovata su questo PC - le richieste in linguaggio libero e il catalogo con RequiresAI falliranno." }
        Fix = 'Tab Motore AI -> inserisci la chiave -> Salva.'
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
