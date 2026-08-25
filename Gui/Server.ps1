param(
    [string]$TenantProfile = "contoso-test",
    [int]$Port = 8743
)

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'M365Ops.psd1') -Force
. (Join-Path $PSScriptRoot 'CommandCatalog.ps1')
# Bug reale segnalato dal vivo il 22/08/2026 su un'installazione DAVVERO vergine (Windows
# Sandbox, Config\tenants.json mai esistito): Connect-M365Ops lancia un'eccezione se non
# trova NESSUN profilo salvato ("Nessun profilo salvato. Usa prima Set-M365OpsTenant.") - qui
# girava senza try/catch, PRIMA che il listener HTTP venga mai creato piu' sotto, quindi
# l'intero processo del server moriva all'istante, senza nemmeno aprire la porta. Da fuori
# sembrava un server "lento a rispondere" (il sintomo osservato da Launch-M365Ops.ps1 e' un
# generico "non ha risposto entro N secondi"), ma la causa vera era un crash immediato, non
# lentezza - il meccanismo di onboarding "firstRun" (GET /api/status, vedi Get-M365OpsTenantList
# poco sotto, che gia' gestiva correttamente un tenants.json assente) non poteva mai essere
# raggiunto perche' il server non arrivava mai ad aprire la porta. Questo codice non era mai
# stato esercitato prima d'ora: ogni test precedente di questa sessione partiva gia' da un PC
# con almeno un profilo tenant esistente. Corretto lasciando partire il server anche senza
# nessun tenant attivo (stato gia' previsto e gestito altrove, es. Get-M365OpsSetupStatus) -
# l'utente vedra' il messaggio di onboarding al primo caricamento della pagina.
try {
    Connect-M365Ops -TenantProfile $TenantProfile
} catch {
    Write-Host "Nessun tenant attivabile all'avvio ('$TenantProfile'): $($_.Exception.Message) - il server parte comunque, l'utente vedra' la schermata di onboarding." -ForegroundColor Yellow
}

$script:ActiveTenantProfile = $TenantProfile
$script:AiProviderConfigPath = Join-Path $moduleRoot 'Config\ai-provider.json'
$script:ActiveAIProvider = 'Claude'
if (Test-Path $script:AiProviderConfigPath) {
    try {
        $savedProvider = (Get-Content $script:AiProviderConfigPath -Raw | ConvertFrom-Json).provider
        if ($savedProvider -in @('Claude', 'AzureOpenAI')) { $script:ActiveAIProvider = $savedProvider }
    } catch {}
}
$script:LoadedFilePath = $null
$script:LoadedIconPath = $null
$script:LoadedMigrationCsvPath = $null
$script:LastGroupId = $null
$script:LastAppId = $null
$script:LastReportPath = $null
$script:PendingAction = $null

Write-M365OpsLog "Server avviato sulla porta $Port, tenant iniziale '$TenantProfile'."

# Auto-sync della guida nella Knowledge Base GLOBALE (21/08/2026, richiesto esplicitamente
# dall'utente dopo aver notato che il documento caricato restava una foto statica: ogni nuova
# modifica alla guida richiedeva un ricaricamento manuale via Add-M365OpsKnowledgeDocument,
# facile da dimenticare - prova reale: la sezione 6.4 e' stata aggiornata piu' volte in questa
# stessa sessione senza mai risincronizzare il documento gia' caricato). Ad ogni avvio del
# server, se il PDF della guida e' cambiato rispetto all'ultimo caricamento (hash SHA256
# confrontato con Config\global-kb-guide-hash.txt, non la data di modifica - piu' affidabile, un
# semplice checkout/copia puo' cambiare la data senza cambiare il contenuto), lo ricarica
# automaticamente. '_global' e' lo stesso nome riservato definito in M365Ops.psm1
# ($script:M365OpsGlobalKbName) - duplicato qui come stringa letterale perche' quella variabile
# e' nello scope del modulo, non visibile da questo script esterno (stesso principio gia' usato
# ovunque nel modulo: TenantName resta sempre una stringa opaca, mai un tipo dedicato). Avvolto
# in try/catch, non blocca mai l'avvio del server: un fallimento qui (es. provider AI non
# raggiungibile in quel momento) non deve impedire all'app di partire.
try {
    $guidePdfPath = Join-Path $moduleRoot 'docs\Guida-Configurazione.pdf'
    $guideHashPath = Join-Path $moduleRoot 'Config\global-kb-guide-hash.txt'
    if (Test-Path $guidePdfPath) {
        $currentHash = (Get-FileHash -Path $guidePdfPath -Algorithm SHA256).Hash
        $lastHash = if (Test-Path $guideHashPath) { (Get-Content $guideHashPath -Raw).Trim() } else { $null }
        if ($currentHash -ne $lastHash) {
            Write-M365OpsLog "Guida di configurazione cambiata, risincronizzo nella Knowledge Base globale..."
            Add-M365OpsKnowledgeDocument -TenantName '_global' -FilePath $guidePdfPath -OriginalFileName 'Guida-Configurazione.pdf' -Provider $script:ActiveAIProvider | Out-Null
            Set-Content -Path $guideHashPath -Value $currentHash -Encoding UTF8
            Write-M365OpsLog "Knowledge Base globale risincronizzata con la guida aggiornata."
        }
    }
} catch {
    Write-M365OpsLog "Auto-sync della guida nella Knowledge Base globale fallito (non bloccante): $($_.Exception.Message)"
}

function Get-M365OpsGroupPlanFromMessage {
    <#
    .SYNOPSIS
        Estrae nome gruppo e membro (email o nome da risolvere via Graph) da una frase
        libera. Tollerante a refusi comuni ("grupp" invece di "gruppo", "mebro" invece
        di "membro") - trovati testando l'app dal vivo, non ipotizzati a tavolino.

        Bug reale corretto: "chiamato 'X'" con virgolette SINGOLE (uso comune in chat)
        non veniva riconosciuto perche' il primo tentativo cercava solo virgolette doppie,
        e il fallback senza virgolette catturava una sola parola invece dell'intero nome.
        In assenza di "chiamato", il fallback su "gruppo di test <nome>" tentava di saltare
        la frase di contorno "di test" per arrivare al nome vero - un refuso banale tipo
        "grupp odi test" (spazio spostato di una posizione) rompeva quel salto e faceva
        catturare "odi" come se fosse il nome scelto dall'utente. Ora, se non c'e' un nome
        esplicito e affidabile da estrarre, si usa il placeholder con timestamp (onesto e
        riconoscibile come tale) invece di indovinare un frammento di frase come nome.
    #>
    param([string]$Msg)

    $groupName = "Test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    # Priorita' massima: una frase tra virgolette (singole o doppie) vicino a "gruppo" -
    # segnale forte e inequivocabile di un nome esplicito, con o senza "chiamato" prima
    # (bug reale: 'gruppo di test "NOME"' senza "chiamato" cadeva nel placeholder). Usa un
    # backreference (\1) cosi' il tipo di virgoletta di apertura e chiusura deve combaciare.
    if ($Msg -match 'grupp\w*.{0,30}?(["\x27])([^"\x27]{2,60})\1') { $groupName = $Matches[2].Trim() }
    elseif ($Msg -match 'chiamat[oa]\s+(?:"([^"]+)"|''([^'']+)'')') { $groupName = (if ($Matches[1]) { $Matches[1] } else { $Matches[2] }).Trim() }
    elseif ($Msg -match 'chiamat[oa]\s+(.+?)(?:\s*[,\.]|\s+(?:e|con|mettici|aggiungi|assegna)\b|$)') { $groupName = $Matches[1].Trim() }
    elseif ($Msg -match '\bgruppo\s+([A-Za-z0-9_-]{3,})\b') { $groupName = $Matches[1] }

    $memberUpn = $null
    $memberNote = $null
    # Il dominio non deve poter terminare con un punto letterale: altrimenti un punto di
    # fine frase subito dopo l'email (es. "...@intralab.it. assegna...") veniva incluso
    # nella cattura, producendo un UPN invalido (bug reale: 404 "diego.porcu@intralab.it.").
    if ($Msg -match '([\w\.\-]+@[\w\-]+(?:\.[\w\-]+)+)') {
        $memberUpn = $Matches[1]
    }
    elseif ($Msg -match '(?:metti|aggiungi)\s+([A-Za-zÀ-ÿ]+(?:\s+[A-Za-zÀ-ÿ]+){0,2})\s+come\s+(?:membro|mebro)') {
        $candidateName = $Matches[1].Trim()
        try { $found = @(Find-M365OpsUser -Name $candidateName) } catch { $found = @() }
        if ($found.Count -eq 1) {
            $memberUpn = $found[0].userPrincipalName
            $memberNote = "'$candidateName' risolto in $($found[0].displayName) ($memberUpn)"
        }
        elseif ($found.Count -gt 1) {
            $memberNote = "trovati piu' utenti per '$candidateName' - nessuno aggiunto, specifica l'email esatta"
        }
        else {
            $memberNote = "nessun utente trovato per '$candidateName' - gruppo creato senza membri, aggiungilo tu dopo"
        }
    }

    [pscustomobject]@{ Name = $groupName; MemberUpn = $memberUpn; MemberNote = $memberNote }
}

function Export-M365OpsDeviceReportChat {
    param([string]$FormatWord)
    $format = switch ($FormatWord) { 'excel' { 'xlsx' } 'xlsx' { 'xlsx' } 'pdf' { 'pdf' } default { 'csv' } }
    $devices = Get-M365OpsManagedDevices
    $reportsDir = Join-Path $moduleRoot 'Reports'
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
    $path = Join-Path $reportsDir "dispositivi-$(Get-Date -Format 'yyyyMMdd-HHmmss').$format"
    $realPath = Export-M365OpsReport -Data $devices -Format $format -Path $path -Title "Dispositivi Intune"
    $script:LastReportPath = $realPath
    # Ponte verso lo scope del modulo (18/08/2026, bug reale) - senza questo, un invio email
    # richiesto in un turno AI SEPARATO non troverebbe il report appena generato dal catalogo.
    Set-M365OpsLastReportPath -Path $realPath
    return "Report generato ($($devices.Count) dispositivi) - scaricalo dal pulsante qui sotto, o chiedimi di inviarlo per email."
}

function Export-M365OpsCompliancePatternsReportChat {
    param([string]$FormatWord)
    $analysisText = Get-M365OpsCompliancePatterns -Provider $script:ActiveAIProvider
    $escaped = $analysisText -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $htmlBody = "<h1>Analisi pattern di non conformita'</h1><pre style='white-space:pre-wrap; font-family:Consolas,monospace; font-size:11px;'>$escaped</pre>"
    $reportsDir = Join-Path $moduleRoot 'Reports'
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
    $path = Join-Path $reportsDir "pattern-conformita-$(Get-Date -Format 'yyyyMMdd-HHmmss').pdf"
    $realPath = Export-M365OpsReport -HtmlBody $htmlBody -Format pdf -Path $path -Title "Pattern di non conformita'"
    $script:LastReportPath = $realPath
    # Ponte verso lo scope del modulo (18/08/2026, bug reale) - senza questo, un invio email
    # richiesto in un turno AI SEPARATO non troverebbe il report appena generato dal catalogo.
    Set-M365OpsLastReportPath -Path $realPath
    return "Report generato - scaricalo dal pulsante qui sotto, o chiedimi di inviarlo per email."
}

function Export-M365OpsExoReportChat {
    param(
        [Parameter(Mandatory)] [string]$Cmdlet,
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$FileSlug,
        [string]$FormatWord
    )
    $format = switch ($FormatWord) { 'excel' { 'xlsx' } 'xlsx' { 'xlsx' } 'pdf' { 'pdf' } default { 'csv' } }
    $data = @(& $Cmdlet)
    $reportsDir = Join-Path $moduleRoot 'Reports'
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
    $path = Join-Path $reportsDir "$FileSlug-$(Get-Date -Format 'yyyyMMdd-HHmmss').$format"
    if ($data.Count -eq 0) { return "Nessun dato trovato per '$Title' - report non generato." }
    $realPath = Export-M365OpsReport -Data $data -Format $format -Path $path -Title $Title
    $script:LastReportPath = $realPath
    # Ponte verso lo scope del modulo (18/08/2026, bug reale) - senza questo, un invio email
    # richiesto in un turno AI SEPARATO non troverebbe il report appena generato dal catalogo.
    Set-M365OpsLastReportPath -Path $realPath
    return "Report generato ($($data.Count) righe) - scaricalo dal pulsante qui sotto, o chiedimi di inviarlo per email."
}

function Get-M365OpsScriptPackagePlan {
    <#
    .SYNOPSIS
        Se il file caricato per il pacchettizzamento e' uno script (.ps1/.bat/.cmd, 18/08/2026,
        richiesto esplicitamente in aggiunta a exe/msi), calcola il comando di installazione e
        determina la detection - a differenza di un exe, uno script non installa nulla in un
        percorso prevedibile (C:\Program Files\<nome>), quindi un default indovinato a caso
        sarebbe silenziosamente sbagliato. Se il file NON e' uno script, restituisce $null: il
        chiamante prosegue con la logica exe/msi gia' esistente, invariata.

        Ordine di risoluzione della detection: (1) esplicita nel messaggio dell'utente
        ("detection file ..."/"detection registro ... valore ..."), sempre prioritaria; (2) se
        assente, un tentativo di deduzione AI dal CONTENUTO dello script
        (Get-M365OpsScriptDetectionSuggestion, 19/08/2026, richiesto esplicitamente
        dall'utente) - usato solo se l'AI e' ragionevolmente sicura, e comunque mostrato
        all'utente nel testo di conferma della sequenza (mai applicato in silenzio, con nota
        "dedotto dall'AI... verificalo"); (3) se nemmeno l'AI e' sicura, si torna a chiedere
        esplicitamente all'utente come sempre fatto in precedenza.
    .OUTPUTS
        $null se il file non e' uno script.
        @{ NeedsDetectionInfo = $true; Message = "..." } se ne' il messaggio ne' l'AI hanno
        prodotto una detection affidabile - nessuna azione in sospeso viene creata, l'utente
        deve ripetere la richiesta includendola esplicitamente.
        @{ InstallCmd; DetectionMode; DetectionPath; DetectionFile; DetectionRegistryKeyPath;
           DetectionRegistryValueName; DetectionNote } se la detection e' stata trovata (fornita
        dall'utente o dedotta dall'AI - DetectionNote specifica sempre quale delle due).
    #>
    param([Parameter(Mandatory)] [string]$FilePath, [Parameter(Mandatory)] [string]$Message)

    $ext = [IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -notin @('.ps1', '.bat', '.cmd')) { return $null }

    $fileName = Split-Path -Leaf $FilePath
    $fileDetection = [regex]::Match($Message, 'detection\s+file\s+"([^"]+)"|detection\s+file\s+(\S+)')
    $regDetection = [regex]::Match($Message, 'detection\s+registro\s+(\S+)\s+valore\s+(\S+)')

    $installCmd = if ($ext -eq '.ps1') { "powershell.exe -ExecutionPolicy Bypass -File `"$fileName`"" } else { "`"$fileName`"" }

    if (-not $fileDetection.Success -and -not $regDetection.Success) {
        # Prima di chiedere all'operatore, prova una deduzione AI dal contenuto dello script
        # (19/08/2026, richiesto esplicitamente dall'utente) - SOLO se ragionevolmente sicura;
        # altrimenti procede comunque a chiedere come faceva prima di questa aggiunta. Mai
        # applicata in silenzio: la detection dedotta compare nel testo di conferma della
        # sequenza (Confermi tutta la sequenza?) PRIMA che qualunque scrittura avvenga, con una
        # nota che ne segnala chiaramente la provenienza - stesso principio gia' in uso per la
        # detection dedotta dai metadati di un exe/msi qualche riga sotto.
        $suggestion = $null
        try { $suggestion = Get-M365OpsScriptDetectionSuggestion -FilePath $FilePath -Provider $script:ActiveAIProvider } catch {}

        if ($suggestion -and $suggestion.confident -and $suggestion.DetectionMode -eq 'FileExists' -and $suggestion.DetectionFile) {
            return @{
                InstallCmd = $installCmd
                DetectionMode = 'FileExists'
                DetectionPath = $suggestion.DetectionPath
                DetectionFile = $suggestion.DetectionFile
                DetectionNote = "file marker $($suggestion.DetectionPath)\$($suggestion.DetectionFile) (dedotto dall'AI dal contenuto dello script: $($suggestion.explanation) - verificalo)"
            }
        }
        if ($suggestion -and $suggestion.confident -and $suggestion.DetectionMode -eq 'RegistryExists' -and $suggestion.DetectionRegistryKeyPath) {
            return @{
                InstallCmd = $installCmd
                DetectionMode = 'RegistryExists'
                DetectionRegistryKeyPath = $suggestion.DetectionRegistryKeyPath
                DetectionRegistryValueName = $suggestion.DetectionRegistryValueName
                DetectionNote = "registro $($suggestion.DetectionRegistryKeyPath) valore $($suggestion.DetectionRegistryValueName) (dedotto dall'AI dal contenuto dello script: $($suggestion.explanation) - verificalo)"
            }
        }

        $unsureNote = if ($suggestion -and $suggestion.explanation) { " (l'AI ha provato a dedurla dal contenuto dello script ma non era ragionevolmente sicura: $($suggestion.explanation))" } else { "" }
        return @{
            NeedsDetectionInfo = $true
            Message = "Per uno script ($ext) non posso dedurre la detection con sicurezza$unsureNote - indicami UNA delle due cose che lo script stesso crea/imposta quando ha successo, aggiungendola alla richiesta:`n- ``detection file <percorso completo del marker>`` (es. ``detection file C:\ProgramData\MiaApp\installed.txt``)`n- ``detection registro <percorso chiave> valore <nome valore>`` (es. ``detection registro HKLM:\SOFTWARE\MiaApp valore Version``)"
        }
    }

    if ($fileDetection.Success) {
        $markerPath = if ($fileDetection.Groups[1].Success) { $fileDetection.Groups[1].Value } else { $fileDetection.Groups[2].Value }
        return @{
            InstallCmd = $installCmd
            DetectionMode = 'FileExists'
            DetectionPath = Split-Path -Parent $markerPath
            DetectionFile = Split-Path -Leaf $markerPath
            DetectionNote = "file marker $markerPath (fornito dall'utente, non dedotto)"
        }
    }

    return @{
        InstallCmd = $installCmd
        DetectionMode = 'RegistryExists'
        DetectionRegistryKeyPath = $regDetection.Groups[1].Value
        DetectionRegistryValueName = $regDetection.Groups[2].Value
        DetectionNote = "registro $($regDetection.Groups[1].Value) valore $($regDetection.Groups[2].Value) (fornito dall'utente, non dedotto)"
    }
}

function Get-M365OpsTenantList {
    $configPath = Join-Path $moduleRoot 'Config\tenants.json'
    if (-not (Test-Path $configPath)) { return @() }
    $raw = Get-Content $configPath -Raw | ConvertFrom-Json
    $list = @()
    foreach ($prop in $raw.PSObject.Properties) {
        # Campi aggiunti il 26/08/2026 (richiesto dall'utente: "aggiungi/aggiorna profilo non
        # fa capire come modificare un profilo esistente come vnsys") - servono a precompilare
        # il form di modifica in GUI senza dover far riscrivere all'utente Tenant ID/Client
        # ID/UPN/thumbprint a memoria. Il VALORE del secret non e' mai incluso qui: non e'
        # nemmeno salvato in tenants.json (solo il NOME della variabile d'ambiente lo e', vedi
        # Set-M365OpsTenant), coerente col principio "il secret non tocca mai un file" gia'
        # documentato nella pagina.
        $list += [pscustomobject]@{
            name                   = $prop.Name
            tenantId               = $prop.Value.TenantId
            authMode               = if ($prop.Value.AuthMode) { $prop.Value.AuthMode } else { 'AppOnly' }
            clientId               = $prop.Value.ClientId
            secretEnvVar           = $prop.Value.SecretEnvVar
            delegatedUpn           = $prop.Value.DelegatedUpn
            exchangeCertThumbprint = $prop.Value.ExchangeCertThumbprint
        }
    }
    return $list
}

function Complete-M365OpsWriteResponse {
    <#
        Helper condiviso (27/08/2026, richiesto esplicitamente dall'utente: "scrivi anche il
        comando ps che sta per lanciare... l'importante che si sappia"): dato il risultato
        gia' pronto di una scrittura riuscita, (1) logga l'evento nel log scritture separato
        (Write-M365OpsWriteLog, Logs\writes-YYYYMMDD.log) e (2) aggiunge in coda al testo
        mostrato in chat un trailer "_Fonte: ... Comando eseguito: ..._" - stesso principio
        gia' in uso per "Fonte dati" nelle risposte dell'AI (Invoke-M365OpsAgentTools.ps1),
        ma qui per il turno di ESECUZIONE deterministica (dopo "si"), che prima non lo aveva
        mai (Execute-PendingAction non passa mai dall'AI, quindi quel meccanismo non
        scattava). Un helper unico invece di ripetere le stesse 3 righe in ogni case sotto.
    #>
    param(
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$BaseText,
        [Parameter(Mandatory)] [string]$CommandText
    )
    $isDelegated = (Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated'
    $source = Get-M365OpsWriteActionSourceLabel -Type $Type -IsDelegatedTenant $isDelegated
    Write-M365OpsWriteLog -Source $source -Command $CommandText -Outcome 'OK'
    @{ role = 'system'; text = "$BaseText`n`n_Fonte: $source. Comando eseguito: $CommandText._" }
}

function Write-M365OpsWriteFailureIfNeeded {
    <#
        Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore): il blocco catch generico
        di Execute-PendingAction (sotto) e' l'UNICO punto che logga un fallimento nel log
        scritture separato - ma parecchi case (LokkaWrite quando Graph rifiuta con un 400/403
        restituito come risultato normale del tool anziche' come eccezione PowerShell,
        CliM365Write con lo stesso schema, PackageApp/AssignApp quando una dipendenza/gruppo/
        app non si risolve) uscivano con un `return @{ role = 'error'; ... }` diretto, MAI
        un'eccezione - quel `catch` non scatta mai per questi casi, quindi restano
        sistematicamente assenti dal log scritture nonostante siano fallimenti di scrittura
        reali e quotidiani (non casi limite). Invece di aggiungere la stessa chiamata di log in
        ognuno dei ~10 punti di return sparsi nei vari case (rischio concreto di dimenticarne
        uno futuro), il controllo vive qui, UNA volta, richiamato dai due punti che invocano
        Execute-PendingAction (single-azione e coda) subito dopo aver ricevuto il risultato -
        cosi' resta corretto per costruzione anche per un case nuovo aggiunto in futuro che
        dimenticasse di loggare da solo.
    #>
    param($Action, $Result)
    if (-not $Result -or $Result.role -notin @('error', 'ai')) { return }
    # 'ai' capita quando un fallimento passa dalla diagnosi/correzione AI (Invoke-M365OpsErrorTriage)
    # invece di un semplice errore - e' comunque un fallimento della scrittura originale, va
    # loggato come tale (stesso principio gia' in uso in Execute-PendingQueue per decidere se
    # fermare la sequenza, vedi il commento li').
    if ($Action.Type -in @('RestartServer', 'NewCustomScript', 'ApplyFix', 'Queue')) { return }
    try {
        $failCmdText =
            if ($Action.Cmdlet) { Format-M365OpsCommandLine -Cmdlet $Action.Cmdlet -Parameters $(if ($Action.Parameters) { $Action.Parameters } else { @{} }) }
            elseif ($Action.Method -and $Action.Path) { "$($Action.Method.ToUpper()) $($Action.Path)" }
            elseif ($Action.Command) { "m365 $($Action.Command)" }
            else { $Action.Type }
        $failSource = Get-M365OpsWriteActionSourceLabel -Type $Action.Type -IsDelegatedTenant ((Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated')
        Write-M365OpsWriteLog -Source $failSource -Command $failCmdText -Outcome 'FAIL' -Detail $Result.text
    } catch { }
}

function Execute-PendingAction {
    param($action)
    Write-M365OpsLog "Esecuzione azione confermata: Type=$($action.Type) Cmdlet=$($action.Cmdlet)"
    try {
        switch ($action.Type) {
            'CreateGroup' {
                $params = @{ DisplayName = $action.Name }
                if ($action.MemberUpn) { $params.MemberUpn = @($action.MemberUpn) }
                $group = New-M365OpsGroup @params
                $script:LastGroupId = $group.id
                # Un fallimento su un singolo membro non fa fallire piu' New-M365OpsGroup
                # (vedi il suo .SYNOPSIS) - il gruppo e' comunque stato creato, va riportato
                # come successo con un avviso, non trattato come un errore totale che
                # innescherebbe un retry e un secondo gruppo duplicato.
                $memberNote = if ($group.MemberErrors) { "`nAttenzione: alcuni membri non sono stati aggiunti - " + ($group.MemberErrors -join '; ') } else { "" }
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto. Gruppo creato: $($group.displayName) ($($group.id))$memberNote" -CommandText (Format-M365OpsCommandLine -Cmdlet 'New-M365OpsGroup' -Parameters $params)
            }
            'PackageApp' {
                $uninstallCmd = if ($action.UninstallCmd) { $action.UninstallCmd } else { "REM disinstallazione da definire manualmente" }
                $packageParams = @{
                    ExePath = $script:LoadedFilePath; DisplayName = $action.DisplayName; Publisher = $action.Publisher
                    InstallCommandLine = $action.InstallCmd; UninstallCommandLine = $uninstallCmd
                    DetectionMode = if ($action.DetectionMode) { $action.DetectionMode } else { 'Version' }
                    DetectionPath = $action.DetectionPath; DetectionFile = $action.DetectionFile; DetectionVersion = $action.DetectionVersion
                    DetectionRegistryKeyPath = $action.DetectionRegistryKeyPath; DetectionRegistryValueName = $action.DetectionRegistryValueName
                }
                if ($script:LoadedIconPath -and (Test-Path $script:LoadedIconPath)) { $packageParams.IconPath = $script:LoadedIconPath }
                # Personalizzazioni avanzate (19/08/2026) - passate solo se presenti su $action,
                # cosi' un packaging senza personalizzazioni resta identico a prima di questa
                # aggiunta. ScopeTagNames/ReturnCodes hanno nomi diversi lato New-M365OpsWin32App
                # (ScopeTagNames/ReturnCodes), gli altri combaciano 1:1.
                foreach ($advKey in @('MinimumFreeDiskSpaceInMB', 'MinimumMemoryInMB', 'MinimumNumberOfProcessors', 'MinimumCPUSpeedInMHz', 'InstallExperience', 'DeviceRestartBehavior', 'MaximumInstallationTimeInMinutes', 'ScopeTagNames', 'ReturnCodes')) {
                    if ($null -ne $action.$advKey) { $packageParams[$advKey] = $action.$advKey }
                }
                if ($action.AllowAvailableUninstall) { $packageParams.AllowAvailableUninstall = $true }

                # Dipendenza/supersedence per NOME (19/08/2026): risolti QUI in un id reale via
                # lettura Graph, mai indovinati - se il nome non corrisponde a nessuna app
                # esistente (o a piu' di una), la scrittura si ferma con un errore chiaro
                # invece di procedere su un id sbagliato o ambiguo.
                if ($action.DependsOnAppName) {
                    $depMatches = @(Invoke-M365OpsGraphRequest -Method GET -Path "/deviceAppManagement/mobileApps?`$filter=contains(displayName,'$($action.DependsOnAppName -replace "'", "''")')" -Beta).value
                    if ($depMatches.Count -ne 1) { return @{ role = 'error'; text = "Impossibile risolvere l'app da cui dipende '$($action.DisplayName)': '$($action.DependsOnAppName)' trova $($depMatches.Count) app corrispondenti in Intune (serve esattamente 1). Pacchettizzazione NON eseguita - correggi il nome e riprova." } }
                    $packageParams.DependsOn = @(@{ Id = $depMatches[0].id; Type = $action.DependencyType })
                }
                if ($action.SupersedesAppName) {
                    $supMatches = @(Invoke-M365OpsGraphRequest -Method GET -Path "/deviceAppManagement/mobileApps?`$filter=contains(displayName,'$($action.SupersedesAppName -replace "'", "''")')" -Beta).value
                    if ($supMatches.Count -ne 1) { return @{ role = 'error'; text = "Impossibile risolvere l'app sostituita da '$($action.DisplayName)': '$($action.SupersedesAppName)' trova $($supMatches.Count) app corrispondenti in Intune (serve esattamente 1). Pacchettizzazione NON eseguita - correggi il nome e riprova." } }
                    $packageParams.Supersedes = @(@{ Id = $supMatches[0].id; Type = $action.SupersedenceType })
                }

                $app = New-M365OpsWin32App @packageParams
                $script:LastAppId = $app.id
                $iconNote = if ($packageParams.IconPath) { " Icona applicata." } else { " Nessuna icona caricata (ne uso una generica di default)." }
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto, NON assegnata. App creata: $($app.displayName) ($($app.id)).$iconNote" -CommandText (Format-M365OpsCommandLine -Cmdlet 'New-M365OpsWin32App' -Parameters $packageParams)
            }
            'AssignApp' {
                # AppId/GroupId possono arrivare gia' valorizzati (flusso singolo) oppure
                # essere risolti ora da $script:Last... (flusso a coda: il gruppo/app appena
                # creati nello stesso batch non erano ancora noti quando e' stato costruito il piano).
                $appId = if ($action.AppId) { $action.AppId } else { $script:LastAppId }
                if (-not $appId) { return @{ role = 'error'; text = "Nessuna app disponibile da assegnare." } }
                $groupId = if ($action.AllDevices) { $null } elseif ($action.GroupId) { $action.GroupId } else { $script:LastGroupId }
                if (-not $action.AllDevices -and -not $groupId) { return @{ role = 'error'; text = "Nessun gruppo disponibile per l'assegnazione." } }

                $params = @{ AppId = $appId; Intent = $action.Intent }
                if ($groupId) { $params.TargetGroupId = $groupId }
                # Parametri avanzati (19/08/2026, richiesti esplicitamente dall'utente) - passati
                # solo se presenti su $action, cosi' il flusso composto a coda esistente (che non
                # li valorizza mai) continua a funzionare esattamente come prima, invariato.
                foreach ($advKey in @('FilterId', 'FilterType', 'NotificationMode', 'RestartGracePeriodMinutes', 'RestartCountdownDisplayMinutes', 'RestartSnoozeDurationMinutes', 'AvailableDateTime', 'DeadlineDateTime', 'DeliveryOptimizationPriority')) {
                    if ($null -ne $action.$advKey -and $action.$advKey -ne '') { $params[$advKey] = $action.$advKey }
                }
                Set-M365OpsAppAssignment @params
                $scope = if ($groupId) { "il gruppo" } else { "tutti i dispositivi" }
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto. Assegnata come '$($action.Intent)' a $scope." -CommandText (Format-M365OpsCommandLine -Cmdlet 'Set-M365OpsAppAssignment' -Parameters $params)
            }
            'LokkaWrite' {
                $writeError = $null
                try {
                    if ((Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated') {
                        # Lokka non e' mai disponibile in modalita' delegata - stessa chiamata
                        # REST ma con il token delegato usato dal resto del modulo.
                        $graphResult = Invoke-M365OpsGraphRequest -Method $action.Method.ToUpper() -Path $action.Path -Body $action.Body
                        $resultText = ($graphResult | ConvertTo-Json -Depth 8 -Compress)
                    } else {
                        $lokkaArgs = @{ apiType = "graph"; method = $action.Method; path = $action.Path }
                        if ($action.Body) { $lokkaArgs.body = $action.Body }
                        $lokkaResult = Invoke-M365OpsLokkaTool -ToolName "Lokka-Microsoft" -Arguments $lokkaArgs
                        $resultText = ($lokkaResult.content | ForEach-Object { $_.text }) -join "`n"
                        # Bug reale (17/08/2026): Lokka non lancia un'eccezione PowerShell
                        # quando Graph rifiuta la richiesta (es. 403/400) - restituisce
                        # l'errore come normale risultato del tool, dentro $resultText.
                        try {
                            $parsedResult = $resultText | ConvertFrom-Json -ErrorAction Stop
                            if ($parsedResult.statusCode -ge 400 -or $parsedResult.error) { $writeError = $resultText }
                        } catch { }
                    }
                }
                catch {
                    $writeError = $_.Exception.Message
                }

                if (-not $writeError) {
                    $lokkaCmdText = "$($action.Method.ToUpper()) $($action.Path)"
                    if ($action.Body) { $lokkaCmdText += " " + ($action.Body | ConvertTo-Json -Depth 6 -Compress) }
                    return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText $lokkaCmdText
                }

                # Bug reale corretto il 17/08/2026 (Lokka non lanciava eccezione su errore Graph
                # - "Fatto." veniva mostrato comunque) e migliorato il 18/08/2026 (richiesta
                # esplicita dell'utente): invece di limitarsi a mostrare l'errore grezzo, chiedi
                # all'AI se il messaggio di Graph indica chiaramente come correggere il corpo
                # della richiesta (es. "serve una password" -> l'AI ne genera una temporanea).
                # MAI eseguita in automatico: se l'AI propone una correzione, torna una NUOVA
                # proposta con conferma esplicita separata, stesso principio di ogni scrittura -
                # una correzione automatica del corpo non significa eseguirla senza supervisione.
                $recovery = $null
                try {
                    $recovery = Invoke-M365OpsWriteRecovery -Method $action.Method -Path $action.Path -Body $action.Body -ErrorMessage $writeError -Reason $action.Reason -Provider $script:ActiveAIProvider
                } catch { }

                if ($recovery -and $recovery.canFix -and $recovery.correctedBody) {
                    $bodyText = ($recovery.correctedBody | ConvertTo-Json -Depth 6 -Compress)
                    $confirmText = "La scrittura e' fallita: $writeError`n`nL'AI propone una correzione: $($recovery.explanation)`n`n--- Scrittura corretta proposta (non ancora eseguita) ---`nMetodo: $($action.Method.ToUpper())`nPercorso: $($action.Path)`nCorpo: $bodyText"
                    $script:PendingAction = @{ Type = 'LokkaWrite'; Method = $action.Method; Path = $action.Path; Body = $recovery.correctedBody; Reason = $action.Reason; ConfirmText = $confirmText }
                    return @{ role = 'ai'; text = "$confirmText`n`n(rispondi 'si' per eseguirla con la correzione, 'no' per annullare)" }
                }

                $noFixNote = if ($recovery) { " (l'AI ha provato a proporre una correzione ma non era ragionevolmente sicura: $($recovery.explanation))" } else { "" }
                return @{ role = 'error'; text = "La scrittura NON e' andata a buon fine.$noFixNote`n$writeError" }
            }
            'CliM365Write' {
                # Nessun meccanismo di correzione automatica (a differenza di 'LokkaWrite',
                # che lo ha per gli errori Graph tipici) - se il comando fallisce, l'errore
                # grezzo di CLI Microsoft 365 torna cosi' com'e' all'utente, che puo' chiedere
                # una correzione in chat come per qualunque altro errore.
                $writeError = $null
                try {
                    $cliResult = Invoke-M365OpsMcpServerTool -ServerName 'CLI-Microsoft365' -ToolName "m365_run_command" -Arguments @{ command = $action.Command }
                    $resultText = ($cliResult.content | ForEach-Object { $_.text }) -join "`n"
                } catch {
                    $writeError = $_.Exception.Message
                }

                if (-not $writeError) {
                    return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText "m365 $($action.Command)"
                }
                return @{ role = 'error'; text = "Il comando CLI Microsoft 365 NON e' andato a buon fine.`n$writeError" }
            }
            'ExoWrite' {
                $params = @{}
                if ($action.Parameters) { $action.Parameters.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
                $cmdletName = $action.Cmdlet
                # Invoke-M365OpsWriteWithIsolationRecovery (26/08/2026, bug reale trovato dal
                # vivo): il conflitto .NET di sezione 6.6 puo' manifestarsi anche DOPO una
                # connessione Exchange/Teams gia' riuscita, su una scrittura specifica - non
                # solo al momento del connect (gia' coperto da Connect-M365OpsExchange.ps1).
                # Vedi quel file per il dettaglio completo del bug e del retry.
                $exoResult = Invoke-M365OpsWriteWithIsolationRecovery -ModuleType 'Exchange' -Action { & $cmdletName @params }
                $resultText = ($exoResult | ConvertTo-Json -Depth 6 -Compress)
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText (Format-M365OpsCommandLine -Cmdlet $action.Cmdlet -Parameters $params)
            }
            'CustomWrite' {
                $params = @{}
                if ($action.Parameters) { $action.Parameters.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
                $customResult = & $action.Cmdlet @params
                $resultText = ($customResult | ConvertTo-Json -Depth 6 -Compress)
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText (Format-M365OpsCommandLine -Cmdlet $action.Cmdlet -Parameters $params)
            }
            'SharePointWrite' {
                $params = @{}
                if ($action.Parameters) { $action.Parameters.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
                $spResult = & $action.Cmdlet @params
                $resultText = ($spResult | ConvertTo-Json -Depth 6 -Compress)
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText (Format-M365OpsCommandLine -Cmdlet $action.Cmdlet -Parameters $params)
            }
            'TeamsWrite' {
                $params = @{}
                if ($action.Parameters) { $action.Parameters.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
                $cmdletName = $action.Cmdlet
                # Invoke-M365OpsWriteWithIsolationRecovery (26/08/2026, bug reale trovato dal
                # vivo: Set-Team fallito con "Method not found: 'Void Microsoft.Identity.
                # Client.ITokenCache.Deserialize(Byte[])'." SU UNA SCRITTURA, con Teams ed
                # Exchange gia' connessi entrambi con successo in precedenza - il conflitto di
                # sezione 6.6 puo' quindi manifestarsi anche dopo un connect riuscito, non
                # solo durante. Vedi quel file per il dettaglio completo del bug e del retry.
                $teamsResult = Invoke-M365OpsWriteWithIsolationRecovery -ModuleType 'Teams' -Action { & $cmdletName @params }
                $resultText = ($teamsResult | ConvertTo-Json -Depth 6 -Compress)
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText (Format-M365OpsCommandLine -Cmdlet $action.Cmdlet -Parameters $params)
            }
            'IntuneWrite' {
                $params = @{}
                if ($action.Parameters) { $action.Parameters.GetEnumerator() | ForEach-Object { $params[$_.Key] = $_.Value } }
                $intuneResult = & $action.Cmdlet @params
                $resultText = ($intuneResult | ConvertTo-Json -Depth 6 -Compress)
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto.`n$resultText" -CommandText (Format-M365OpsCommandLine -Cmdlet $action.Cmdlet -Parameters $params)
            }
            'MfaReset' {
                $mfaResult = Reset-M365OpsUserMfa -Upn $action.Upn
                if ($mfaResult.Failed.Count -gt 0) {
                    $failText = "`nAlcuni metodi NON sono stati rimossi: $($mfaResult.Failed -join '; ')"
                } else { $failText = "" }
                $removedText = if ($mfaResult.Removed.Count -gt 0) { $mfaResult.Removed -join ', ' } else { "(nessun metodo MFA era registrato)" }
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto. Metodi MFA rimossi per $($action.Upn): $removedText$failText" -CommandText (Format-M365OpsCommandLine -Cmdlet 'Reset-M365OpsUserMfa' -Parameters @{ Upn = $action.Upn })
            }
            'SendReportEmail' {
                if (-not $action.AttachmentPath -or -not (Test-Path $action.AttachmentPath)) {
                    return @{ role = 'error'; text = "Il file del report non e' piu' presente su disco - genera di nuovo il report e riprova." }
                }
                $emailResult = Send-M365OpsReportEmail -To $action.To -AttachmentPath $action.AttachmentPath -Subject $action.Subject -Body $action.Body
                return Complete-M365OpsWriteResponse -Type $action.Type -BaseText "Fatto. $emailResult" -CommandText (Format-M365OpsCommandLine -Cmdlet 'Send-M365OpsReportEmail' -Parameters @{ To = $action.To; Subject = $action.Subject; AttachmentPath = (Split-Path -Leaf $action.AttachmentPath) })
            }
            'RestartServer' {
                # Confermato dall'utente in risposta al suggerimento automatico sotto (catch
                # del conflitto di assembly .NET) - stessa infrastruttura di riavvio sicuro
                # del pulsante GUI/POST /api/restart, agisce solo dopo l'invio di questa risposta.
                $script:RestartRequested = $true
                return @{ role = 'system'; text = "Riavvio in corso - riprova l'azione appena il server e' di nuovo raggiungibile (qualche secondo)." }
            }
            'NewCustomScript' {
                # Validazione ripetuta qui (difesa in profondita', non ci si fida del solo
                # controllo gia' fatto lato dispatch AI in Invoke-M365OpsAgentTools): percorso
                # sicuro dentro Scripts\Custom, nessuna sovrascrittura silenziosa di uno script
                # gia' esistente (potrebbe essere stato creato nel frattempo da un altro turno).
                if ($action.Name -notmatch '^[A-Z][a-zA-Z]*-M365Ops[A-Za-z0-9]+$') {
                    return @{ role = 'error'; text = "Nome script non valido: '$($action.Name)' - non salvato." }
                }
                $scriptPath = Join-Path $moduleRoot "Scripts\Custom\$($action.Name).ps1"
                if (Test-Path $scriptPath) {
                    return @{ role = 'error'; text = "Esiste gia' uno script chiamato '$($action.Name)' - non sovrascritto. Chiedi di usare un nome diverso." }
                }
                Set-Content -Path $scriptPath -Value $action.Code -Encoding UTF8
                Write-M365OpsLog "Nuovo script personalizzato salvato: $($action.Name).ps1 [$($action.Mode)]"
                # Stessa infrastruttura di riavvio sicuro del pulsante GUI/POST /api/restart
                # (sezione 12.2 della guida): agisce solo DOPO che questa risposta e' gia' stata
                # inviata, quindi l'utente vede sempre prima la conferma di cosa e' successo.
                $script:RestartRequested = $true
                return @{ role = 'system'; text = "Fatto. Script '$($action.Name)' ($($action.Mode)) salvato in Scripts\Custom\$($action.Name).ps1. Il server si riavvia ora per caricarlo - sara' uno strumento vero, disponibile all'AI dal prossimo messaggio." }
            }
            default {
                return @{ role = 'error'; text = "Azione sconosciuta." }
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-M365OpsLog "Azione fallita: Type=$($action.Type) Errore=$errorMessage" -Level Error

        # Log scritture separato: la chiamata dedicata viveva QUI fino al 23/08/2026 (bug-hunt
        # di 16 ore) - rimossa perche' duplicava un log gia' scritto altrove. Da quando esiste
        # Write-M365OpsWriteFailureIfNeeded (helper condiviso, vedi la sua definizione sopra
        # Execute-PendingAction), quella funzione viene chiamata nei DUE punti che invocano
        # Execute-PendingAction (esecuzione singola e coda) SUBITO dopo aver ricevuto il
        # risultato - copre quindi GIA' anche il caso di questo blocco catch (il risultato che
        # arriva la' fuori ha comunque role='error', l'unico segnale di cui quell'helper ha
        # bisogno). Tenere ANCHE una chiamata qui avrebbe scritto ogni fallimento con eccezione
        # DUE VOLTE nel log scritture (bug reale trovato durante l'autoreview di questa stessa
        # maratona) - un secondo agente di revisione, non un test dal vivo, ha individuato il
        # doppione confrontando i due punti di logging fianco a fianco.

        # Rilevamento deterministico del conflitto di assembly .NET diagnosticato dal vivo il
        # 18/08/2026 (0x80131040, "Could not load file or assembly... manifest definition does
        # not match the assembly reference"): capita dopo che il processo server ha usato
        # troppi moduli PowerShell pesanti diversi (Graph, PnP, MicrosoftTeams,
        # ExchangeOnlineManagement, Purview/IPPS) nella stessa sessione lunga - non e' un bug
        # nel codice di M365Ops, isolato e confermato riproducendo la STESSA scrittura in un
        # processo fresco (riuscita) e nel processo reale prima/dopo un riavvio (fallita poi
        # riuscita). Intercettato QUI, prima della diagnosi AI generica (che non conosce questa
        # causa specifica e propone un'indagine approfondita inutile) - risposta immediata,
        # deterministica, sempre corretta per questo pattern esatto, con un riavvio proponibile
        # con un click invece di dover andare a cercarlo nel tab Manutenzione.
        if ($errorMessage -match 'Could not load file or assembly|0x80131040|assembly.{0,40}manifest definition does not match') {
            $confirmText = "Scrittura fallita per un conflitto tra i moduli PowerShell caricati in questa sessione del server (Graph/PnP/Teams/Exchange/Purview usati insieme in un processo lungo) - non e' un problema dei dati o dei permessi. Il riavvio del server risolve in modo affidabile (verificato dal vivo): apre un processo pulito, la scrittura poi funziona normalmente. Vuoi che riavvii ora?"
            $script:PendingAction = @{ Type = 'RestartServer'; ConfirmText = $confirmText }
            return @{ role = 'ai'; text = "$confirmText`n(rispondi 'si' per riavviare, 'no' per lasciare com'e')" }
        }

        # Se l'azione e' stata costruita da testo libero con estrazione a regex (non AI) ed
        # e' fallita, primo tentativo prima di arrendersi: chiedere all'AI di rileggere il
        # messaggio originale e proporre parametri corretti, poi riprovare UNA volta - pensato
        # per errori di ESTRAZIONE testuale (es. il 404 del 15/08/2026: email con un punto di
        # troppo incluso per errore dal regex), non per bug di codice (quelli restano gestiti
        # dalla diagnosi/proposta di fix sotto, raggiunta comunque se il retry fallisce di
        # nuovo). Il tentativo e la sua motivazione vengono sempre mostrati all'utente nel
        # testo finale, mai fatti in silenzio. Scope limitato a CreateGroup per ora: e' l'unico
        # caso dove un'estrazione di testo sbagliata (nome/email) spiega davvero il
        # fallimento - PackageApp/AssignApp falliscono quasi sempre per motivi esterni
        # (pipeline Intune, permessi) che rileggere il messaggio non puo' correggere.
        $recoveryPrefix = ""
        if ($action.OriginalMessage -and $action.Type -eq 'CreateGroup') {
            $paramsForRecovery = @{ Name = $action.Name; MemberUpn = $action.MemberUpn }
            $lines = @("Primo tentativo fallito: $errorMessage", "", "Chiedo all'AI di rivedere il messaggio originale prima di arrendermi...")
            $recovery = $null
            try {
                $recovery = Invoke-M365OpsActionRecovery -ActionType $action.Type -Parameters $paramsForRecovery -ErrorMessage $errorMessage -OriginalMessage $action.OriginalMessage -Provider $script:ActiveAIProvider
            } catch { }

            if ($recovery -and $recovery.canFix -and $recovery.correctedParameters) {
                $lines += "AI: $($recovery.explanation)"
                $lines += "Riprovo con i parametri corretti..."

                $retryAction = $action.Clone()
                $retryAction.Remove('OriginalMessage')
                $recovery.correctedParameters.PSObject.Properties | Where-Object { $paramsForRecovery.ContainsKey($_.Name) } | ForEach-Object { $retryAction[$_.Name] = $_.Value }

                $retryResult = Execute-PendingAction $retryAction
                return @{ role = $retryResult.role; text = (($lines -join "`n") + "`n`n" + $retryResult.text) }
            }

            $lines += if ($recovery) { "AI: $($recovery.explanation)" } else { "Non sono riuscito a ottenere una correzione dall'AI." }
            $recoveryPrefix = ($lines -join "`n") + "`n`n"
        }

        # Non solo mostro l'errore: lo mando all'AI per capire se e' transitorio,
        # se serve una decisione tua, o se e' un bug con una correzione proponibile.
        # Vale anche per LokkaWrite/ExoWrite/CustomWrite - uno script "home made" ha piu'
        # probabilita' di avere bug reali di una cmdlet del modulo, quindi conviene ancora
        # di piu' passare da qui invece che da un semplice messaggio di errore piatto.
        $context = "Azione: $($action.Type). Parametri: $($action | ConvertTo-Json -Depth 3 -Compress)"
        $sourceFile = switch ($action.Type) {
            'CreateGroup' { Join-Path $moduleRoot 'Public\New-M365OpsGroup.ps1' }
            'PackageApp'  { Join-Path $moduleRoot 'Public\New-M365OpsWin32App.ps1' }
            'AssignApp'   { Join-Path $moduleRoot 'Public\Set-M365OpsAppAssignment.ps1' }
            'ExoWrite'        { if ($action.Cmdlet) { Join-Path $moduleRoot "Public\$($action.Cmdlet).ps1" } else { $null } }
            'CustomWrite'     { if ($action.Cmdlet) { Join-Path $moduleRoot "Scripts\Custom\$($action.Cmdlet).ps1" } else { $null } }
            'SharePointWrite' { if ($action.Cmdlet) { Join-Path $moduleRoot "Public\$($action.Cmdlet).ps1" } else { $null } }
            'TeamsWrite'      { if ($action.Cmdlet) { Join-Path $moduleRoot "Public\$($action.Cmdlet).ps1" } else { $null } }
            'IntuneWrite'     { if ($action.Cmdlet) { Join-Path $moduleRoot "Public\$($action.Cmdlet).ps1" } else { $null } }
            'MfaReset'    { Join-Path $moduleRoot 'Public\Reset-M365OpsUserMfa.ps1' }
            default       { $null }
        }
        $triage = Invoke-M365OpsErrorTriage -ErrorMessage $errorMessage -Context $context -SourceFile $sourceFile -Provider $script:ActiveAIProvider
        $text = $recoveryPrefix + (Format-M365OpsErrorTriage $triage)

        if (Test-M365OpsFixApplicable $triage $moduleRoot) {
            $script:PendingAction = @{ Type = 'ApplyFix'; Triage = $triage; ConfirmText = $text }
        }
        # Nota sorgente (24/08/2026, stesso principio del catalogo comandi sopra): questo e' un
        # percorso di diagnosi/correzione di una scrittura fallita, l'IA viene davvero
        # interpellata (Invoke-M365OpsErrorTriage, e Invoke-M365OpsActionRecovery quando
        # $recoveryPrefix e' popolato) - mai stato reso esplicito prima d'ora.
        $text += "`n`n_Fonte: diagnosi errore con analisi IA. Elaborata da IA: $(Get-M365OpsAiProviderLabel -Provider $script:ActiveAIProvider)._"
        return @{ role = 'ai'; text = $text }
    }
}

function Execute-PendingQueue {
    param($queue)
    $outputs = @()
    foreach ($action in $queue) {
        $result = Execute-PendingAction $action
        Write-M365OpsWriteFailureIfNeeded -Action $action -Result $result
        $outputs += $result.text
        # role='ai' capita quando un passo fallisce e passa dalla diagnosi/correzione AI
        # (Invoke-M365OpsErrorTriage) invece di un semplice errore - anche in quel caso il
        # passo NON e' riuscito: i passi successivi della sequenza dipendono tipicamente da
        # quello (es. assegnare un'app che non e' stata creata), quindi ci si ferma comunque
        # invece di procedere alla cieca. Bug reale: prima si fermava solo su role='error'.
        if ($result.role -ne 'system') {
            $outputs += "Interrotto il resto della sequenza per il problema sopra."
            return @{ role = $result.role; text = ($outputs -join "`n`n") }
        }
    }
    return @{ role = 'system'; text = ($outputs -join "`n`n") }
}

function Handle-ChatMessage {
    param([string]$Message)

    $msg = $Message.Trim()
    # $lower e' SOLO per il matching locale (catalogo + si/no) - normalizzato per assorbire il
    # rumore meccanico piu' comune (apostrofi doppi, abbreviazioni SMS come "nn"/"sn"), MAI il
    # testo originale $msg che va all'AI o nello storico: l'utente deve rivedere quello che ha
    # scritto per davvero, e l'AI gestisce gia' bene da sola i refusi veri (bug-hunt 19/08/2026).
    $lower = Get-M365OpsNormalizedChatText -Text $msg.ToLower()
    Write-M365OpsLog "Messaggio ricevuto: $msg"

    if ($script:PendingAction) {
        # Bug reale trovato dal vivo il 23/08/2026 (bug-hunt di 16 ore) - SICUREZZA, non
        # cosmetico: il vecchio controllo era '^(si|...)\b', ancorato SOLO all'inizio della
        # stringa, quindi un normalissimo "si" italiano come pronome impersonale/riflessivo
        # ("si può fare anche per l'account di backup?", "si dovrebbe controllare anche...")
        # veniva interpretato come CONFERMA ed eseguiva alla cieca l'azione in sospeso (reset
        # MFA, creazione gruppo, scrittura Graph/Exchange/Teams qualsiasi) invece di far
        # passare la vera domanda dell'utente. Stesso rischio con "ok"/"vai" dentro una frase
        # normale ("ok ma prima dimmi...", "vai al tab tenant prima"). Ora si conferma SOLO se
        # OGNI parola del messaggio (ripulito da punteggiatura finale) e' una parola di conferma
        # nota - una singola parola estranea (qualunque parte di una domanda/frase vera) blocca
        # il match e fa cadere il messaggio nel ramo "else" sotto, che chiede di nuovo si/no
        # esplicitamente invece di agire su un'ipotesi rischiosa.
        $confirmWords = @('si', 'sì', 'ok', 'okay', 'conferma', 'confermo', 'procedi', 'esegui', 'fai', 'pure', 'vai', 'dai', 'yes')
        $cancelWords  = @('no', 'annulla', 'stop', 'grazie')
        # Bug reale trovato dal vivo il 23/08/2026 durante una riverifica di questo stesso fix
        # (regressione introdotta dal fix originale, non presente prima): la punteggiatura
        # veniva ripulita SOLO alla fine dell'intera stringa, non parola per parola - "sì,
        # esegui pure" (virgola interna dopo "sì", frase di conferma naturalissima) produceva
        # la parola "sì," (virgola ancora attaccata), che non risultava MAI uguale a "si"/"sì"
        # in $confirmWords, bloccando una conferma reale e ovvia. Ripulita ora la punteggiatura
        # da OGNI parola singola dopo lo split, non solo dalla fine della frase intera.
        $cleanedWords = ($lower -split '\s+' | ForEach-Object { $_ -replace '^[!.,;:?]+|[!.,;:?]+$', '' }) | Where-Object { $_ }
        $isConfirm = $cleanedWords.Count -gt 0 -and -not ($cleanedWords | Where-Object { $_ -notin $confirmWords })
        $isCancel  = $cleanedWords.Count -gt 0 -and -not ($cleanedWords | Where-Object { $_ -notin $cancelWords })
        if ($isConfirm) {
            $action = $script:PendingAction
            $script:PendingAction = $null
            if ($action.Type -eq 'Queue') { return (Execute-PendingQueue $action.Queue) }
            if ($action.Type -eq 'ApplyFix') {
                try {
                    $resultText = Invoke-M365OpsApplyFix -Triage $action.Triage -ModuleRoot $moduleRoot
                    return @{ role = 'system'; text = $resultText }
                }
                catch {
                    return @{ role = 'error'; text = "Applicazione della correzione fallita: $($_.Exception.Message)" }
                }
            }
            $actionResult = Execute-PendingAction $action
            Write-M365OpsWriteFailureIfNeeded -Action $action -Result $actionResult
            return $actionResult
        }
        elseif ($isCancel) {
            $script:PendingAction = $null
            return @{ role = 'system'; text = "Operazione annullata." }
        }
        else {
            return @{ role = 'system'; text = "Ho una proposta in sospeso:`n$($script:PendingAction.ConfirmText)`n`nRispondi 'si' per procedere o 'no' per annullare." }
        }
    }

    # --- Catalogo comandi locali: eseguiti direttamente, nessuna chiamata AI
    #     tranne le voci con RequiresAI = $true (es. CompliancePatterns). ---
    foreach ($entry in (Get-M365OpsCommandCatalog)) {
        $hit = $false
        foreach ($t in $entry.Triggers) { if ($lower -match $t) { $hit = $true; break } }
        if (-not $hit) { continue }

        # DeferWords: bug reale del 17/08/2026, osservato due volte di fila sullo stesso
        # messaggio - un trigger locale (regex a costo zero) intercettava una richiesta molto
        # piu' ampia di quanto quella singola voce del catalogo sappia fare (es. "report
        # mailbox utente + condivise + gruppi, con un tab permessi" faceva scattare prima
        # SharedMailboxPermissions poi, corretto quello, ExportSharedMailboxReport - entrambi
        # rispondevano SOLO con la loro fetta, ignorando in silenzio il resto della richiesta,
        # senza che l'utente avesse modo di saperlo). Una voce con DeferWords si fa da parte
        # (passa al catalogo successivo, poi eventualmente all'AI) se il messaggio contiene
        # anche uno di questi segnali di richiesta piu' ampia di quella singola voce.
        if ($entry.DeferWords) {
            # Solo \b INIZIALE, mai anche finale: bug reale trovato dal vivo il 19/08/2026
            # (bug-hunt mirato) - diverse DeferWords in questo catalogo sono radici di parola
            # ('consigl', 'perch', appena aggiunta 'correlazion'), pensate per matchare
            # "consiglio"/"perché"/"correlazioni" ecc. Con \b anche alla fine, il confine di
            # parola serve SUBITO dopo la radice - dove pero' la parola vera continua con altre
            # lettere, quindi non c'e' mai un confine li' e il match falliva SEMPRE, in silenzio,
            # da quando queste DeferWords erano state introdotte (verificato: 'consiglio' -match
            # '\bconsigl\b' e' $false). Il \b iniziale da solo basta gia' a evitare falsi
            # positivi a meta' parola (es. 'nn' non tocca 'innovazione': non c'e' un confine
            # nemmeno li' prima della 'nn'), quindi rimuovere solo quello finale e' sicuro.
            $deferPattern = '\b(' + ($entry.DeferWords -join '|') + ')'
            if ($lower -match $deferPattern) { continue }
        }

        try {
            $captured = $null
            if ($entry.CaptureRegex -and $msg -match $entry.CaptureRegex) { $captured = $Matches[1] }

            $reportPathBefore = $script:LastReportPath
            $result = if ($null -ne $captured) { & $entry.Handler $captured } else { & $entry.Handler }
            $text = & $entry.Formatter $result
            $role = if ($entry.RequiresAI) { 'ai' } else { 'system' }
            # Nota sorgente SEMPRE presente (24/08/2026, richiesto esplicitamente dall'utente
            # dopo aver notato che "dammi i fattori mfa di X" - voce MfaStatus del catalogo,
            # RequiresAI=$false - non mostrava nessuna nota, a differenza delle risposte passate
            # dal loop AI generale che dal v0.9.86 la mostrano sempre): stesso principio esteso
            # qui, l'unico altro punto che restituisce dati reali all'utente. RequiresAI=$false
            # (la stragrande maggioranza, es. MfaStatus/ListDevices) e' un comando locale a
            # costo zero, nessuna IA coinvolta - lo si dice esplicitamente invece di lasciare
            # un'assenza di nota come unico modo (implicito, mai spiegato) per dedurlo.
            # RequiresAI=$true (es. CompliancePatterns) chiama davvero l'IA (vedi
            # Get-M365OpsCompliancePatterns -Provider $script:ActiveAIProvider) - stessa
            # etichetta del motore usata dal loop AI generale (Get-M365OpsAiProviderLabel,
            # Private, estratta apposta il 24/08/2026 per essere condivisa tra i due punti).
            $text += if ($entry.RequiresAI) {
                "`n`n_Fonte: comando locale '$($entry.Name)' con analisi IA. Elaborata da IA: $(Get-M365OpsAiProviderLabel -Provider $script:ActiveAIProvider)._"
            } else {
                "`n`n_Fonte: comando locale '$($entry.Name)', nessuna IA usata._"
            }
            # Se l'handler ha appena generato un report (LastReportPath cambiato rispetto a
            # prima della chiamata), rendilo scaricabile dalla GUI invece di lasciare solo
            # il percorso su disco nel testo - l'utente non deve andare a cercarselo a mano.
            $attachments = if ($script:LastReportPath -and $script:LastReportPath -ne $reportPathBefore) {
                @(@{ FileName = (Split-Path -Leaf $script:LastReportPath) })
            } else { $null }
            return @{ role = $role; text = $text; attachments = $attachments }
        }
        catch {
            # Bug reale trovato dal vivo il 24/08/2026 (agente di autoreview dedicato a questo
            # commit, v0.9.87): la nota d'errore diceva SEMPRE "nessuna IA usata", anche per le
            # voci RequiresAI=$true (CompliancePatterns/ExportCompliancePatterns), dove l'IA e'
            # esattamente quello che puo' aver fallito (chiave API mancante, rete, risposta
            # vuota...) - a differenza del ramo di successo qui sopra, che gia' distingue
            # correttamente le due etichette. Riprodotto forzando un errore di validazione dentro
            # Get-M365OpsCompliancePatterns (Provider non valido): l'errore reale mostrava "nessuna
            # IA usata (fallito prima di completare)" nonostante la voce chiami davvero l'IA.
            # Corretto branchando sullo stesso $entry.RequiresAI del ramo di successo.
            $failNote = if ($entry.RequiresAI) {
                "_Fonte: comando locale '$($entry.Name)' con analisi IA, fallito prima di completare (Elaborata da IA: $(Get-M365OpsAiProviderLabel -Provider $script:ActiveAIProvider))._"
            } else {
                "_Fonte: comando locale '$($entry.Name)', nessuna IA usata (fallito prima di completare)._"
            }
            return @{ role = 'error'; text = "Errore in '$($entry.Name)': $($_.Exception.Message)`n`n$failNote" }
        }
    }

    # --- Richieste composte: piu' azioni nella stessa frase (es. "pacchettizza, crea
    #     gruppo e assegna"). Rilevate localmente, nessuna chiamata AI: le tre azioni
    #     esistono gia' come logica singola, qui vengono solo accodate invece di
    #     escludersi a vicenda con un elseif. ---
    # Bug reale trovato dal vivo il 19/08/2026: 'pacchett' (doppia T) non intercettava
    # "pacchetizza" (singola T, variante di battitura molto comune) - la richiesta composta
    # reale di un utente ("pacchetizza e distribuisci l'app GIT, crea un gruppo X e
    # assegnalo") e' passata con $hasPackageIntent=false, saltando in silenzio il passo di
    # pacchettizzazione e fallendo poi in modo confuso all'assegnazione ("nessuna app
    # disponibile"). 'pacchet{1,2}izz'/'impacchet{1,2}' tollerano ora entrambe le grafie.
    # (?!at[ao]) esclude il participio passato "pacchett(i)zzato/a" (23/08/2026, bug reale
    # trovato dal vivo, bug-hunt di 16 ore): "Ho pacchettizzato l'app ma non riesco a farla
    # girare nel gruppo di test, puoi aiutarmi?" e' una domanda di supporto su un'azione GIA'
    # fatta, non una nuova richiesta - prima di questo fix veniva comunque interpretata come
    # "pacchettizza di nuovo" perche' la radice 'pacchett(i)zz' matcha qualunque coniugazione,
    # incluso il participio passato. L'imperativo/presente ("pacchettizza"/"pacchetizzalo"/
    # "pacchettizzando") continua a matchare regolarmente (la lookahead nega solo "at"+a/o
    # subito dopo la radice, non "a" da sola).
    $hasPackageIntent = $lower -match 'pacchet{1,2}izz(?!at[ao])|impacchet{1,2}(?!at[ao])|crea (l.)?app\b|carica app'
    # "grupp" senza richiedere la 'o' finale: tollera refusi tipo "grupp odi test" (visto
    # in un test reale) dove uno spazio di troppo/mancante rompe la parola "gruppo".
    $hasGroupIntent = $lower -match 'crea.{0,20}grupp|grupp.{0,10}test'
    # Guardia comune anti-troubleshooting (23/08/2026, stesso bug-hunt, stesso esempio reale
    # sopra): "gruppo di test" dentro una domanda di supporto ("...non riesco a farla girare
    # nel gruppo di test, puoi aiutarmi?") faceva scattare ANCHE $hasGroupIntent (prossimita'
    # "grupp"+"test"), portando $intentCount a 2 e proponendo una sequenza di scritture
    # (ripacchettizzazione + nuovo gruppo) mai richiesta - l'utente voleva solo un aiuto per
    # un problema. Stesso principio gia' in uso per $hasAssignIntent qui sotto (esclusione
    # esplicita se il messaggio contiene segnali di un contesto diverso): un vero comando di
    # pacchettizzazione/creazione gruppo non ha motivo di contenere anche una domanda di
    # supporto ("aiut", "riesc", "problema", "puoi") o un punto interrogativo.
    $looksLikeTroubleshootingQuestion = $lower -match '\b(aiut\w*|non riesc\w*|problema|puoi|perch[eé]|come mai)\b' -or $msg.TrimEnd().EndsWith('?')
    if ($looksLikeTroubleshootingQuestion) { $hasPackageIntent = $false; $hasGroupIntent = $false }
    # "assegna" da solo prendeva anche "quali licenze ha assegnate a..." (domanda, non comando).
    # Richiede che nelle vicinanze compaia un indizio reale di assegnazione app (app/gruppo/tutti/required/available).
    # Bug reale trovato dal vivo il 18/08/2026: "grupp"/"tutti" da soli sono troppo generici -
    # intercettavano anche richieste di processo/ticketing completamente estranee a Intune
    # ("assegnata al gruppo" dentro un flusso di gestione ticket, "assegnando il record...al
    # gruppo competente" per SharePoint) - mai arrivate all'AI. Escluse esplicitamente se il
    # messaggio contiene segnali di un contesto diverso (ticket/mail/processo), che un vero
    # comando di assegnazione app non avrebbe motivo di nominare.
    # BUG reale trovato dal vivo il 19/08/2026: "crea l'app GIT e rendila available all devices"
    # non contiene 'assegna' in nessuna forma - solo "rendila"/"rendilo" + available/required, un
    # fraseggio reale altrettanto comune quanto "assegna...". Aggiunto come alternativa.
    $hasAssignIntent = ($lower -match 'assegna\w*.{0,25}(app|required|available|obbligator|opzional|tutti|grupp)|rendil[ao].{0,20}(available|required|obbligator|opzional)') -and
        ($lower -notmatch '\b(ticket|mail|record|flusso|subject|categoria|tag|triage|competente)\b')
    $intentCount = 0
    if ($hasPackageIntent) { $intentCount++ }
    if ($hasGroupIntent) { $intentCount++ }
    if ($hasAssignIntent) { $intentCount++ }

    if ($intentCount -ge 2) {
        $queue = @()
        $summaryLines = @()
        $step = 0

        if ($hasGroupIntent) {
            $step++
            $groupPlan = Get-M365OpsGroupPlanFromMessage -Msg $msg
            $queue += @{ Type = 'CreateGroup'; Name = $groupPlan.Name; MemberUpn = $groupPlan.MemberUpn; OriginalMessage = $msg }
            $memberPart = if ($groupPlan.MemberUpn) { " con membro $($groupPlan.MemberUpn)" } elseif ($groupPlan.MemberNote) { " ($($groupPlan.MemberNote))" } else { " (nessun membro specificato)" }
            $summaryLines += "$step. Creo gruppo '$($groupPlan.Name)'$memberPart"
        }

        if ($hasPackageIntent) {
            if (-not $script:LoadedFilePath) {
                return @{ role = 'system'; text = "Prima carica un file .exe/.msi/.ps1/.bat/.cmd con il pulsante sopra la casella di testo, poi ripeti la richiesta." }
            }
            $scriptPlan = Get-M365OpsScriptPackagePlan -FilePath $script:LoadedFilePath -Message $msg
            if ($scriptPlan -and $scriptPlan.NeedsDetectionInfo) {
                return @{ role = 'system'; text = $scriptPlan.Message }
            }

            $insight = Get-M365OpsInstallerInsight -Path $script:LoadedFilePath
            # BUG reale trovato dal vivo il 19/08/2026: "pacchetizza X, chiamalo NomeVoluto" ignorava
            # sempre il nome richiesto, usando SEMPRE i metadati dell'installer o il nome del file -
            # "chiamalo"/"chiamala"/ecc. non venivano mai letti dal messaggio. Il nome esplicito
            # dell'utente ha ora sempre priorita' quando presente. Secondo bug reale trovato dal
            # vivo POCO DOPO aver corretto il primo: "crea l'app GIT e rendila available..." non
            # usa nessuna delle parole sopra, il nome e' l'oggetto diretto di "crea l'app X" - non
            # riconosciuto dal primo pattern, l'app veniva ancora nominata dal file. Un secondo
            # pattern (provato solo se il primo non trova nulla) copre anche questa forma.
            $requestedNameMatch = [regex]::Match($msg, '(?:chiamalo|chiamala|chiamato|chiamata|nominalo|nominala|di nome|con nome)\s+(.+?)(?:\s*,|\s*\.|\s+e\s+|$)', 'IgnoreCase')
            if (-not $requestedNameMatch.Success) {
                $requestedNameMatch = [regex]::Match($msg, "crea\s+(?:l['’]|un['’]|una\s+|il\s+|lo\s+)?app(?:licazione)?\s+(?:chiamat[ao]\s+)?(.+?)(?:\s*,|\s*\.|\s+e\s+|`$)", 'IgnoreCase')
            }
            $displayName = if ($requestedNameMatch.Success -and $requestedNameMatch.Groups[1].Value.Trim()) { $requestedNameMatch.Groups[1].Value.Trim() } elseif ($insight.ProductName) { $insight.ProductName } else { [IO.Path]::GetFileNameWithoutExtension($script:LoadedFilePath) }
            $publisher = if ($insight.CompanyName) { $insight.CompanyName } else { "Sconosciuto" }

            if ($scriptPlan) {
                # Script (ps1/bat/cmd, 18/08/2026): comando e detection gia' pronti dal messaggio
                # dell'utente - nessuna deduzione da metadati exe, non applicabile a uno script.
                $installCmd = $scriptPlan.InstallCmd
                $detectionMode = $scriptPlan.DetectionMode
                $detectionPath = $scriptPlan.DetectionPath
                $detectionFile = $scriptPlan.DetectionFile
                $detectionRegKeyPath = $scriptPlan.DetectionRegistryKeyPath
                $detectionRegValueName = $scriptPlan.DetectionRegistryValueName
                $detectionVersion = $null
                $uninstallCmd = $null
                $detectionNote = "detection ($($scriptPlan.DetectionNote))"
            } elseif ([IO.Path]::GetExtension($script:LoadedFilePath) -eq '.msi') {
                # Ramo MSI dedicato (23/08/2026, bug reale trovato dal vivo, bug-hunt di 16 ore):
                # prima di questo fix un .msi cadeva nel ramo EXE sotto, producendo un
                # InstallCommandLine tipo "App.msi /S" - non un comando valido: MSI non si
                # avvia da solo con uno switch, va invocato tramite msiexec. Inoltre .msi e' un
                # OLE compound document, non un eseguibile PE: (Get-Item).VersionInfo e la
                # ricerca di firme installer (Inno/NSIS/...) su un .msi non trovano mai nulla
                # di significativo, quindi $insight per un .msi era comunque inutile per dedurre
                # switch/nome/publisher. La ProductCode GUID (necessaria per un uninstall
                # silenzioso affidabile via msiexec /x) non e' deducibile in modo sicuro senza
                # aprire il database MSI (COM WindowsInstaller.Installer) - non tentato qui per
                # non rischiare un GUID sbagliato: l'uninstall resta esplicitamente da
                # verificare, come gia' accade per un EXE senza firma riconosciuta.
                $fileNameOnly = Split-Path -Leaf $script:LoadedFilePath
                $installCmd = "msiexec /i `"$fileNameOnly`" /quiet /norestart"
                $uninstallCmd = "REM uninstall MSI: serve la ProductCode (GUID) di questo pacchetto - msiexec /x {PRODUCT-CODE-GUID} /quiet /norestart. Trovala con 'Get-Package -Name `"$displayName`"' su una macchina dove e' gia' installato, o nel registro sotto HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall."
                $detectionMode = 'Version'
                $detectionPath = "C:\Program Files\$displayName"
                $detectionFile = "$displayName.exe"
                $detectionVersion = "1.0.0.0"
                $detectionRegKeyPath = $null; $detectionRegValueName = $null
                $detectionNote = "detection: $detectionPath\$detectionFile >= $detectionVersion (dedotta dal solo nome prodotto richiesto - un .msi non espone gli stessi metadati exe di un file .exe, verifica il percorso di installazione reale prima di assegnare l'app)"
            } else {
                $useRegistry = $lower -match 'registro|registry'
                $switchPart = if ($insight.SuggestedSilentSwitch) { $insight.SuggestedSilentSwitch } else { "/S" }
                $installCmd = "$(Split-Path -Leaf $script:LoadedFilePath) $switchPart"
                $detectionMode = 'Version'
                $detectionPath = "C:\Program Files\$displayName"
                $detectionFile = "$displayName.exe"
                $detectionVersion = if ($insight.FileVersion) { $insight.FileVersion } else { "1.0.0.0" }
                $detectionRegKeyPath = $null; $detectionRegValueName = $null
                $uninstallCmd = if ($insight.InstallerFramework -eq 'Inno Setup') { "`"$detectionPath\unins000.exe`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" } else { $null }
                $detectionNote = if ($useRegistry) {
                    "detection su FILE come fallback (avevi chiesto registro: non posso dedurre con certezza la chiave di uninstall di Inno Setup dai soli metadati - contiene un AppId generato in fase di build del setup, verificalo tu nel registro dopo un'installazione di prova e correggo)"
                } else {
                    "detection: $detectionPath\$detectionFile >= $detectionVersion (dedotta dal nome prodotto, verificala)"
                }
            }

            $packageAction = @{
                Type = 'PackageApp'; DisplayName = $displayName; Publisher = $publisher
                InstallCmd = $installCmd; UninstallCmd = $uninstallCmd
                DetectionMode = $detectionMode; DetectionPath = $detectionPath; DetectionFile = $detectionFile; DetectionVersion = $detectionVersion
                DetectionRegistryKeyPath = $detectionRegKeyPath; DetectionRegistryValueName = $detectionRegValueName
            }

            # Opzioni avanzate di packaging menzionate A PAROLE dall'utente (19/08/2026,
            # richiesto esplicitamente) - requisiti hardware, comportamento install/riavvio,
            # return code, scope tag, dipendenze/supersedence. Solo estrazione, mai invenzione:
            # ogni campo non menzionato resta $null e NON viene passato (default standard,
            # invariato). Se l'utente non ha menzionato nulla, un promemoria nel testo di
            # conferma gli ricorda che puo' farlo, invece di procedere in silenzio come se
            # l'opzione non esistesse.
            $customization = $null
            try { $customization = Get-M365OpsWin32AppCustomizationFromMessage -Message $msg -Provider $script:ActiveAIProvider } catch {}

            $customizationDetails = @()
            if ($customization -and $customization.mentionedAnything) {
                foreach ($simpleField in @('MinimumFreeDiskSpaceInMB', 'MinimumMemoryInMB', 'MinimumNumberOfProcessors', 'MinimumCPUSpeedInMHz', 'InstallExperience', 'DeviceRestartBehavior', 'MaximumInstallationTimeInMinutes', 'AllowAvailableUninstall', 'ScopeTagNames')) {
                    if ($null -ne $customization.$simpleField) {
                        $packageAction[$simpleField] = $customization.$simpleField
                        $customizationDetails += "$simpleField=$($customization.$simpleField -join ',')"
                    }
                }
                if ($customization.ReturnCodes) {
                    $packageAction.ReturnCodes = $customization.ReturnCodes
                    $customizationDetails += "return code: " + (($customization.ReturnCodes | ForEach-Object { "$($_.ReturnCode)=$($_.Type)" }) -join ', ')
                }
                # Dipendenza/supersedence per NOME: risolta all'esecuzione (Execute-PendingAction),
                # mai un id indovinato qui - se il nome non si trova, il passo fallisce con un
                # errore chiaro invece di procedere su un id inventato.
                if ($customization.DependsOnAppName) {
                    $packageAction.DependsOnAppName = $customization.DependsOnAppName
                    $packageAction.DependencyType = if ($customization.DependencyType) { $customization.DependencyType } else { 'Detect' }
                    $customizationDetails += "dipende da '$($customization.DependsOnAppName)' ($($packageAction.DependencyType))"
                }
                if ($customization.SupersedesAppName) {
                    $packageAction.SupersedesAppName = $customization.SupersedesAppName
                    $packageAction.SupersedenceType = if ($customization.SupersedenceType) { $customization.SupersedenceType } else { 'Update' }
                    $customizationDetails += "sostituisce '$($customization.SupersedesAppName)' ($($packageAction.SupersedenceType))"
                }
            }

            $queue += $packageAction
            $step++
            $detailsNote = if ($customizationDetails) { " Personalizzazioni: " + ($customizationDetails -join '; ') + "." } else { " (nessuna personalizzazione avanzata indicata - requisiti hardware, comportamento riavvio, tempo massimo, disinstallazione da available, return code, scope tag, dipendenze/supersedence: procedo con gli standard Intune. Puoi indicarle a parole nella richiesta se vuoi personalizzarle.)" }
            $summaryLines += "$step. Pacchettizzo '$displayName' ($publisher). Install: $installCmd. $detectionNote.$detailsNote"
        }

        if ($hasAssignIntent) {
            $step++
            $intentValue = 'available'
            if ($lower -match 'required|obbligator|forzat') { $intentValue = 'required' }
            # BUG reale trovato dal vivo il 19/08/2026: "rendila available ALL DEVICES" (inglese,
            # fraseggio reale comune) non veniva riconosciuto - solo l'italiano 'tutti'.
            $allDevices = $lower -match 'tutti|all devices|all\s+the\s+devices'
            $queue += @{ Type = 'AssignApp'; Intent = $intentValue; AllDevices = $allDevices }
            $target = if ($allDevices) { "tutti i dispositivi" } else { "il gruppo creato in questa stessa sequenza" }
            $summaryLines += "$step. Assegno come '$intentValue' a $target"
        }

        $confirmText = "Richiesta composta, la eseguo in $($queue.Count) passi in sequenza:`n" + ($summaryLines -join "`n") + "`n`nConfermi tutta la sequenza?"
        $script:PendingAction = @{ Type = 'Queue'; Queue = $queue; ConfirmText = $confirmText }
        return @{ role = 'system'; text = "$confirmText`n(rispondi 'si' o 'no')" }
    }

    # --- Flussi a piu' turni con conferma (non catalogabili come dispatch diretto) ---
    if ($msg -match '^[Cc]rea gruppo (.+)') {
        $rest = $Matches[1].Trim()
        $name = $rest
        $memberUpn = $null
        if ($rest -match '^(.+?)\s+con\s+(\S+@\S+)$') {
            $name = $Matches[1].Trim()
            $memberUpn = $Matches[2].Trim()
        }
        $confirmText = if ($memberUpn) { "Creo il gruppo '$name' con membro $memberUpn. Confermi?" } else { "Creo il gruppo '$name' senza membri iniziali. Confermi?" }
        $script:PendingAction = @{ Type = 'CreateGroup'; Name = $name; MemberUpn = $memberUpn; ConfirmText = $confirmText; OriginalMessage = $msg }
        return @{ role = 'system'; text = "$confirmText`n(rispondi 'si' o 'no')" }
    }
    elseif ($lower -match 'pacchet{1,2}izz|impacchet{1,2}|crea (l.)?app\b|carica app') {
        if (-not $script:LoadedFilePath) {
            return @{ role = 'system'; text = "Prima carica un file .exe/.msi/.ps1/.bat/.cmd con il pulsante sopra la casella di testo." }
        }
        $scriptPlan = Get-M365OpsScriptPackagePlan -FilePath $script:LoadedFilePath -Message $msg
        if ($scriptPlan -and $scriptPlan.NeedsDetectionInfo) {
            return @{ role = 'system'; text = $scriptPlan.Message }
        }

        $insight = Get-M365OpsInstallerInsight -Path $script:LoadedFilePath
        # Stesso fix del ramo a coda sopra (19/08/2026): il nome esplicito dell'utente
        # ("chiamalo X" oppure "crea l'app X") ha sempre priorita' sui metadati installer/nome file.
        $requestedNameMatch = [regex]::Match($msg, '(?:chiamalo|chiamala|chiamato|chiamata|nominalo|nominala|di nome|con nome)\s+(.+?)(?:\s*,|\s*\.|\s+e\s+|$)', 'IgnoreCase')
        if (-not $requestedNameMatch.Success) {
            $requestedNameMatch = [regex]::Match($msg, "crea\s+(?:l['’]|un['’]|una\s+|il\s+|lo\s+)?app(?:licazione)?\s+(?:chiamat[ao]\s+)?(.+?)(?:\s*,|\s*\.|\s+e\s+|`$)", 'IgnoreCase')
        }
        $displayName = if ($requestedNameMatch.Success -and $requestedNameMatch.Groups[1].Value.Trim()) { $requestedNameMatch.Groups[1].Value.Trim() } elseif ($insight.ProductName) { $insight.ProductName } else { [IO.Path]::GetFileNameWithoutExtension($script:LoadedFilePath) }
        $publisher = if ($insight.CompanyName) { $insight.CompanyName } else { "Sconosciuto" }

        if ($scriptPlan) {
            $installCmd = $scriptPlan.InstallCmd
            $detectionMode = $scriptPlan.DetectionMode
            $detectionPath = $scriptPlan.DetectionPath
            $detectionFile = $scriptPlan.DetectionFile
            $detectionRegKeyPath = $scriptPlan.DetectionRegistryKeyPath
            $detectionRegValueName = $scriptPlan.DetectionRegistryValueName
            $detectionVersion = $null
            $uninstallCmd = $null
            $detectionText = "Detection: $($scriptPlan.DetectionNote)"
        } elseif ([IO.Path]::GetExtension($script:LoadedFilePath) -eq '.msi') {
            # Stesso fix del ramo a coda sopra (23/08/2026, bug reale trovato dal vivo, bug-hunt
            # di 16 ore) - vedi li' per il dettaglio completo del perche' un .msi non puo' usare
            # la stessa logica "filename + switch" di un .exe.
            $fileNameOnly = Split-Path -Leaf $script:LoadedFilePath
            $installCmd = "msiexec /i `"$fileNameOnly`" /quiet /norestart"
            $uninstallCmd = "REM uninstall MSI: serve la ProductCode (GUID) di questo pacchetto - msiexec /x {PRODUCT-CODE-GUID} /quiet /norestart. Trovala con 'Get-Package -Name `"$displayName`"' su una macchina dove e' gia' installato, o nel registro sotto HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall."
            $detectionMode = 'Version'
            $detectionPath = "C:\Program Files\$displayName"
            $detectionFile = "$displayName.exe"
            $detectionVersion = "1.0.0.0"
            $detectionRegKeyPath = $null; $detectionRegValueName = $null
            $detectionText = "Detection: $detectionPath\$detectionFile >= $detectionVersion`n(dedotta dal solo nome prodotto richiesto - un .msi non espone gli stessi metadati exe di un file .exe, verifica il percorso di installazione reale prima di assegnare l'app)"
        } else {
            $switchPart = if ($insight.SuggestedSilentSwitch) { $insight.SuggestedSilentSwitch } else { "/S (nessuna firma installer riconosciuta - verifica tu lo switch corretto)" }
            $installCmd = "$(Split-Path -Leaf $script:LoadedFilePath) $switchPart"
            $detectionMode = 'Version'
            $detectionPath = "C:\Program Files\$displayName"
            $detectionFile = "$displayName.exe"
            $detectionVersion = if ($insight.FileVersion) { $insight.FileVersion } else { "1.0.0.0" }
            $detectionRegKeyPath = $null; $detectionRegValueName = $null
            $uninstallCmd = if ($insight.InstallerFramework -eq 'Inno Setup') { "`"$detectionPath\unins000.exe`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" } else { $null }
            $detectionText = "Detection: $detectionPath\$detectionFile >= $detectionVersion`n(percorso di detection DEDOTTO dal nome prodotto, verificalo)"
        }

        $singlePackageAction = @{
            Type = 'PackageApp'; DisplayName = $displayName; Publisher = $publisher
            InstallCmd = $installCmd; UninstallCmd = $uninstallCmd
            DetectionMode = $detectionMode; DetectionPath = $detectionPath; DetectionFile = $detectionFile; DetectionVersion = $detectionVersion
            DetectionRegistryKeyPath = $detectionRegKeyPath; DetectionRegistryValueName = $detectionRegValueName
        }
        # Stessa estrazione di personalizzazioni a parole del flusso a coda sopra (19/08/2026) -
        # duplicata qui perche' questo e' un ramo separato (pacchettizzazione senza altre azioni
        # nella stessa frase), non un refactor per non rischiare di toccare il flusso a coda.
        $singleCustomization = $null
        try { $singleCustomization = Get-M365OpsWin32AppCustomizationFromMessage -Message $msg -Provider $script:ActiveAIProvider } catch {}
        $singleCustomizationDetails = @()
        if ($singleCustomization -and $singleCustomization.mentionedAnything) {
            foreach ($simpleField in @('MinimumFreeDiskSpaceInMB', 'MinimumMemoryInMB', 'MinimumNumberOfProcessors', 'MinimumCPUSpeedInMHz', 'InstallExperience', 'DeviceRestartBehavior', 'MaximumInstallationTimeInMinutes', 'AllowAvailableUninstall', 'ScopeTagNames')) {
                if ($null -ne $singleCustomization.$simpleField) {
                    $singlePackageAction[$simpleField] = $singleCustomization.$simpleField
                    $singleCustomizationDetails += "$simpleField=$($singleCustomization.$simpleField -join ',')"
                }
            }
            if ($singleCustomization.ReturnCodes) {
                $singlePackageAction.ReturnCodes = $singleCustomization.ReturnCodes
                $singleCustomizationDetails += "return code: " + (($singleCustomization.ReturnCodes | ForEach-Object { "$($_.ReturnCode)=$($_.Type)" }) -join ', ')
            }
            if ($singleCustomization.DependsOnAppName) {
                $singlePackageAction.DependsOnAppName = $singleCustomization.DependsOnAppName
                $singlePackageAction.DependencyType = if ($singleCustomization.DependencyType) { $singleCustomization.DependencyType } else { 'Detect' }
                $singleCustomizationDetails += "dipende da '$($singleCustomization.DependsOnAppName)' ($($singlePackageAction.DependencyType))"
            }
            if ($singleCustomization.SupersedesAppName) {
                $singlePackageAction.SupersedesAppName = $singleCustomization.SupersedesAppName
                $singlePackageAction.SupersedenceType = if ($singleCustomization.SupersedenceType) { $singleCustomization.SupersedenceType } else { 'Update' }
                $singleCustomizationDetails += "sostituisce '$($singleCustomization.SupersedesAppName)' ($($singlePackageAction.SupersedenceType))"
            }
        }
        $singleDetailsNote = if ($singleCustomizationDetails) { "Personalizzazioni: " + ($singleCustomizationDetails -join '; ') + "." } else { "Nessuna personalizzazione avanzata indicata (requisiti hardware, riavvio, tempo massimo, disinstallazione da available, return code, scope tag, dipendenze/supersedence) - procedo con gli standard Intune. Puoi indicarle a parole se vuoi personalizzarle." }

        $confirmText = "Pacchettizzo '$displayName' ($publisher).`nInstall: $installCmd`n$detectionText`n$singleDetailsNote`nNON verra' assegnata a nessuno. Confermi?"
        $singlePackageAction.ConfirmText = $confirmText
        $script:PendingAction = $singlePackageAction
        return @{ role = 'system'; text = "$confirmText`n(rispondi 'si' o 'no')" }
    }
    elseif (($lower -match 'assegna\w*.{0,25}(app|required|available|obbligator|opzional|tutti|grupp)') -and
            ($lower -notmatch '\b(ticket|mail|record|flusso|subject|categoria|tag|triage|competente)\b') -and
            # Guardia anti-domanda-di-supporto (23/08/2026, bug reale trovato dal vivo,
            # bug-hunt di 16 ore): questo ramo standalone usava lo stesso identico trigger di
            # $hasAssignIntent sopra (vedi il blocco richieste composte, che GIA' applica
            # $looksLikeTroubleshootingQuestion per lo stesso identico motivo) ma senza mai
            # applicare la stessa guardia qui - "Ho assegnato l'app come available a tutti ma
            # alcuni utenti non riescono a installarla, sai perche'?" matcha comunque il
            # trigger (assegnato+available+tutti) e proponeva una NUOVA assegnazione live
            # invece di rispondere alla domanda di supporto.
            (-not $looksLikeTroubleshootingQuestion)) {
        if (-not $script:LastAppId) { return @{ role = 'system'; text = "Non ho un'app recente da assegnare — creane una prima (carica un file e chiedimi di pacchettizzarla)." } }
        $intentValue = $null
        if ($lower -match 'required|obbligator|forzat') { $intentValue = 'required' }
        elseif ($lower -match 'available|opzional|disponibil') { $intentValue = 'available' }
        if (-not $intentValue) { return @{ role = 'system'; text = "Vuoi assegnarla come 'required' (obbligatoria) o 'available' (opzionale)?" } }

        $allDevices = $lower -match 'tutti|all devices|all\s+the\s+devices'
        if (-not $allDevices -and -not $script:LastGroupId) {
            return @{ role = 'system'; text = "Non ho un gruppo recente. Vuoi assegnarla a 'tutti i dispositivi', o creo prima un gruppo (dimmi il nome)?" }
        }
        $groupId = if ($allDevices) { $null } else { $script:LastGroupId }
        $target = if ($allDevices) { "tutti i dispositivi" } else { "il gruppo creato in precedenza" }
        $confirmText = "Assegno l'app come '$intentValue' a $target. Confermi?"
        $script:PendingAction = @{ Type = 'AssignApp'; AppId = $script:LastAppId; Intent = $intentValue; GroupId = $groupId; ConfirmText = $confirmText }
        return @{ role = 'system'; text = "$confirmText`n(rispondi 'si' o 'no')" }
    }
    else {
        # Fallback libero: prima usava una singola chiamata AI senza alcun dato reale
        # allegato (rispondeva "da manuale" - bug reale trovato testando l'app). Ora usa
        # tool-calling: il modello decide da solo quali dati del tenant interrogare prima
        # di rispondere.
        $aiPrompt = $msg
        if ($script:LoadedMigrationCsvPath -and (Test-Path $script:LoadedMigrationCsvPath)) {
            $csvEmails = @(Get-Content $script:LoadedMigrationCsvPath | Select-Object -Skip 1 | Where-Object { $_.Trim() })
            if ($csvEmails.Count -gt 0) {
                $aiPrompt = "$msg`n`n[CSV caricato dall'utente - indirizzi per un eventuale batch di migrazione: $($csvEmails -join ', ')]"
            }
        }
        Write-M365OpsLog "Avvio Invoke-M365OpsAgentTools (fallback AI)..."
        try {
            # -Provider esplicito: Invoke-M365OpsAgentTools vive nel modulo, il suo $script:
            # e' lo scope DEL MODULO, non quello di questo script (Server.ps1) - un default
            # basato su $script:ActiveAIProvider dentro la funzione vedrebbe sempre $null e
            # cadrebbe silenziosamente su Claude a prescindere dalla scelta in GUI (stesso
            # tipo di bug di scoping gia' incontrato con Get-M365OpsAiUsageStatus).
            # Storico locale della conversazione (Config\ChatHistory-<tenant>.json): senza,
            # ogni domanda di follow-up ripartirebbe da zero e l'AI non "ricorderebbe" mai la
            # domanda precedente (bug reale segnalato dall'utente il 15/08/2026).
            # @(...) OBBLIGATORIO qui - causa radice reale del bug "role mancante" trovata il
            # 19/08/2026 (bug-hunt mirato, prima solo mitigata a valle, sezione 20.5 della
            # guida): senza, quando lo storico e' vuoto Get-M365OpsChatHistory restituisce un
            # array vuoto che PowerShell collassa a $null in un'assegnazione scalare - $null
            # passato a -History produce poi una voce fantasma {role=null} in ogni chiamata AI
            # (vedi Invoke-M365OpsAgentTools.ps1 per il meccanismo completo, corretto anche li').
            $chatHistory = @(Get-M365OpsChatHistory -TenantName $script:ActiveTenantProfile)
            $result = Invoke-M365OpsAgentTools -Prompt $aiPrompt -Provider $script:ActiveAIProvider -History $chatHistory
            Write-M365OpsLog "Invoke-M365OpsAgentTools completato."

            if ($result.PendingWrite) {
                # GLITCH REALE osservato dal vivo il 23/08/2026 durante uno stress test: nonostante
                # la REGOLA CRITICA ASSOLUTA anti-fabbricazione gia' nel system prompt di
                # Invoke-M365OpsAgentTools.ps1 (aggiunta il 19/08/2026 per un bug simile: il
                # modello dichiarava una scrittura fatta senza MAI aver chiamato uno strumento
                # propose_*), qui si e' visto un caso diverso ma imparentato - il modello ha
                # chiamato per davvero propose_intune_write (PendingWrite e' infatti valorizzato,
                # correttamente, il blocco di conferma sotto e' vero) MA nella STESSA risposta ha
                # anche scritto un testo tipo "La creazione risulta confermata ed eseguita
                # correttamente... e' stato creato con ID <GUID INVENTATO>" - un ID che l'esecuzione
                # reale (confermata subito dopo dal vivo) ha smentito con un ID diverso. La regola
                # nel prompt riduce ma non elimina il rischio (i modelli possono comunque violare
                # un'istruzione testuale), e riscrivere/tagliare la prosa libera del modello qui
                # sarebbe troppo fragile (italiano libero, nessuna struttura da fare pattern-match
                # affidabile) - invece, quando il testo sembra dichiarare un completamento gia'
                # avvenuto PROPRIO mentre PendingWrite risulta ancora genuinamente in sospeso
                # (quindi la frase e' per costruzione falsa, nulla e' stato eseguito), si antepone
                # un avviso ben visibile invece di editare la frase originale, e si logga per
                # visibilita'/telemetria.
                $falseCompletionPattern = "(?i)(risulta\s+(confermat|eseguit)|e'?\s*stat[oa]\s+(creat|eliminat|modificat|aggiornat|rimoss)|operazione\s+completat|eseguit[oa]\s+con\s+success|ho\s+(creat|eliminat|modificat|aggiornat|rimoss)o)"
                if ($result.Text -match $falseCompletionPattern) {
                    Write-M365OpsLog "GLITCH rilevato: il testo del modello sembra dichiarare un'azione gia' completata (es. un ID inventato) nonostante sia stata solo proposta con propose_* e sia ancora in attesa di conferma dell'utente - avviso anteposto al testo mostrato, nulla e' stato eseguito davvero. Testo originale del modello: $($result.Text)" -Level Warn
                    $result.Text = "_[Avviso M365Ops: la frase che segue potrebbe sembrare dire che l'azione e' gia' stata eseguita - NON lo e', e' ancora solo una PROPOSTA in attesa della tua conferma esplicita (vedi il blocco sotto). Ignora eventuali ID o esiti citati: non sono reali finche' non confermi con 'si'.]_`n`n$($result.Text)"
                }

                $w = $result.PendingWrite
                # Indicatore "passo X di N" per un piano a piu' scritture in sequenza (es. crea
                # utente POI assegna licenza) - l'AI valorizza StepNumber/TotalSteps solo quando
                # sta davvero eseguendo un piano a piu' passaggi (vedi system prompt), cosi'
                # un'azione singola non mostra mai un fuorviante "passo 1 di 1".
                $stepPrefix = if ($w.TotalSteps -and $w.TotalSteps -gt 1) { "Passo $($w.StepNumber) di $($w.TotalSteps)`n`n" } else { "" }
                switch ($w.Kind) {
                    'Exo' {
                        $paramsText = if ($w.Parameters -and $w.Parameters.Count -gt 0) { ($w.Parameters | ConvertTo-Json -Depth 4 -Compress) } else { "(nessuno)" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Scrittura Exchange Online proposta (non ancora eseguita) ---`nCmdlet: $($w.Cmdlet)`nParametri: $paramsText`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'ExoWrite'; Cmdlet = $w.Cmdlet; Parameters = $w.Parameters; ConfirmText = $confirmText }
                    }
                    'Custom' {
                        $paramsText = if ($w.Parameters -and $w.Parameters.Count -gt 0) { ($w.Parameters | ConvertTo-Json -Depth 4 -Compress) } else { "(nessuno)" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Script personalizzato proposto (non ancora eseguito) ---`nScript: $($w.Cmdlet)`nParametri: $paramsText`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'CustomWrite'; Cmdlet = $w.Cmdlet; Parameters = $w.Parameters; ConfirmText = $confirmText }
                    }
                    'SharePoint' {
                        # Stesso meccanismo generico di 'Exo' qui sopra (18/08/2026, aggiunto dopo
                        # il batch di test del 18/08/2026 che segnalava l'assenza di scrittura
                        # SharePoint) - Execute-PendingAction esegue con & $action.Cmdlet @params,
                        # nessuna logica specifica per cmdlet necessaria qui.
                        $paramsText = if ($w.Parameters -and $w.Parameters.Count -gt 0) { ($w.Parameters | ConvertTo-Json -Depth 4 -Compress) } else { "(nessuno)" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Scrittura SharePoint proposta (non ancora eseguita) ---`nCmdlet: $($w.Cmdlet)`nParametri: $paramsText`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'SharePointWrite'; Cmdlet = $w.Cmdlet; Parameters = $w.Parameters; ConfirmText = $confirmText }
                    }
                    'Teams' {
                        $paramsText = if ($w.Parameters -and $w.Parameters.Count -gt 0) { ($w.Parameters | ConvertTo-Json -Depth 4 -Compress) } else { "(nessuno)" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Scrittura Teams proposta (non ancora eseguita) ---`nCmdlet: $($w.Cmdlet)`nParametri: $paramsText`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'TeamsWrite'; Cmdlet = $w.Cmdlet; Parameters = $w.Parameters; ConfirmText = $confirmText }
                    }
                    'Intune' {
                        # Stesso meccanismo generico di 'Exo'/'SharePoint'/'Teams' qui sopra
                        # (19/08/2026, aggiunto insieme alla seconda ondata di cmdlet Intune -
                        # Settings Catalog, Autopilot, script, Proactive Remediations, MAM, anelli
                        # di aggiornamento, Modelli amministrativi, Scope Tag, restrizioni
                        # iscrizione, modelli di notifica, ruoli RBAC) - Execute-PendingAction
                        # esegue con & $action.Cmdlet @params, nessuna logica specifica per
                        # cmdlet necessaria qui. Percorso SEPARATO da 'PackageApp'/'AssignApp'
                        # (pacchettizzazione Win32 da file reale), che restano sul loro flusso
                        # dedicato di parsing del linguaggio naturale.
                        $paramsText = if ($w.Parameters -and $w.Parameters.Count -gt 0) { ($w.Parameters | ConvertTo-Json -Depth 6 -Compress) } else { "(nessuno)" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Scrittura Intune proposta (non ancora eseguita) ---`nCmdlet: $($w.Cmdlet)`nParametri: $paramsText`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'IntuneWrite'; Cmdlet = $w.Cmdlet; Parameters = $w.Parameters; ConfirmText = $confirmText }
                    }
                    'NewCustomScript' {
                        # A differenza di ogni altra proposta, qui l'"azione" e' aggiungere una
                        # capacita' NUOVA all'app, non solo modificare un dato sul tenant - il testo
                        # lo dice esplicitamente in cima, prima ancora del codice, cosi' e' chiaro
                        # cosa sta per succedere anche a chi non legge tutto il codice riga per riga.
                        $modeNote = if ($w.Mode -eq 'Write') { " (ogni sua esecuzione futura richiedera' comunque una conferma separata, come per ogni altra scrittura di questo modulo)" } else { " (una volta caricato, l'AI potra' eseguirlo subito senza chiedere conferma ogni volta - e' dichiarato di sola lettura)" }
                        $warnText = if ($w.Warnings -and $w.Warnings.Count -gt 0) { "`n`nATTENZIONE - il codice contiene questi comandi potenzialmente distruttivi, leggili con particolare attenzione prima di confermare: $($w.Warnings -join ', ')" } else { "" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- NUOVO SCRIPT proposto: aggiunge una capacita' nuova all'app, non e' una scrittura sul tenant ---`nNome file: $($w.Name).ps1 (in Scripts\Custom)`nModalita': $($w.Mode)$modeNote`nMotivo: $($w.Reason)$warnText`n`n--- Codice completo che verrebbe salvato (leggilo prima di confermare) ---`n$($w.Code)"
                        $script:PendingAction = @{ Type = 'NewCustomScript'; Name = $w.Name; Code = $w.Code; Mode = $w.Mode; ConfirmText = $confirmText }
                    }
                    'ApplyFix' {
                        # Uno script custom in sola lettura e' fallito e l'AI ha una correzione
                        # da proporre - stesso meccanismo di conferma di ogni altra scrittura.
                        $fixText = Format-M365OpsErrorTriage $w.Triage
                        $confirmText = "$($result.Text)`n`n$fixText"
                        $script:PendingAction = @{ Type = 'ApplyFix'; Triage = $w.Triage; ConfirmText = $confirmText }
                    }
                    'MfaReset' {
                        # Azione con impatto immediato sull'utente (perde l'accesso ai metodi
                        # MFA rimossi finche' non li riconfigura) - conferma esplicita sempre
                        # richiesta, stesso meccanismo di ogni altra scrittura in questo modulo.
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Reset MFA proposto (non ancora eseguito) ---`nUtente: $($w.Upn)`nMotivo: $($w.Reason)`nATTENZIONE: rimuove i metodi MFA registrati (Authenticator, telefono, FIDO2, ecc.) - NON la password. L'utente dovra' riconfigurare l'MFA al prossimo accesso."
                        $script:PendingAction = @{ Type = 'MfaReset'; Upn = $w.Upn; ConfirmText = $confirmText }
                    }
                    'CliM365' {
                        # Stesso meccanismo generico di 'Exo'/'SharePoint'/'Teams' qui sopra
                        # (26/08/2026, aggiunto insieme all'integrazione del server MCP
                        # CLI-Microsoft365) - Execute-PendingAction esegue tramite
                        # m365RunCommand, nessuna logica specifica per comando necessaria qui.
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Comando CLI Microsoft 365 proposto (non ancora eseguito) ---`nComando: m365 $($w.Command)`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'CliM365Write'; Command = $w.Command; Reason = $w.Reason; ConfirmText = $confirmText }
                    }
                    'EmailReport' {
                        # Invio email = azione visibile a un terzo (specie un indirizzo esterno
                        # al tenant) - conferma esplicita sempre richiesta, stesso meccanismo di
                        # ogni altra scrittura. Il percorso del file arriva da $w.AttachmentPath
                        # (valorizzato dentro Invoke-M365OpsAgentTools, dove $script:LastReportPath
                        # e' nello scope corretto) - MAI da $script:LastReportPath letto qui: in
                        # Server.ps1 quella variabile e' nello scope di QUESTO script, non del
                        # modulo, quindi sarebbe sempre $null per un report generato dall'AI
                        # (bug reale osservato il 17/08/2026: "Cannot bind argument to parameter
                        # 'Path' because it is null" su Split-Path).
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Invio email proposto (non ancora eseguito) ---`nDestinatario: $($w.To)`nOggetto: $($w.Subject)`nAllegato: $(Split-Path -Leaf $w.AttachmentPath)`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'SendReportEmail'; To = $w.To; Subject = $w.Subject; Body = $w.Body; AttachmentPath = $w.AttachmentPath; ConfirmText = $confirmText }
                    }
                    default {
                        $bodyText = if ($w.Body) { ($w.Body | ConvertTo-Json -Depth 6 -Compress) } else { "(nessuno)" }
                        $confirmText = "$stepPrefix$($result.Text)`n`n--- Scrittura proposta (non ancora eseguita) ---`nMetodo: $($w.Method.ToUpper())`nPercorso: $($w.Path)`nCorpo: $bodyText`nMotivo: $($w.Reason)"
                        $script:PendingAction = @{ Type = 'LokkaWrite'; Method = $w.Method; Path = $w.Path; Body = $w.Body; Reason = $w.Reason; ConfirmText = $confirmText }
                    }
                }
                return @{ role = 'ai'; text = "$confirmText`n`n(rispondi 'si' per eseguirla davvero, 'no' per annullare)" }
            }

            # Rete di sicurezza per un bug ricorrente del modello: a volte scrive "ora genero
            # il report..." come risposta finale SENZA davvero chiamare generate_report,
            # lasciando l'utente senza file e senza errore (osservato piu' volte il
            # 15/08/2026, oltre al rinforzo nel system prompt che da solo non basta sempre).
            # Se il testo promette un report ma non e' arrivato nessun allegato, lo diciamo
            # chiaramente invece di lasciar credere che sia stato fatto.
            if (-not $result.Attachments -and $result.Text -match '(?i)(genero|creo|preparo|sto generando|sto creando)\b.{0,15}\breport') {
                $result.Text += "`n`n(Nota: sembra che il report non sia stato effettivamente generato - nessun file allegato. Chiedimi di riprovare.)"
            }
            return @{ role = 'ai'; text = $result.Text; attachments = $result.Attachments }
        }
        catch {
            # Bug reale scoperto il 17/08/2026: questo catch inghiottiva l'errore ORIGINALE
            # senza mai loggarlo, poi ripiegava su una chiamata AI senza strumenti/contesto
            # (utile per un errore benigno/transitorio, ma inutile se la causa e' la stessa che
            # farebbe fallire/svuotare anche questa) - se ANCHE questa falliva o restituiva
            # vuoto, l'utente vedeva un messaggio bianco in chat senza NESSUNA riga nel log a
            # spiegare cosa fosse successo (ne' l'errore originale ne' quello del fallback).
            # Investigato a lungo esattamente per questo motivo - ora l'errore originale e'
            # sempre loggato per primo, e se anche il fallback fallisce l'utente vede l'errore
            # vero invece di un silenzio totale.
            $originalError = $_.Exception.Message
            Write-M365OpsLog "Invoke-M365OpsAgentTools fallito, ripiego su chiamata AI senza strumenti: $originalError" -Level Error
            try {
                $response = Invoke-M365OpsAgent -Prompt $msg -Provider $script:ActiveAIProvider
                if (-not $response) { throw "risposta di fallback vuota" }
                return @{ role = 'ai'; text = "$response`n`n(Nota: risposta senza accesso ai dati del tenant - il tentativo con gli strumenti e' fallito: $originalError)`n`n_Fonte: nessun dato del tenant consultato (fallback dopo un errore). Elaborata da IA: $(Get-M365OpsAiProviderLabel -Provider $script:ActiveAIProvider)._" }
            }
            catch {
                Write-M365OpsLog "Anche il fallback AI senza strumenti e' fallito: $($_.Exception.Message)" -Level Error
                return @{ role = 'error'; text = "Errore: $originalError`n`nAnche il tentativo di risposta semplificata e' fallito: $($_.Exception.Message)" }
            }
        }
    }
}

$indexHtmlPath = Join-Path $PSScriptRoot 'index.html'
$indexHtml = Get-Content $indexHtmlPath -Raw -Encoding UTF8

# Rilevamento automatico porta occupata (18/08/2026, richiesto dall'utente): se $Port e' gia'
# in uso da un altro programma, si prova in sequenza le porte successive fino a trovarne una
# libera, invece di fallire con un errore HttpListener criptico. Il test e' il vero
# $listener.Start() (non un proxy tipo TcpListener separato) - l'unico modo di sapere con
# certezza che HttpListener stesso riuscira' a legarsi, dato che usa http.sys sotto e non un
# semplice bind Socket, quindi un proxy diverso potrebbe dare falsi positivi/negativi.
$originalRequestedPort = $Port
$listener = $null
$boundOk = $false
for ($candidatePort = $Port; $candidatePort -le $Port + 20; $candidatePort++) {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$candidatePort/")
    try {
        $listener.Start()
        $Port = $candidatePort
        $boundOk = $true
        break
    } catch {
        $listener.Close()
        $listener = $null
    }
}
if (-not $boundOk) {
    Write-Host "Porta $originalRequestedPort occupata e nessuna porta libera trovata tra $originalRequestedPort e $($originalRequestedPort + 20) - impossibile avviare." -ForegroundColor Red
    exit 1
}
if ($Port -ne $originalRequestedPort) {
    Write-Host "Porta $originalRequestedPort gia' in uso da un altro programma - avviato invece sulla porta $Port." -ForegroundColor Yellow
    Write-M365OpsLog "Porta $originalRequestedPort occupata, avviato invece su $Port."
}

# Scritta SEMPRE (anche se coincide col valore richiesto): e' cosi' che Launch-M365Ops.ps1 sa
# su quale porta REALE controllare/aprire il browser, senza dover indovinare o assumere che
# coincida sempre con quella passata inizialmente.
$activePortFile = Join-Path $moduleRoot 'Config\active-port.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $activePortFile) -ErrorAction SilentlyContinue | Out-Null
Set-Content -Path $activePortFile -Value $Port -Encoding UTF8 -NoNewline

Write-Host "M365Ops web app in ascolto su http://localhost:$Port/ (Ctrl+C per fermare)" -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $response.Headers.Add("Cache-Control", "no-store")

        try {
            $routeKey = "$($request.HttpMethod) $($request.Url.AbsolutePath)"
            $responseBytes = $null
            $contentType = "application/json; charset=utf-8"

            switch ($routeKey) {
                "GET /" {
                    $contentType = "text/html; charset=utf-8"
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($indexHtml)
                }
                "GET /guida" {
                    # Aggiunto il 21/08/2026, richiesto esplicitamente dall'utente dopo un test
                    # su PC pulito: "quando l'app parte e non e' configurata la sua guida deve
                    # essere raggiungibile per essere consultata, o non fa perche' manca l'IA?".
                    # Prima di questo fix la guida era leggibile SOLO tramite kb_query dentro il
                    # motore AI (Invoke-M365OpsAgentTools) - senza una chiave AI configurata,
                    # nemmeno una domanda semplicissima come "come genero il certificato
                    # Exchange?" trovava risposta, un problema dell'uovo e della gallina (serve
                    # la guida per sapere come configurare l'AI, ma la guida richiedeva l'AI per
                    # essere letta). Servito qui staticamente, senza passare dal motore AI - una
                    # semplice URL raggiungibile con qualunque browser, anche a zero
                    # configurazione, zero chiavi API, zero tenant salvati.
                    $guidePdfFile = Join-Path $moduleRoot 'docs\Guida-Configurazione.pdf'
                    if (Test-Path $guidePdfFile) {
                        $contentType = "application/pdf"
                        $responseBytes = [System.IO.File]::ReadAllBytes($guidePdfFile)
                    } else {
                        $response.StatusCode = 404
                        $contentType = "text/plain; charset=utf-8"
                        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("Guida non trovata su questo PC (docs\Guida-Configurazione.pdf mancante).")
                    }
                }
                "GET /api/status" {
                    # pending/pendingText esposti qui cosi' un refresh della pagina puo' ridisegnare
                    # subito il banner "si'/no" in sospeso invece di lasciarlo invisibile mentre il
                    # server lo aspetta ancora davvero (bug reale: un refresh perdeva la vista sulla
                    # proposta in sospeso, un messaggio successivo rischiava di essere interpretato
                    # come risposta a una proposta che l'utente non vedeva piu' in GUI).
                    $json = @{
                        tenant      = $script:ActiveTenantProfile
                        pending     = [bool]$script:PendingAction
                        pendingText = if ($script:PendingAction) { $script:PendingAction.ConfirmText } else { $null }
                        # Nessun profilo tenant salvato ancora in Config\tenants.json (21/08/2026,
                        # richiesto esplicitamente dall'utente): la GUI usa questo per mostrare un
                        # messaggio di benvenuto/onboarding diverso al primo avvio, che indirizza al
                        # tab Impostazioni tenant - ridiventa false da solo non appena l'utente salva
                        # il primo profilo, nessun flag separato da resettare manualmente.
                        firstRun    = (@(Get-M365OpsTenantList).Count -eq 0)
                    } | ConvertTo-Json -Compress
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/chat/history" {
                    $history = @(Get-M365OpsChatHistory -TenantName $script:ActiveTenantProfile)
                    # Bug reale (16/08/2026): PIPARE un array in ConvertTo-Json (con o senza
                    # -AsArray) lo "srotola" un elemento alla volta sulla pipeline - un array
                    # vuoto non emette NESSUN oggetto, quindi il cmdlet restituisce $null vero
                    # (non la stringa "null"), e GetBytes($null) lanciava "Value cannot be null"
                    # ad ogni caricamento pagina su un tenant senza storico (es. subito dopo un
                    # riavvio). -InputObject invece lega l'intero array come UN SOLO valore,
                    # quindi ConvertTo-Json lo riconosce gia' come array e lo serializza
                    # correttamente sia vuoto ([]) sia con 1 o piu' elementi, senza bisogno di
                    # -AsArray ne' di un controllo Count separato.
                    $json = ConvertTo-Json -InputObject $history -Depth 4 -Compress
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/tenants" {
                    # -InputObject (mai pipeIato): con un solo profilo tenant configurato, la
                    # vecchia forma pipeIata avrebbe "srotolato" l'array a un singolo oggetto
                    # nudo (non [...]) - mai capitato dal vivo con 2 profili configurati, ma
                    # stesso identico bug di GET /api/chat/history (16/08/2026), corretto qui
                    # per costruzione invece di aspettare che càpiti con un solo tenant.
                    $json = ConvertTo-Json -InputObject @(Get-M365OpsTenantList) -Compress
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/tenants" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    $authMode = if ($body.authMode) { $body.authMode } else { 'AppOnly' }
                    $tenantParams = @{ Name = $body.name; TenantId = $body.tenantId; AuthMode = $authMode }
                    if ($authMode -eq 'Delegated') {
                        $tenantParams.DelegatedUpn = $body.delegatedUpn
                    } else {
                        $tenantParams.ClientId = $body.clientId
                        $tenantParams.SecretEnvVar = $body.secretEnvVar
                    }
                    if ($body.exchangeCertThumbprint) { $tenantParams.ExchangeCertThumbprint = $body.exchangeCertThumbprint }
                    try {
                        Set-M365OpsTenant @tenantParams
                        if ($body.secretValue -and $body.secretEnvVar) {
                            [System.Environment]::SetEnvironmentVariable($body.secretEnvVar, $body.secretValue, [System.EnvironmentVariableTarget]::User)
                        }
                        # Bug reale segnalato dal vivo il 21/08/2026: modificando (via "Salva
                        # profilo") il tenant GIA' ATTIVO - es. cambiando modalita' di
                        # autenticazione o altri campi - $script:M365OpsContext restava quello
                        # vecchio in memoria, e nessuno dei flag di connessione (Intune, Exchange,
                        # Teams, SharePoint, Purview) veniva resettato, perche' solo Connect-M365Ops
                        # lo fa (vedi il commento li' dentro) e questo handler non lo richiamava
                        # mai dopo il salvataggio - a differenza del gemello "POST
                        # /api/email-settings" poco sopra, che lo fa gia' correttamente. Sintomo
                        # osservato: Intune mostrato ancora "connesso" nella GUI dopo aver
                        # modificato/riattivato il profilo attivo con impostazioni diverse. Se il
                        # profilo salvato e' quello attivo, lo riattivano qui per lo stesso motivo
                        # per cui /api/tenants/activate lo fa sempre: ricaricare il contesto dal
                        # file appena scritto e chiudere/azzerare ogni sessione residua invece di
                        # lasciarla sopravvivere con dati ormai vecchi.
                        if ($script:ActiveTenantProfile -eq $body.name) {
                            Connect-M365Ops -TenantProfile $body.name
                        }
                        $json = (@{ text = "Profilo '$($body.name)' salvato [$authMode]." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/setup-status" {
                    try {
                        $items = @(Get-M365OpsSetupStatus)
                        $json = ConvertTo-Json -InputObject $items -Compress -Depth 4
                    } catch {
                        $json = ConvertTo-Json -InputObject @(@{ Name = 'Errore controllo stato'; Status = 'Missing'; Detail = $_.Exception.Message; Fix = '' }) -Compress
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/install-prerequisites" {
                    # Azione di sistema (installa software via winget), non un dato del tenant -
                    # per questo NON passa dal meccanismo di conferma propose_*/PendingAction
                    # (quello e' per le scritture sul tenant): e' un'azione locale a QUESTO PC,
                    # esplicitamente richiesta dal click sul pulsante, mai avviata da sola in
                    # background - stesso principio del pulsante "Riavvia" esistente.
                    try {
                        $items = @(Install-M365OpsPrerequisites)
                        $json = ConvertTo-Json -InputObject $items -Compress -Depth 4
                    } catch {
                        $json = ConvertTo-Json -InputObject @(@{ Name = 'Errore installazione'; Status = 'Failed'; Detail = $_.Exception.Message; Action = '' }) -Compress
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/logs" {
                    try {
                        $logFile = Join-Path $moduleRoot "Logs\m365ops-$(Get-Date -Format 'yyyyMMdd').log"
                        $lines = if (Test-Path $logFile) { @(Get-Content $logFile -Tail 200) } else { @() }
                        $json = ConvertTo-Json -InputObject $lines -Compress -Depth 2
                        if ($lines.Count -eq 0) { $json = "[]" }
                    } catch {
                        $json = ConvertTo-Json -InputObject @("Errore lettura log: $($_.Exception.Message)") -Compress
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/logs/search" {
                    try {
                        $days = 30
                        if ($request.QueryString["days"]) { [void][int]::TryParse($request.QueryString["days"], [ref]$days) }
                        $searchParams = @{ Days = $days; MaxResults = 500 }
                        if ($request.QueryString["search"]) { $searchParams.Search = $request.QueryString["search"] }
                        if ($request.QueryString["level"] -in @('Info', 'Warn', 'Error')) { $searchParams.Level = $request.QueryString["level"] }
                        if ($request.QueryString["tenant"]) { $searchParams.Tenant = $request.QueryString["tenant"] }
                        # scope=writes (27/08/2026, richiesto esplicitamente dall'utente): stesso
                        # endpoint, stessi filtri, ma legge Logs\writes-YYYYMMDD.log (solo azioni
                        # di scrittura confermate) invece del log generale - vedi
                        # Write-M365OpsWriteLog per il perche' di un file separato.
                        if ($request.QueryString["scope"] -eq 'writes') { $searchParams.LogFilePrefix = 'writes' }
                        $entries = @(Get-M365OpsLogHistory @searchParams)
                        $json = ConvertTo-Json -InputObject $entries -Compress -Depth 3
                        if ($entries.Count -eq 0) { $json = "[]" }
                    } catch {
                        $json = (@{ error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/custom-scripts" {
                    $scripts = @(Get-M365OpsCustomScriptCatalog)
                    $json = if ($scripts.Count -eq 0) { "[]" } else { ConvertTo-Json -InputObject $scripts -Compress -Depth 4 }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/delegated-login/start" {
                    try {
                        $flow = Start-M365OpsDelegatedLogin
                        $json = ($flow | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ status = 'Error'; message = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/delegated-login/poll" {
                    try {
                        $result = Complete-M365OpsDelegatedLogin
                        $json = ($result | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ Status = 'Error'; Message = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/exchange-delegated-login/start" {
                    try {
                        $flow = Start-M365OpsExchangeDelegatedLogin
                        $json = ($flow | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ status = 'Error'; message = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/exchange-delegated-login/poll" {
                    try {
                        $result = Complete-M365OpsExchangeDelegatedLogin
                        $json = ($result | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ Status = 'Error'; Message = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/sharepoint-test" {
                    # Bug reale corretto il 17/08/2026 (due bug distinti sullo stesso sintomo):
                    # (1) il precedente flusso a codice dispositivo per i tenant Delegati usava
                    # un client_id "PnP Management Shell" indovinato a memoria, mai verificato -
                    # falliva con AADSTS700016. Sostituito con -Interactive (stesso principio
                    # gia' usato per Intune, vedi /api/intune-test).
                    # (2) DOPO quella correzione, l'errore persisteva ancora: $script:M365OpsContext
                    # letto QUI (dentro Server.ps1, che non fa parte del modulo) e' sempre vuoto -
                    # quella variabile vive nello scope del modulo, popolata da Connect-M365Ops,
                    # mai da Server.ps1 stesso (stessa classe di bug di scope gia' vista piu'
                    # volte in questo progetto, es. $script:LastReportPath). isDelegated
                    # risultava quindi SEMPRE false, passando -AllowInteractive:$false anche su
                    # un tenant Delegato reale. Va letto tramite Get-M365OpsActiveTenantInfo
                    # (la funzione ponte pensata apposta per questo), mai da $script:M365OpsContext
                    # direttamente fuori dal modulo.
                    try {
                        $isDelegated = (Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated'
                        Connect-M365OpsSharePoint -Force -AllowInteractive:$isDelegated
                        $sites = @(Get-M365OpsSharePointSites)
                        $json = (@{ ok = $true; text = "Connesso. Trovati $($sites.Count) siti." } | ConvertTo-Json -Compress)
                    } catch {
                        # Diagnostica temporanea (17/08/2026): "Specified method is not supported"
                        # e' un messaggio troppo generico da solo per capire DOVE nasce dentro
                        # Connect-PnPOnline -Interactive - logga l'intera catena di eccezioni
                        # (InnerException puo' avere il vero dettaglio .NET) invece del solo
                        # messaggio superficiale.
                        $exChain = @()
                        $e = $_.Exception
                        while ($e) { $exChain += "$($e.GetType().FullName): $($e.Message)"; $e = $e.InnerException }
                        Write-M365OpsLog "SharePoint connect-test fallito - catena eccezioni: $($exChain -join ' <- ')" -Level Error
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/teams-test" {
                    # Stesso principio di /api/sharepoint-test (17/08/2026): -AllowInteractive
                    # su Delegato invece del flusso a codice dispositivo custom rimosso (client_id
                    # indovinato, mai verificato - vedi Connect-M365OpsSharePoint per il bug
                    # reale confermato sullo stesso schema). AuthMode letto tramite
                    # Get-M365OpsActiveTenantInfo, MAI $script:M365OpsContext direttamente qui -
                    # vedi il commento esteso in /api/sharepoint-test per il bug di scope reale
                    # che questo evita (isDelegated sempre false altrimenti).
                    try {
                        $isDelegated = (Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated'
                        Connect-M365OpsTeams -Force -AllowInteractive:$isDelegated
                        $teams = @(Get-M365OpsTeamsList)
                        $json = (@{ ok = $true; text = "Connesso. Trovati $($teams.Count) Team." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/teams-test-async-start" {
                    # Login Teams NON bloccante (23/08/2026, richiesto esplicitamente dal vivo
                    # dall'utente dopo un episodio scambiato per un crash del server - vedi
                    # Start-M365OpsIsolatedModuleConnectAsync per il contesto completo). Solo
                    # per Delegato: su App-only /api/teams-test esistente resta gia' rapido/
                    # silenzioso (certificato), non ha bisogno di questo percorso - il chiamante
                    # lato GUI (index.html) usa questo endpoint SOLO quando AuthMode e' Delegato.
                    try {
                        $connectParams = Get-M365OpsIsolatedConnectParams -ModuleType 'Teams'
                        $result = Start-M365OpsIsolatedModuleConnectAsync -ModuleType 'Teams' -ConnectParams $connectParams
                        $json = (@{ ok = $true; status = $result.Status } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; status = 'error'; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/teams-test-async-poll" {
                    # Controllo NON bloccante (una lettura sola, mai un'attesa) - vedi
                    # Get-M365OpsIsolatedModuleConnectAsyncStatus. Chiamato ripetutamente dalla
                    # GUI mentre il login procede nel processo isolato separato.
                    try {
                        $status = Get-M365OpsIsolatedModuleConnectAsyncStatus -ModuleType 'Teams'
                        if ($status.Status -eq 'Connected') {
                            $teams = @(Get-M365OpsTeamsList)
                            $json = (@{ ok = $true; status = 'connected'; text = "Connesso. Trovati $($teams.Count) Team." } | ConvertTo-Json -Compress)
                        } elseif ($status.Status -eq 'Error') {
                            $json = (@{ ok = $false; status = 'error'; text = "Errore: $($status.Message)" } | ConvertTo-Json -Compress)
                        } else {
                            $json = (@{ ok = $true; status = 'pending' } | ConvertTo-Json -Compress)
                        }
                    } catch {
                        $json = (@{ ok = $false; status = 'error'; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/compliance-test" {
                    # Nuovo (25/08/2026): Purview/Compliance non aveva NESSUN punto di ingresso
                    # in GUI per la modalita' Delegata - Get-M365OpsRetentionCompliancePolicies
                    # chiama Connect-M365OpsCompliance SENZA -AllowInteractive, quindi su un
                    # tenant Delegato falliva sempre con "vai al tab Tenant e connetti" senza che
                    # esistesse davvero un modo di farlo. Stesso identico principio di
                    # /api/sharepoint-test e /api/teams-test: AuthMode letto tramite
                    # Get-M365OpsActiveTenantInfo, MAI $script:M365OpsContext direttamente qui
                    # (Server.ps1 non e' parte del modulo, stesso bug di scope gia' visto altrove
                    # in questo file). Il login delegato qui e' interattivo (popup bloccante,
                    # come Teams/SharePoint), non device-code in background come Exchange -
                    # ExchangeOnlineManagement 3.4.0 (fissata per il conflitto Teams, sezione 6.6)
                    # non espone un flusso device-code su Connect-IPPSSession, solo su
                    # Connect-ExchangeOnline - vedi Connect-M365OpsCompliance.ps1 per il dettaglio.
                    try {
                        $isDelegated = (Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated'
                        Connect-M365OpsCompliance -Force -AllowInteractive:$isDelegated
                        $policies = @(Get-M365OpsRetentionCompliancePolicies)
                        $json = (@{ ok = $true; text = "Connesso. Trovate $($policies.Count) policy di conservazione." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/sharepoint-sync-app" {
                    # Endpoint manuale per Sync-M365OpsSharePointAppRegistration (17/08/2026) -
                    # utile sia come pulsante "ri-sincronizza" per un utente sia per verificare
                    # dal vivo che il discovery trovi davvero l'app via Graph e la salvi nel
                    # profilo, invece di fidarsi solo della lettura del codice.
                    try {
                        $sync = Sync-M365OpsSharePointAppRegistration
                        $json = ($sync | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ Found = $false; Status = 'Error'; Message = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/ai-status" {
                    $status = Get-M365OpsAiUsageStatus -ActiveProvider $script:ActiveAIProvider
                    $json = ($status | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/ai-status/test" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    $provider = if ($body.provider) { $body.provider } else { $script:ActiveAIProvider }
                    $result = Test-M365OpsAiConnection -Provider $provider
                    $json = ($result | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/ai-settings" {
                    $hasClaudeKey = [bool]([System.Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'User'))
                    $hasAzureKey = [bool]([System.Environment]::GetEnvironmentVariable('AZURE_OPENAI_KEY', 'User'))
                    $json = (@{ provider = $script:ActiveAIProvider; hasClaudeKey = $hasClaudeKey; hasAzureKey = $hasAzureKey } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/ai-settings" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    if ($body.provider) {
                        $script:ActiveAIProvider = $body.provider
                        # Persistito qui (non e' un segreto, solo il nome del provider) - senza
                        # questo, un riavvio del server tornava sempre a Claude come default,
                        # anche se l'utente aveva scelto Azure OpenAI.
                        @{ provider = $script:ActiveAIProvider } | ConvertTo-Json -Compress | Set-Content -Path $script:AiProviderConfigPath -Encoding UTF8
                    }
                    if ($body.apiKey) {
                        $varName = if ($body.provider -eq 'AzureOpenAI') { 'AZURE_OPENAI_KEY' } else { 'ANTHROPIC_API_KEY' }
                        [System.Environment]::SetEnvironmentVariable($varName, $body.apiKey, [System.EnvironmentVariableTarget]::User)
                    }
                    if ($body.endpoint) { [System.Environment]::SetEnvironmentVariable('AZURE_OPENAI_ENDPOINT', $body.endpoint, [System.EnvironmentVariableTarget]::User) }
                    if ($body.deployment) { [System.Environment]::SetEnvironmentVariable('AZURE_OPENAI_DEPLOYMENT', $body.deployment, [System.EnvironmentVariableTarget]::User) }
                    $json = (@{ text = "Impostazioni AI salvate (provider attivo: $($script:ActiveAIProvider))." } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/email-settings" {
                    $info = Get-M365OpsActiveTenantInfo
                    $json = (@{ emailSender = $info.EmailSender } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/email-settings" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    $info = Get-M365OpsActiveTenantInfo
                    try {
                        # BUG corretto: prima passava sempre ClientId/SecretEnvVar (vuoti su un
                        # tenant Delegato) senza -AuthMode, che quindi tornava al default
                        # 'AppOnly' - salvare l'indirizzo mittente su un tenant Delegato falliva
                        # con un errore di validazione, o peggio ne cancellava silenziosamente
                        # la configurazione (DelegatedUpn perso, tornava App-only).
                        $tenantParams = @{ Name = $info.Name; TenantId = $info.TenantId; AuthMode = $info.AuthMode; EmailSender = $body.emailSender }
                        if ($info.AuthMode -eq 'Delegated') {
                            $tenantParams.DelegatedUpn = $info.DelegatedUpn
                        } else {
                            $tenantParams.ClientId = $info.ClientId
                            $tenantParams.SecretEnvVar = $info.SecretEnvVar
                        }
                        Set-M365OpsTenant @tenantParams
                        Connect-M365Ops -TenantProfile $info.Name
                        $json = (@{ text = "Indirizzo mittente salvato: $($body.emailSender)" } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/mcp-servers" {
                    $servers = @(Get-M365OpsMcpServers | ForEach-Object { @{ name = $_.Name; command = $_.Command; args = $_.Args; builtIn = $_.BuiltIn } })
                    $json = if ($servers.Count -eq 0) { "[]" } else { ConvertTo-Json -InputObject $servers -Compress -Depth 4 }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/mcp-servers" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    Set-M365OpsMcpServer -Name $body.name -Command $body.command -Args $body.args
                    $json = (@{ text = "Server MCP '$($body.name)' salvato." } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/mcp-servers/remove" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        Remove-M365OpsMcpServer -Name $body.name
                        $json = (@{ text = "Server MCP '$($body.name)' rimosso." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/mcp-status" {
                    $info = Get-M365OpsActiveTenantInfo
                    $json = (@{
                        lokkaConnected         = $info.LokkaConnected
                        lokkaToolCount         = $info.LokkaToolCount
                        # McpServerStatus (26/08/2026): un oggetto per OGNI server MCP
                        # configurato per questo tenant (Lokka incluso), non solo Lokka -
                        # vedi Get-M365OpsActiveTenantInfo.ps1. La GUI lo usa per mostrare lo
                        # stato di server come CLI-Microsoft365, aggiunti dall'utente ma prima
                        # sempre inerti (nessun codice li connetteva mai).
                        # Where-Object { $_ } PRIMA del ForEach-Object (26/08/2026): senza,
                        # quando $info e' $null (nessun tenant attivo, Get-M365OpsActiveTenantInfo
                        # ritorna $null) "$null | ForEach-Object {...}" non produce zero
                        # iterazioni come per una collezione vuota - ne produce UNA con $_ = $null,
                        # una voce fantasma {name=null;...} - stesso identico bug di scope gia'
                        # documentato e corretto altrove in questo file per lo storico chat vuoto.
                        mcpServers             = @($info.McpServerStatus | Where-Object { $_ } | ForEach-Object { @{ name = $_.Name; builtIn = $_.BuiltIn; connected = $_.Connected; toolCount = $_.ToolCount } })
                        exchangeConfigured     = [bool]$info.ExchangeCertThumbprint
                        exchangeConnected      = $info.ExchangeConnected
                        exchangeThumbprint     = $info.ExchangeCertThumbprint
                        sharePointConnected    = $info.SharePointConnected
                        sharePointConnectedUrl = $info.SharePointConnectedUrl
                        teamsConnected         = $info.TeamsConnected
                        complianceConnected    = $info.ComplianceConnected
                        intuneConnected        = $info.IntuneConnected
                        intuneConnectedUpn     = $info.IntuneConnectedUpn
                        intuneConnectedTenant  = $info.IntuneConnectedTenant
                        authMode               = $info.AuthMode
                        delegatedUpn           = $info.DelegatedUpn
                        delegatedSessionActive = $info.DelegatedSessionActive
                    } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/lokka-reconnect" {
                    try {
                        $tools = Connect-M365OpsLokka -Force
                        $json = (@{ text = "Lokka riconnesso. Tool disponibili: $($tools.Count)." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ text = "Errore riconnettendo Lokka: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/mcp-servers/connect" {
                    # Generico (26/08/2026): a differenza di /api/lokka-reconnect (fisso su
                    # Lokka), connette QUALUNQUE server MCP configurato per nome - usato dal
                    # nuovo pulsante "Connetti/Test" per riga in "Altri server MCP" (prima
                    # quella sezione era puramente informativa, nessun codice la collegava
                    # mai al motore di ragionamento).
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        # allowInteractive (26/08/2026): richiesto SOLO dal client quando l'utente
                        # ha gia' confermato esplicitamente un login a browser bloccante (tenant
                        # Delegato su CLI-Microsoft365, vedi Connect-M365OpsCliMicrosoft365.ps1) -
                        # ignorato senza effetto da qualunque altro server MCP.
                        $allowInteractive = [bool]$body.allowInteractive
                        $tools = Connect-M365OpsMcpServer -Name $body.name -Force -AllowInteractive:$allowInteractive
                        $json = (@{ ok = $true; text = "Server MCP '$($body.name)' connesso. Tool disponibili: $($tools.Count)." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/exchange-test" {
                    try {
                        # Su tenant Delegated il login interattivo passa SEMPRE dal flusso a
                        # codice dispositivo asincrono (/api/exchange-delegated-login/start+poll,
                        # vedi Start-/Complete-M365OpsExchangeDelegatedLogin) - la GUI non chiama
                        # piu' questo endpoint per quel caso, ma il server non deve fidarsi solo
                        # del client: -AllowInteractive qui bloccherebbe l'intero processo
                        # single-threaded (l'incidente gia' diagnosticato e risolto una volta
                        # in questa sessione) se mai richiamato per un tenant Delegated.
                        # Bug reale corretto il 17/08/2026 (mai innescato finora perche' la GUI
                        # non chiama mai questo endpoint su Delegato, ma sbagliato comunque -
                        # trovato correggendo lo stesso bug su SharePoint/Teams): $script:M365OpsContext
                        # letto qui era sempre vuoto (vive nello scope del modulo, non di
                        # Server.ps1) - la condizione sotto era quindi SEMPRE false. Va letto
                        # tramite Get-M365OpsActiveTenantInfo, mai $script:M365OpsContext
                        # direttamente fuori dal modulo.
                        if ((Get-M365OpsActiveTenantInfo).AuthMode -eq 'Delegated') {
                            throw "Tenant delegato: usa il pulsante 'Connetti / Test connessione Exchange' (flusso a codice dispositivo, non bloccante) invece di questo endpoint."
                        }
                        Connect-M365OpsExchange -Force
                        $mailboxes = @(Get-M365OpsSharedMailboxes)
                        $json = (@{ ok = $true; text = "Connesso. Trovate $($mailboxes.Count) mailbox condivise." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/intune-test" {
                    try {
                        # A differenza di Exchange, IntuneWin32App non supporta un flusso
                        # asincrono a due passi (nessun parametro per iniettare un token gia'
                        # ottenuto - verificato sulla v1.5.0 installata). Su un tenant Delegated
                        # questa chiamata BLOCCA davvero il server finche' non completi il login
                        # - accettabile solo perche' e' un click esplicito e consapevole
                        # dell'utente su un pulsante dedicato (vedi Connect-M365OpsIntune), mai
                        # dentro un flusso composto automatico. Usa -Interactive (browser con
                        # selezione account), non -DeviceCode: quest'ultimo ha un bug reale nel
                        # modulo che lo rende sempre fallito su PowerShell 7 (vedi il .SYNOPSIS
                        # di Connect-M365OpsIntune). -Force per rifare sempre un login fresco su
                        # un click esplicito, anche se una connessione precedente risultasse
                        # ancora valida.
                        Connect-M365OpsIntune -Force -AllowInteractive
                        $json = (@{ ok = $true; text = "Connesso a Intune." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/analyze-headers" {
                    # Analisi intestazioni email/NDR (25/08/2026, richiesto esplicitamente
                    # dall'utente dopo un caso reale di troubleshooting NDR - replica in locale
                    # https://mha.azurewebsites.net) - nessuna chiamata AI qui, solo parsing
                    # deterministico via Get-M365OpsMessageHeaderAnalysis (Private). Il campo
                    # 'kind' e ogni sotto-oggetto usano camelCase per coerenza con ogni altra
                    # risposta JSON di questo server (Get-M365OpsMessageHeaderAnalysis stessa
                    # restituisce PascalCase, tipico convenzione PowerShell - la conversione
                    # avviene qui, unico punto di contatto con la GUI).
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        $analysis = Get-M365OpsMessageHeaderAnalysis -RawText $body.rawText
                        # rawText incluso nella risposta (25/08/2026, richiesto esplicitamente
                        # dall'utente: "vorrei avere un riferimento diretto ai raw data
                        # analizzati") - la GUI lo mostra in una sezione dedicata sotto il
                        # risultato interpretato, cosi' resta sempre visibile ESATTAMENTE cosa e'
                        # stato analizzato, senza dover riaprire/ricontrollare la casella di
                        # incolla originale.
                        $payload = [ordered]@{ ok = $true; kind = $analysis.Kind; warnings = @($analysis.Warnings); rawText = $analysis.RawText }
                        if ($analysis.Kind -eq 'Ndr') {
                            $n = $analysis.Ndr
                            $payload.ndr = [ordered]@{
                                smtpCode      = $n.SmtpCode
                                enhancedCode  = $n.EnhancedCode
                                text          = $n.Text
                                fqdn          = $n.Fqdn
                                ip            = $n.Ip
                                lastRetryTime = $n.LastRetryTime
                            }
                        } else {
                            $payload.summary = [ordered]@{
                                subject   = $analysis.Summary.Subject
                                messageId = $analysis.Summary.MessageId
                                date      = $analysis.Summary.Date
                                from      = $analysis.Summary.From
                                to        = $analysis.Summary.To
                                cc        = $analysis.Summary.Cc
                            }
                            $payload.hops = @($analysis.Hops | ForEach-Object {
                                [ordered]@{ hop = $_.Hop; from = $_.From; by = $_.By; type = $_.Type; time = $_.Time; delaySec = $_.DelaySec }
                            })
                            if ($analysis.Authentication) {
                                $payload.authentication = [ordered]@{ spf = $analysis.Authentication.Spf; dkim = $analysis.Authentication.Dkim; dmarc = $analysis.Authentication.Dmarc; compAuth = $analysis.Authentication.CompAuth }
                            }
                            if ($analysis.AntispamReport) {
                                $fieldsOut = [ordered]@{}
                                foreach ($k in $analysis.AntispamReport.Fields.Keys) {
                                    $fieldsOut[$k] = [ordered]@{ value = $analysis.AntispamReport.Fields[$k].Value; label = $analysis.AntispamReport.Fields[$k].Label }
                                }
                                $payload.antispamReport = [ordered]@{ fields = $fieldsOut }
                            }
                        }
                        $json = ($payload | ConvertTo-Json -Depth 10 -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/analyze-headers-ai" {
                    # Spiegazione in linguaggio chiaro via IA (25/08/2026) - SOLO qui, mai nel
                    # parsing sopra, il testo incollato dall'utente lascia questo PC verso l'API
                    # IA configurata (Claude/Azure OpenAI), esattamente come ogni altra funzione
                    # IA del modulo - nessuna sorpresa, il pulsante in GUI e' separato ed esplicito
                    # apposta. Il parsing locale viene rifatto qui e passato come contesto
                    # strutturato in aggiunta al testo grezzo, cosi' l'IA ragiona su un riepilogo
                    # gia' corretto (hop/ritardi/SPF-DKIM-DMARC/codice NDR) invece di doverlo
                    # ricalcolare da sola dal testo grezzo, piu' soggetto a errori su un compito
                    # essenzialmente aritmetico/di parsing.
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        $analysis = Get-M365OpsMessageHeaderAnalysis -RawText $body.rawText
                        $analysisJson = $analysis | Select-Object -ExcludeProperty RawText | ConvertTo-Json -Depth 10 -Compress
                        $prompt = "Un amministratore IT ha incollato delle intestazioni email o un blocco di diagnostica NDR di Exchange Online per capire perche' un'email non e' stata consegnata o e' arrivata in ritardo. Sotto trovi (1) l'analisi GIA' calcolata in locale (hop di consegna con ritardi, esito SPF/DKIM/DMARC, rapporto antispam, o il codice NDR se e' un rimbalzo) e (2) il testo originale incollato. Spiega in italiano semplice, per un amministratore IT non necessariamente esperto di SMTP: cosa e' successo, la causa PIU' probabile (basandoti sui dati reali sopra, non su ipotesi generiche), e i prossimi passi concreti di troubleshooting. Se l'analisi locale ha gia' segnalato delle osservazioni (campo Warnings), usale come punto di partenza principale invece di ripartire da zero. Sii specifico e concreto, non generico.`n`n--- ANALISI LOCALE (JSON) ---`n$analysisJson`n`n--- TESTO ORIGINALE INCOLLATO ---`n$($body.rawText)"
                        # -ReturnUsage (25/08/2026, richiesto esplicitamente dall'utente, con la
                        # richiesta esplicita di verificare PRIMA che non introduca rallentamenti):
                        # il conteggio token arriva GRATIS nella stessa risposta HTTP gia' attesa
                        # per il testo (campo "usage" di Claude/Azure OpenAI) - zero chiamate in
                        # piu', zero latenza aggiuntiva, verificato leggendo la struttura della
                        # risposta prima di usarla, non assunto.
                        $aiResult = Invoke-M365OpsAgent -Prompt $prompt -Provider $script:ActiveAIProvider -MaxTokens 1500 -ReturnUsage
                        $tokenNote = "$($aiResult.InputTokens) token inviati, $($aiResult.OutputTokens) ricevuti"
                        if ($aiResult.CachedTokens -gt 0) { $tokenNote += ", di cui $($aiResult.CachedTokens) dalla cache" }
                        $aiText = $aiResult.Text + "`n`n_Elaborata da IA: $(Get-M365OpsAiProviderLabel -Provider $script:ActiveAIProvider) ($tokenNote)._"
                        $json = (@{ ok = $true; text = $aiText } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/infra-diagram" {
                    # Diagramma infrastruttura (25/08/2026, richiesto esplicitamente dall'utente:
                    # sezione a parte in GUI per disegnare l'infrastruttura del proprio tenant -
                    # macchine, ruoli, IP, domain controller, Entra Connect, eventualmente ibrida
                    # - che entri anche nella KB fruibile dall'IA, vedi Invoke-M365OpsAgentTools.ps1
                    # per il tool get_tenant_infrastructure). Stesso schema per-tenant di
                    # GET /api/chat/history sopra - nessuna guardia esplicita su tenant non
                    # attivo, stesso comportamento gia' consolidato in quella route.
                    $diagram = Get-M365OpsInfraDiagram -TenantName $script:ActiveTenantProfile
                    $json = ConvertTo-Json -InputObject @{ nodes = @($diagram.Nodes); edges = @($diagram.Edges); updatedAt = $diagram.UpdatedAt } -Depth 8 -Compress
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/infra-diagram" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        Set-M365OpsInfraDiagram -TenantName $script:ActiveTenantProfile -Nodes @($body.nodes) -Edges @($body.edges) | Out-Null
                        $json = (@{ ok = $true } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/infra-diagram/export" {
                    # Export/import (25/08/2026, richiesto esplicitamente dall'utente: poter
                    # condividere un diagramma tra installazioni diverse dell'app). La passphrase
                    # e' facoltativa (stringa vuota o assente = export in chiaro) - MAI salvata,
                    # esiste solo per la durata di questa chiamata. tenantId nel pacchetto e' la
                    # STESSA chiave risolta gia' usata per salvare/leggere il diagramma (vedi
                    # Get-M365OpsTenantStorageKey) - lato import serve a confrontare "questo
                    # export appartiene al tenant attivo adesso, o a uno diverso?" senza dover
                    # ridigitare/indovinare nulla.
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        $diagram = Get-M365OpsInfraDiagram -TenantName $script:ActiveTenantProfile
                        $payload = [ordered]@{ nodes = @($diagram.Nodes); edges = @($diagram.Edges) }
                        $envelope = [ordered]@{
                            m365opsExport = 'infra-diagram-v1'
                            tenantId      = Get-M365OpsTenantStorageKey -TenantName $script:ActiveTenantProfile
                            sourceProfile = $script:ActiveTenantProfile
                            exportedAt    = (Get-Date -Format 'o')
                            encrypted     = [bool]$body.passphrase
                        }
                        if ($body.passphrase) {
                            $enc = Protect-M365OpsInfraExport -Payload $payload -Passphrase $body.passphrase
                            $envelope.kdf = $enc.kdf
                            $envelope.iterations = $enc.iterations
                            $envelope.salt = $enc.salt
                            $envelope.iv = $enc.iv
                            $envelope.hmac = $enc.hmac
                            $envelope.ciphertext = $enc.ciphertext
                        } else {
                            $envelope.diagram = $payload
                        }
                        $json = (@{ ok = $true; envelope = $envelope } | ConvertTo-Json -Depth 10 -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/infra-diagram/import" {
                    # Non salva mai da solo (coerente col principio "nessun autosave" gia' in
                    # uso per l'intero editor) - restituisce solo nodi/collegamenti pronti per il
                    # canvas, l'utente deve comunque premere "Salva" esplicitamente per persisterli
                    # su QUESTA installazione/tenant.
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        $envelope = $body.envelope
                        if (-not $envelope -or $envelope.m365opsExport -ne 'infra-diagram-v1') {
                            throw "File non riconosciuto come export di un diagramma infrastruttura M365Ops."
                        }
                        $diagram = if ($envelope.encrypted) {
                            if (-not $body.passphrase) { throw "Questo export e' cifrato - serve la passphrase usata al momento dell'esportazione." }
                            Unprotect-M365OpsInfraExport -Envelope $envelope -Passphrase $body.passphrase
                        } else {
                            $envelope.diagram
                        }
                        $currentKey = Get-M365OpsTenantStorageKey -TenantName $script:ActiveTenantProfile
                        $sameTenant = [bool]($envelope.tenantId -and ($envelope.tenantId -eq $currentKey))
                        # "| Where-Object { $_ }" invece di un semplice "@(...)" (26/08/2026, bug reale
                        # trovato durante la review sicurezza): un envelope non cifrato SENZA il campo
                        # "diagram" (mancante/manomesso) rende $diagram $null - "@($null)" in PowerShell
                        # non produce un array VUOTO ma un array con UN elemento $null dentro, che
                        # arrivava cosi' com'era al canvas GUI (renderInfraCanvas legge n.id su ogni
                        # nodo, un nodo $null vi manda un'eccezione JS non gestita). Filtrare i null
                        # qui degrada correttamente a un diagramma vuoto invece di rompere il canvas.
                        $json = (@{
                            ok            = $true
                            nodes         = @($diagram.nodes | Where-Object { $_ })
                            edges         = @($diagram.edges | Where-Object { $_ })
                            sourceProfile = $envelope.sourceProfile
                            exportedAt    = $envelope.exportedAt
                            sameTenant    = $sameTenant
                        } | ConvertTo-Json -Depth 10 -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/tenants/activate" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        Connect-M365Ops -TenantProfile $body.name
                        $script:ActiveTenantProfile = $body.name
                        $script:LastGroupId = $null
                        $script:LastAppId = $null
                        $script:PendingAction = $null
                        $json = (@{ ok = $true } | ConvertTo-Json -Compress)
                    }
                    catch {
                        $json = (@{ ok = $false; text = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/tenants/remove" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    try {
                        $result = Remove-M365OpsTenant -Name $body.name
                        $json = (@{ ok = $true; text = "Profilo '$($result.Name)' rimosso." } | ConvertTo-Json -Compress)
                    }
                    catch {
                        $json = (@{ ok = $false; text = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/chat" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    $result = Handle-ChatMessage -Message $body.message
                    # Registrato qui, un solo punto per QUALUNQUE percorso di risposta (catalogo,
                    # AI, conferma "si"/"no") - cosi' lo storico resta coerente con cio' che
                    # l'utente ha davvero visto, non solo con le risposte passate dall'AI.
                    if ($result.text) { Add-M365OpsChatHistoryTurn -TenantName $script:ActiveTenantProfile -UserText $body.message -AssistantText $result.text -Attachments $result.attachments }
                    # $script:PendingAction e' impostato come effetto collaterale dentro
                    # Handle-ChatMessage quando la risposta e' una proposta in attesa di 'si'/'no'
                    # - lo esponiamo qui cosi' la GUI puo' mostrare due pulsanti invece di
                    # costringere l'utente a scriverli a mano. $result e' gia' una Hashtable
                    # (non un PSCustomObject) - .Clone() copia le sue chiavi/valori reali,
                    # a differenza di .PSObject.Properties che su una Hashtable restituirebbe
                    # le proprieta' del tipo .NET stesso (Keys/Values/Count...), non il contenuto.
                    $resultHash = $result.Clone()
                    $resultHash['pending'] = [bool]$script:PendingAction
                    $json = $resultHash | ConvertTo-Json -Depth 6 -Compress
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/chat/reset" {
                    Clear-M365OpsChatHistory -TenantName $script:ActiveTenantProfile
                    $script:PendingAction = $null
                    $json = (@{ ok = $true } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/upload" {
                    $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    $fileBytes = [Convert]::FromBase64String($body.contentBase64)
                    $kind = if ($body.kind -eq 'icon') { 'icon' } elseif ($body.kind -eq 'migration-csv') { 'migration-csv' } else { 'app' }
                    $uploadDir = Join-Path $moduleRoot "Uploads\$kind"
                    New-Item -ItemType Directory -Force -Path $uploadDir | Out-Null
                    $safeName = Split-Path -Leaf $body.filename
                    $destPath = Join-Path $uploadDir $safeName
                    [IO.File]::WriteAllBytes($destPath, $fileBytes)

                    if ($kind -eq 'icon') {
                        $script:LoadedIconPath = $destPath
                        $msgText = "Icona caricata: $safeName. Verra' usata nel prossimo packaging."
                    } elseif ($kind -eq 'migration-csv') {
                        $script:LoadedMigrationCsvPath = $destPath
                        $emailCount = @(Get-Content $destPath | Select-Object -Skip 1 | Where-Object { $_.Trim() }).Count
                        $msgText = "CSV caricato: $safeName ($emailCount indirizzi trovati, prima colonna=EmailAddress). Ora puoi chiedermi di creare il batch di migrazione."
                    } else {
                        $script:LoadedFilePath = $destPath
                        $msgText = "File caricato: $safeName ($([math]::Round($fileBytes.Length/1MB,1)) MB). Ora puoi chiedermi di pacchettizzarlo."
                    }
                    $json = (@{ role = 'system'; text = $msgText } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/reports/download" {
                    $fileName = $request.QueryString["file"]
                    # Solo un nome file semplice e' ammesso, mai un percorso: i report vivono
                    # sempre direttamente dentro Reports\, mai in sottocartelle - questo blocca
                    # a monte qualunque tentativo di path traversal (es. "..\..\..\qualcosa").
                    if (-not $fileName -or $fileName -match '[\\/]') {
                        $response.StatusCode = 400
                        $contentType = "text/plain; charset=utf-8"
                        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("Nome file non valido.")
                    } else {
                        $filePath = Join-Path (Join-Path $moduleRoot 'Reports') $fileName
                        if (-not (Test-Path $filePath -PathType Leaf)) {
                            $response.StatusCode = 404
                            $contentType = "text/plain; charset=utf-8"
                            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("File non trovato.")
                        } else {
                            $contentType = switch ([IO.Path]::GetExtension($fileName).ToLower()) {
                                '.pdf'  { 'application/pdf' }
                                '.xlsx' { 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }
                                '.csv'  { 'text/csv' }
                                default { 'application/octet-stream' }
                            }
                            $response.Headers.Add("Content-Disposition", "attachment; filename=`"$fileName`"")
                            $responseBytes = [IO.File]::ReadAllBytes($filePath)
                        }
                    }
                }
                "POST /api/restart" {
                    $script:RestartRequested = $true
                    $json = (@{ text = "Riavvio in corso..." } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/kb/list" {
                    # Get-M365OpsActiveTenantInfo, MAI $script:M365OpsContext direttamente qui -
                    # stesso motivo di ogni altro endpoint di questo file (Server.ps1 non e' parte
                    # del modulo, il suo $script: e' un altro scope - vedi /api/sharepoint-test).
                    # Per la Knowledge Base questo NON e' solo un bug di comodo come altrove: e'
                    # la garanzia stessa di isolamento tra tenant - leggere il nome sbagliato qui
                    # significherebbe mostrare/modificare la Knowledge Base del tenant sbagliato.
                    try {
                        $tenantName = (Get-M365OpsActiveTenantInfo).Name
                        if (-not $tenantName) { throw "Nessun tenant attivo." }
                        $catalog = @(Get-M365OpsKnowledgeCatalog -TenantName $tenantName)
                        $json = (ConvertTo-Json -InputObject $catalog -Compress -Depth 4)
                    } catch {
                        $json = (@{ error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/kb/upload" {
                    try {
                        $tenantName = (Get-M365OpsActiveTenantInfo).Name
                        if (-not $tenantName) { throw "Nessun tenant attivo." }
                        $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                        $body = $reader.ReadToEnd() | ConvertFrom-Json
                        $fileBytes = [Convert]::FromBase64String($body.contentBase64)
                        $tempPath = Join-Path $env:TEMP "m365ops-kb-upload-$(Get-Date -Format 'yyyyMMddHHmmssfff')"
                        [IO.File]::WriteAllBytes($tempPath, $fileBytes)
                        try {
                            $entry = Add-M365OpsKnowledgeDocument -TenantName $tenantName -FilePath $tempPath -OriginalFileName $body.filename -Provider $script:ActiveAIProvider
                            $json = (@{ ok = $true; text = "Documento '$($entry.FileName)' aggiunto alla Knowledge Base di '$tenantName'."; entry = $entry } | ConvertTo-Json -Compress -Depth 4)
                        } finally {
                            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/kb/delete" {
                    try {
                        $tenantName = (Get-M365OpsActiveTenantInfo).Name
                        if (-not $tenantName) { throw "Nessun tenant attivo." }
                        $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                        $body = $reader.ReadToEnd() | ConvertFrom-Json
                        $result = Remove-M365OpsKnowledgeDocument -TenantName $tenantName -FileName $body.fileName
                        $json = (@{ ok = $true; text = "Documento '$($result.FileName)' rimosso." } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/update/status" {
                    try {
                        $status = Get-M365OpsUpdateStatus
                        $json = (ConvertTo-Json -InputObject $status -Compress -Depth 4)
                    } catch {
                        $json = (@{ error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/server-port" {
                    try {
                        $json = (@{ activePort = $Port; preferredPort = (Get-M365OpsServerPort) } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ error = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/server-port" {
                    try {
                        $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                        $body = $reader.ReadToEnd() | ConvertFrom-Json
                        $result = Set-M365OpsServerPort -Port ([int]$body.port)
                        $json = (@{ ok = $true; preferredPort = $result.Port } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = $_.Exception.Message } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "GET /api/update/channel" {
                    $json = (@{ channel = (Get-M365OpsUpdateChannel) } | ConvertTo-Json -Compress)
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/update/channel" {
                    try {
                        $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                        $body = $reader.ReadToEnd() | ConvertFrom-Json
                        $result = Set-M365OpsUpdateChannel -Channel $body.channel
                        $json = (@{ ok = $true; channel = $result.Channel } | ConvertTo-Json -Compress)
                    } catch {
                        $json = (@{ ok = $false; text = "Errore: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                "POST /api/update/apply" {
                    # Stessa infrastruttura di riavvio sicuro degli altri punti che la usano
                    # (POST /api/restart, salvataggio script personalizzati) - il riavvio scatta
                    # SOLO dopo che questa risposta e' gia' stata inviata, cosi' l'utente vede
                    # sempre prima l'esito del download/applicazione prima che il processo cambi.
                    try {
                        $result = Install-M365OpsUpdate
                        if ($result.Applied) {
                            $script:RestartRequested = $true
                            $json = (@{ ok = $true; text = "Aggiornato da $($result.FromVersion) a $($result.ToVersion). Riavvio in corso..."; result = $result } | ConvertTo-Json -Compress -Depth 4)
                        } else {
                            $json = (@{ ok = $true; text = $result.Reason; result = $result } | ConvertTo-Json -Compress -Depth 4)
                        }
                    } catch {
                        $json = (@{ ok = $false; text = "Errore durante l'aggiornamento: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
                    }
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                }
                default {
                    $response.StatusCode = 404
                    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("Not found")
                }
            }

            $response.ContentType = $contentType
            # try/catch dedicato (23/08/2026, bug reale segnalato dal vivo nei log: "Errore
            # interno: Exception calling 'Write' with '3' argument(s): 'Bytes to be written to
            # the stream exceed the Content-Length bytes size specified.'"): questa scrittura
            # NON aveva una protezione propria, a differenza di quella di fallback subito sotto
            # (commento del 18/08/2026 li' sotto, stesso principio) - se il client si disconnette
            # (tab chiusa, timeout del browser, fetch abortito) esattamente durante l'invio del
            # corpo della risposta, HttpListenerResponse puo' rifiutare il resto della scrittura
            # con questo identico messaggio fuorviante (parla di "Content-Length" ma la causa
            # reale e' il client sparito a meta', non un bug di conteggio byte: $responseBytes.Length
            # e' sempre coerente, costruito una riga sopra dallo stesso valore). Senza questo
            # try/catch, l'eccezione risaliva al blocco catch generico sotto, che poi tentava
            # un SECONDO Write (la risposta d'errore) sullo stesso stream gia' compromesso -
            # quel secondo tentativo falliva a sua volta con lo stesso identico errore criptico,
            # loggato come "Errore interno" allarmante anche se si tratta solo di un client gia'
            # andato via, mai un vero problema del server. Ora classificato correttamente: loggato
            # come nota informativa (Info, non Error) e la richiesta finisce qui, senza secondo
            # tentativo di scrittura ne' comparsa nel log come errore.
            try {
                $response.ContentLength64 = $responseBytes.Length
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            } catch {
                Write-M365OpsLog "Risposta non completata (client disconnesso durante l'invio, es. tab chiusa o fetch interrotto) - non e' un errore del server: $($_.Exception.Message)"
            }
        }
        catch {
            $errText = "Errore interno: $($_.Exception.Message)"
            Write-Host $errText -ForegroundColor Red
            try { Write-M365OpsLog $errText -Level Error } catch {}
            # BUG SERIO trovato dal vivo il 18/08/2026: questo intero blocco di scrittura della
            # risposta d'errore non aveva la sua PROPRIA protezione. Se l'eccezione originale
            # (catturata qui sopra) era gia' dovuta al client disconnesso a meta' scrittura
            # ("The specified network name is no longer available" - es. un client con timeout
            # breve mentre l'AI ci mette piu' tempo a rispondere), anche QUESTO tentativo di
            # scrivere una risposta d'errore falliva ("This operation cannot be performed after
            # the response has been submitted") - e quella SECONDA eccezione, senza try/catch
            # proprio, risaliva fino a fuori dal loop principale e terminava l'INTERO processo
            # del server (non solo la singola richiesta). Un client che si disconnette in
            # anticipo (tab chiusa, timeout) non deve mai poter far cadere l'app per tutti.
            try {
                $response.StatusCode = 500
                # BUG corretto: prima serializzava $errText come stringa nuda (JSON valido, ma non
                # un oggetto) - il client si aspetta sempre { role, text }, altrimenti data.text e'
                # undefined e mostra "(nessuna risposta)" anche se il server ha risposto davvero.
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes((@{ role = 'error'; text = $errText } | ConvertTo-Json -Compress))
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $errBytes.Length
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
            catch {
                # Il client e' gia' andato - non c'e' piu' nessuno a cui scrivere una risposta
                # d'errore, ma l'errore ORIGINALE e' gia' stato loggato sopra: non e' silenzio,
                # e' semplicemente accettare che questa singola richiesta non riceve risposta.
                Write-Host "Impossibile scrivere la risposta d'errore (client gia' disconnesso): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        finally {
            # try/catch aggiunto lo stesso giorno del bug sopra, stessa cautela: .Close() su una
            # connessione gia' interrotta dal client non dovrebbe lanciare, ma non c'e' motivo di
            # rischiare un altro crash dell'intero processo per un dettaglio di pulizia.
            try { $response.OutputStream.Close() } catch {}
        }

        if ($script:RestartRequested) {
            Write-Host "Riavvio richiesto dalla GUI - libero la porta e avvio una nuova istanza." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 300
            # BUG scope trovato durante l'audit del 22/08/2026 (stessa classe di
            # $script:ActiveAIProvider in Get-M365OpsSetupStatus, v0.9.26): $script:M365OpsLokkaProcess
            # e' impostato da Connect-M365OpsLokka.ps1 nello scope del MODULO, non in quello di
            # Server.ps1 - letto qui era SEMPRE $null, quindi il kill esplicito prima del riavvio
            # non uccideva mai realmente il sottoprocesso Lokka (npx), lasciandolo orfano.
            # Corretto usando la funzione ponte gia' esistente (stesso pattern di
            # Get-M365OpsActiveTenantInfo) invece di leggere la variabile fuori scope.
            # Disconnect-M365OpsAllMcpServers, non solo Disconnect-M365OpsLokka (26/08/2026):
            # da quando i processi MCP sono isolati per tenant e restano vivi in background
            # tra un cambio profilo e l'altro (vedi Connect-M365OpsMcpServer.ps1), un riavvio
            # vero del server deve comunque fermarli TUTTI (di ogni tenant visitato in questa
            # sessione, non solo quello attivo ora) prima di uscire dal processo, altrimenti
            # restano orfani esattamente come il bug originale che questo blocco correggeva.
            Disconnect-M365OpsAllMcpServers
            # Worker isolati Exchange/Teams (26/08/2026, isolamento reattivo del conflitto di
            # sezione 6.6, vedi Connect-M365OpsIsolatedModule.ps1) - stesso motivo dei server
            # MCP appena sopra, nessuno deve restare orfano dopo un riavvio vero.
            Disconnect-M365OpsAllIsolatedWorkers
            $listener.Stop()
            $exePath = (Get-Process -Id $PID).Path
            # BUG corretto: passava sempre $TenantProfile (il parametro di avvio originale,
            # es. contoso-test), non $script:ActiveTenantProfile (il tenant realmente attivo
            # al momento del riavvio) - un riavvio perdeva sempre il tenant su cui l'utente
            # aveva effettivamente lavorato, tornando silenziosamente a quello di default.
            # Output rediretto su file: la finestra e' nascosta, quindi senza questo un
            # eventuale codice device-code stampato da un modulo di terze parti (es. Intune,
            # che a differenza di Exchange non ha un flusso non bloccante) sarebbe invisibile
            # e irrecuperabile finche' il processo resta bloccato in attesa.
            $consoleLogDir = Join-Path $moduleRoot 'Logs'
            if (-not (Test-Path $consoleLogDir)) { New-Item -ItemType Directory -Force -Path $consoleLogDir | Out-Null }
            # -STA aggiunto il 17/08/2026 (bug reale): senza, pwsh gira in MTA (default) e
            # qualunque finestra di login interattivo basata su WebBrowser/WinForms (SharePoint,
            # Teams -Interactive/-UseDeviceAuthentication) fallisce con
            # "System.NotSupportedException: Specified method is not supported" - quei
            # controlli sono COM e richiedono un thread STA per essere mostrati, non lo
            # richiedono invece i flussi puramente REST (device code, certificato) gia'
            # funzionanti. Riprodotto dal vivo su Fabrikam-Prod prima di questa correzione.
            Start-Process -FilePath $exePath -ArgumentList @("-NoProfile", "-STA", "-File", $PSCommandPath, "-TenantProfile", $script:ActiveTenantProfile, "-Port", $Port) -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $consoleLogDir 'server-console.log') -RedirectStandardError (Join-Path $consoleLogDir 'server-console-error.log')
            break
        }
    }
}
catch {
    # Rete di sicurezza aggiunta il 23/08/2026 (indagine su una segnalazione dal vivo -
    # "sembra che il server sia crashato" - in quel caso specifico il server NON era
    # davvero crashato, il log confermava un login Teams riuscito tramite isolamento
    # reattivo e il client ha solo perso la connessione TCP durante un'attesa umana molto
    # lunga - ma indagando si e' notato che questo ciclo principale try{while}finally{}
    # non aveva MAI avuto un catch: qualunque eccezione che sfugge al try/catch per
    # singola richiesta piu' sotto (o che arriva da fuori quel blocco, es. da
    # $listener.GetContext() stesso) risalirebbe fino a qui SENZA essere mai loggata,
    # terminando l'intero processo in modo silenzioso e non diagnosticabile - un vero
    # crash futuro, se mai capitasse, non lascerebbe alcuna traccia utile. Logga qui
    # l'eccezione fatale PRIMA che il processo termini, cosi' la prossima volta (se
    # capita davvero) si sa almeno cosa l'ha causata, invece di doverlo indovinare dai
    # log parziali di prima del blocco.
    try {
        Write-M365OpsLog "ERRORE FATALE nel ciclo principale del server - il processo sta per terminare: $($_.Exception.GetType().FullName): $($_.Exception.Message)`n$($_.ScriptStackTrace)" -Level Error
    } catch {}
    Write-Host "ERRORE FATALE: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    $listener.Stop()
    $listener.Close()
}
