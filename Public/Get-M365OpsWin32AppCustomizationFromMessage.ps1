function Get-M365OpsWin32AppCustomizationFromMessage {
    <#
    .SYNOPSIS
        Legge il messaggio libero dell'utente e chiede all'AI di estrarre eventuali opzioni
        avanzate di packaging Win32 menzionate A PAROLE (requisiti hardware, comportamento di
        installazione/riavvio, tempo massimo, disinstallazione da available, return code, scope
        tag, dipendenze/supersedence) - richiesto esplicitamente dall'utente il 19/08/2026 dopo
        aver esteso New-M365OpsWin32App con questi parametri, per non dover sempre chiedere una
        sintassi rigida.

        SOLO ESTRAZIONE, mai invenzione: se l'utente non menziona nulla su una di queste sezioni,
        il campo corrispondente resta $null/vuoto - il chiamante (il blocco richieste composte in
        Gui\Server.ps1) usa poi i default standard per tutto cio' che resta vuoto, esattamente
        come prima di questa funzione, e aggiunge un promemoria nel testo di conferma che
        l'utente PUO' specificare queste sezioni a parole se vuole personalizzarle - non le
        propone mai di sua iniziativa con valori indovinati.
    .OUTPUTS
        pscustomobject con un campo per ciascuna opzione (tutti $null/vuoti se non menzionati):
        MinimumFreeDiskSpaceInMB, MinimumMemoryInMB, MinimumNumberOfProcessors,
        MinimumCPUSpeedInMHz (int), InstallExperience ('system'|'user'),
        DeviceRestartBehavior ('allow'|'basedOnReturnCode'|'suppress'|'force'),
        MaximumInstallationTimeInMinutes (int), AllowAvailableUninstall (bool),
        ReturnCodes (array di @{ReturnCode;Type}), ScopeTagNames (array di stringhe),
        DependsOnAppName / SupersedesAppName (stringa - nome, non id: il chiamante deve
        risolverlo con una lettura prima di usarlo, mai un id inventato),
        DependencyType ('AutoInstall'|'Detect'), SupersedenceType ('Replace'|'Update'),
        mentionedAnything (bool - true se almeno un campo e' stato trovato, usato dal chiamante
        per decidere se mostrare il promemoria "puoi personalizzare a parole" oppure no).
    #>
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider = 'Claude'
    )

    $prompt = @"
Analizza questo messaggio di un amministratore IT che sta chiedendo di pacchettizzare/distribuire un'app Win32 su Intune. Cerca SOLO le seguenti opzioni avanzate, esplicitamente menzionate nel testo - non dedurle, non inventarle se non sono nominate:

- Requisiti hardware minimi: spazio disco (MB), RAM/memoria (MB), numero di processori, velocita' CPU (MHz)
- Contesto di installazione: 'system' (di sistema, default) o 'user' (utente)
- Comportamento di riavvio dopo l'installazione: 'allow' (consenti), 'basedOnReturnCode' (in base al codice restituito), 'suppress' (sopprimi, default), 'force' (forza)
- Tempo massimo di installazione in minuti
- Se consentire la disinstallazione dall'app quando assegnata come 'available' (Company Portal)
- Codici di ritorno (return code) personalizzati e il loro significato: success, softReboot, hardReboot, retry, failed
- Nomi di Scope Tag Intune da assegnare
- Dipendenza da un'altra app gia' esistente (nome dell'altra app, e se e' 'AutoInstall' o 'Detect')
- Supersedence/sostituzione di un'altra app gia' esistente (nome dell'altra app, e se e' 'Replace' o 'Update')

Messaggio da analizzare:
"$Message"

Rispondi SOLO con un blocco JSON, nessun altro testo prima o dopo, in questo formato esatto (usa null per ogni campo NON menzionato esplicitamente nel messaggio):
{
  "minimumFreeDiskSpaceInMB": null,
  "minimumMemoryInMB": null,
  "minimumNumberOfProcessors": null,
  "minimumCpuSpeedInMHz": null,
  "installExperience": null,
  "deviceRestartBehavior": null,
  "maximumInstallationTimeInMinutes": null,
  "allowAvailableUninstall": null,
  "returnCodes": null,
  "scopeTagNames": null,
  "dependsOnAppName": null,
  "dependencyType": null,
  "supersedesAppName": null,
  "supersedenceType": null
}
"@

    try {
        $raw = Invoke-M365OpsAgent -Prompt $prompt -MaxTokens 500 -Provider $Provider
        $jsonMatch = [regex]::Match($raw, '\{[\s\S]*\}')
        if (-not $jsonMatch.Success) { throw "Nessun JSON nella risposta." }
        $parsed = $jsonMatch.Value | ConvertFrom-Json

        $result = [pscustomobject]@{
            MinimumFreeDiskSpaceInMB         = $parsed.minimumFreeDiskSpaceInMB
            MinimumMemoryInMB                = $parsed.minimumMemoryInMB
            MinimumNumberOfProcessors        = $parsed.minimumNumberOfProcessors
            MinimumCPUSpeedInMHz             = $parsed.minimumCpuSpeedInMHz
            InstallExperience                = $parsed.installExperience
            DeviceRestartBehavior            = $parsed.deviceRestartBehavior
            MaximumInstallationTimeInMinutes = $parsed.maximumInstallationTimeInMinutes
            AllowAvailableUninstall          = $parsed.allowAvailableUninstall
            ReturnCodes                      = if ($parsed.returnCodes) { @($parsed.returnCodes | ForEach-Object { @{ ReturnCode = $_.returnCode; Type = $_.type } }) } else { $null }
            ScopeTagNames                    = if ($parsed.scopeTagNames) { @($parsed.scopeTagNames) } else { $null }
            DependsOnAppName                 = $parsed.dependsOnAppName
            DependencyType                   = $parsed.dependencyType
            SupersedesAppName                = $parsed.supersedesAppName
            SupersedenceType                 = $parsed.supersedenceType
        }
        $result | Add-Member -NotePropertyName mentionedAnything -NotePropertyValue ([bool]($result.PSObject.Properties | Where-Object { $_.Name -ne 'mentionedAnything' -and $null -ne $_.Value }))
        return $result
    }
    catch {
        # Estrazione fallita/non interpretabile: nessuna opzione avanzata, il chiamante procede
        # con i default standard - mai bloccare il packaging per un problema di questa sola
        # estrazione facoltativa.
        $empty = [pscustomobject]@{
            MinimumFreeDiskSpaceInMB = $null; MinimumMemoryInMB = $null; MinimumNumberOfProcessors = $null; MinimumCPUSpeedInMHz = $null
            InstallExperience = $null; DeviceRestartBehavior = $null; MaximumInstallationTimeInMinutes = $null; AllowAvailableUninstall = $null
            ReturnCodes = $null; ScopeTagNames = $null; DependsOnAppName = $null; DependencyType = $null; SupersedesAppName = $null; SupersedenceType = $null
        }
        $empty | Add-Member -NotePropertyName mentionedAnything -NotePropertyValue $false
        return $empty
    }
}
